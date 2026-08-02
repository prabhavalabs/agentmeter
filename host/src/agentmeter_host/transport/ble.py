from __future__ import annotations

import asyncio
from collections.abc import Callable
from typing import Any, Protocol

from bleak import BleakClient, BleakScanner

_FRAME_HEADER_SIZE = 8
_FRAME_VERSION = 1
_SNAPSHOT_MESSAGE_TYPE = 1
_ACK_MESSAGE_TYPE = 0x81

SERVICE_UUID = "a77e0001-8f7b-4f63-9a53-65f93f0d6d01"
DATA_CHARACTERISTIC_UUID = "a77e0002-8f7b-4f63-9a53-65f93f0d6d01"
STATUS_CHARACTERISTIC_UUID = "a77e0003-8f7b-4f63-9a53-65f93f0d6d01"

_ACK_STATUS_MESSAGES = {
    1: "malformed frame",
    2: "payload too large",
    3: "invalid JSON",
    4: "unsupported schema",
    5: "invalid snapshot model",
}


class TransportError(RuntimeError):
    """A snapshot could not be delivered to the display."""

    def __init__(self, message: str, *, retryable: bool) -> None:
        super().__init__(message)
        self.retryable = retryable


class BleBackend(Protocol):
    max_write_without_response_size: int

    async def connect(self) -> None: ...

    async def start_notify(self, notification) -> None: ...

    async def write(self, frame: bytes) -> None: ...

    async def disconnect(self) -> None: ...


class BleakBackend:
    """Bleak adapter that discovers and connects to one AgentMeter display."""

    def __init__(
        self,
        *,
        name_prefix: str = "AgentMeter",
        scan_timeout_seconds: float = 10,
        scanner: Any = BleakScanner,
        client_factory: Callable[..., Any] = BleakClient,
    ) -> None:
        self._name_prefix = name_prefix
        self._scan_timeout_seconds = scan_timeout_seconds
        self._scanner = scanner
        self._client_factory = client_factory
        self._client: Any | None = None
        self.max_write_without_response_size = 20

    async def connect(self) -> None:
        try:
            discovered = await self._scanner.discover(
                timeout=self._scan_timeout_seconds,
                return_adv=True,
                service_uuids=[SERVICE_UUID],
            )
            device = next(
                (
                    candidate
                    for candidate, advertisement in discovered.values()
                    if (advertisement.local_name or candidate.name or "").startswith(
                        self._name_prefix
                    )
                ),
                None,
            )
            if device is None:
                raise TransportError(
                    f"No AgentMeter display named {self._name_prefix!r} was discovered",
                    retryable=True,
                )
            client = self._client_factory(device, disconnected_callback=self._disconnected)
            self._client = client
            await client.connect()
            characteristic = client.services.get_characteristic(DATA_CHARACTERISTIC_UUID)
            if characteristic is None:
                await client.disconnect()
                raise TransportError(
                    "The discovered display does not expose the AgentMeter data characteristic",
                    retryable=False,
                )
            write_size = int(characteristic.max_write_without_response_size)
            if not 20 <= write_size <= 512:
                await client.disconnect()
                raise TransportError(
                    "The display reported an unsupported Bluetooth write size",
                    retryable=False,
                )
            self.max_write_without_response_size = write_size
        except TransportError:
            raise
        except Exception as error:
            raise TransportError(
                "Could not connect to the AgentMeter Bluetooth display",
                retryable=True,
            ) from error

    async def start_notify(self, notification) -> None:
        client = self._require_client()

        def receive(_sender: object, data: bytearray) -> None:
            notification(bytes(data))

        await client.start_notify(STATUS_CHARACTERISTIC_UUID, receive)

    async def write(self, frame: bytes) -> None:
        await self._require_client().write_gatt_char(
            DATA_CHARACTERISTIC_UUID,
            frame,
            response=False,
        )

    async def disconnect(self) -> None:
        client = self._client
        self._client = None
        if client is not None:
            await client.disconnect()

    def _require_client(self):
        if self._client is None:
            raise TransportError("AgentMeter Bluetooth display is not connected", retryable=True)
        return self._client

    def _disconnected(self, _client: object) -> None:
        self._client = None


def fragment_payload(
    payload: bytes,
    *,
    message_id: int,
    max_write_size: int,
) -> tuple[bytes, ...]:
    if not 20 <= max_write_size <= 512:
        raise ValueError("max_write_size must be between 20 and 512 bytes")
    if len(payload) > 4_096:
        raise ValueError("payload exceeds the 4096-byte device limit")
    if not 0 <= message_id <= 65_535:
        raise ValueError("message_id must be between 0 and 65535")

    fragment_size = max_write_size - _FRAME_HEADER_SIZE
    frames = []
    for offset in range(0, len(payload), fragment_size):
        header = bytes((_FRAME_VERSION, _SNAPSHOT_MESSAGE_TYPE))
        header += message_id.to_bytes(2, "little")
        header += len(payload).to_bytes(2, "little")
        header += offset.to_bytes(2, "little")
        frames.append(header + payload[offset : offset + fragment_size])
    return tuple(frames)


class BleTransport:
    def __init__(
        self,
        backend: BleBackend,
        *,
        ack_timeout_seconds: float = 2,
        max_attempts: int = 3,
    ) -> None:
        self._backend = backend
        self._ack_timeout_seconds = ack_timeout_seconds
        self._max_attempts = max_attempts
        self._connected = False
        self._ack: asyncio.Future[tuple[int, int]] | None = None

    async def connect(self) -> None:
        if self._connected:
            return
        try:
            await self._backend.connect()
            await self._backend.start_notify(self._receive_notification)
        except TransportError:
            await self._backend.disconnect()
            raise
        except Exception as error:
            await self._backend.disconnect()
            raise TransportError(
                "Could not connect to the AgentMeter Bluetooth display",
                retryable=True,
            ) from error
        self._connected = True

    async def send(self, payload: bytes, *, message_id: int) -> None:
        for attempt in range(self._max_attempts):
            try:
                await self.connect()
                frames = fragment_payload(
                    payload,
                    message_id=message_id,
                    max_write_size=self._backend.max_write_without_response_size,
                )
                self._ack = asyncio.get_running_loop().create_future()
                for frame in frames:
                    await self._backend.write(frame)
                ack_message_id, status = await asyncio.wait_for(
                    self._ack,
                    timeout=self._ack_timeout_seconds,
                )
            except TimeoutError:
                if attempt + 1 == self._max_attempts:
                    raise TransportError(
                        "AgentMeter did not acknowledge the snapshot",
                        retryable=True,
                    ) from None
                continue
            except TransportError as error:
                await self._disconnect()
                if not error.retryable or attempt + 1 == self._max_attempts:
                    raise
                continue
            except Exception as error:
                await self._disconnect()
                if attempt + 1 == self._max_attempts:
                    raise TransportError(
                        "Bluetooth connection failed while sending the snapshot",
                        retryable=True,
                    ) from error
                continue
            if ack_message_id != message_id:
                if attempt + 1 == self._max_attempts:
                    raise TransportError(
                        "AgentMeter did not acknowledge the snapshot",
                        retryable=True,
                    )
                continue
            if status != 0:
                message = _ACK_STATUS_MESSAGES.get(status, f"unknown status {status}")
                raise TransportError(
                    f"AgentMeter rejected the snapshot: {message}",
                    retryable=False,
                )
            return

        raise TransportError("AgentMeter did not acknowledge the snapshot", retryable=True)

    def _receive_notification(self, data: bytes) -> None:
        if len(data) != 5 or data[0] != _FRAME_VERSION or data[1] != _ACK_MESSAGE_TYPE:
            return
        ack = self._ack
        if ack is None or ack.done():
            return
        ack.set_result((int.from_bytes(data[2:4], "little"), data[4]))

    async def close(self) -> None:
        await self._disconnect()

    async def _disconnect(self) -> None:
        if not self._connected:
            return
        self._connected = False
        await self._backend.disconnect()
