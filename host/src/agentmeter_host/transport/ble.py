from __future__ import annotations

import asyncio
import time
from collections.abc import Callable
from dataclasses import dataclass
from typing import Any, Protocol

from bleak import BleakClient, BleakScanner

from agentmeter_host.control.models import PeripheralSummary
from agentmeter_host.transport.management import (
    DEVICE_EVENT_MESSAGE_TYPE,
    MANAGEMENT_RESULT_MESSAGE_TYPE,
    ManagementError,
    ManagementProtocolError,
    ManagementReassembler,
    decode_management_document,
    encode_management_request,
    fragment_management_payload,
)

_FRAME_HEADER_SIZE = 8
_FRAME_VERSION = 1
_SNAPSHOT_MESSAGE_TYPE = 1
_ACK_MESSAGE_TYPE = 0x81

SERVICE_UUID = "a77e0001-8f7b-4f63-9a53-65f93f0d6d01"
DATA_CHARACTERISTIC_UUID = "a77e0002-8f7b-4f63-9a53-65f93f0d6d01"
STATUS_CHARACTERISTIC_UUID = "a77e0003-8f7b-4f63-9a53-65f93f0d6d01"
MANAGEMENT_REQUEST_CHARACTERISTIC_UUID = "a77e0004-8f7b-4f63-9a53-65f93f0d6d01"
DEVICE_EVENT_CHARACTERISTIC_UUID = "a77e0005-8f7b-4f63-9a53-65f93f0d6d01"

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


@dataclass(frozen=True, slots=True)
class ConnectedPeripheral:
    peripheral: PeripheralSummary
    management_available: bool


class BleBackend(Protocol):
    max_write_without_response_size: int
    management_available: bool

    async def connect(self, identifier: str | None = None) -> ConnectedPeripheral | None: ...

    async def start_notify(self, notification) -> None: ...

    async def write(self, frame: bytes) -> None: ...

    async def start_management_notify(self, notification) -> None: ...

    async def write_management(self, frame: bytes) -> None: ...

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
        clock: Callable[[], float] = time.time,
    ) -> None:
        self._name_prefix = name_prefix
        self._scan_timeout_seconds = scan_timeout_seconds
        self._scanner = scanner
        self._client_factory = client_factory
        self._clock = clock
        self._client: Any | None = None
        self._discovered: dict[str, tuple[Any, PeripheralSummary]] = {}
        self._disconnect_callback: Callable[[], None] | None = None
        self._write_lock = asyncio.Lock()
        self.max_write_without_response_size = 20
        self.management_available = False

    async def scan(self) -> tuple[PeripheralSummary, ...]:
        try:
            discovered = await self._scanner.discover(
                timeout=self._scan_timeout_seconds,
                return_adv=True,
                service_uuids=[SERVICE_UUID],
            )
        except Exception as error:
            raise TransportError(
                "Could not scan for AgentMeter displays", retryable=True
            ) from error

        matches: dict[str, tuple[Any, PeripheralSummary]] = {}
        values = discovered.values() if isinstance(discovered, dict) else discovered
        for value in values:
            if isinstance(value, tuple):
                candidate, advertisement = value
            else:
                candidate, advertisement = value, None
            advertised_name = getattr(advertisement, "local_name", None)
            name = advertised_name or getattr(candidate, "name", None) or ""
            if not name.startswith(self._name_prefix):
                continue
            identifier = str(getattr(candidate, "address", ""))
            if not identifier:
                continue
            rssi = getattr(advertisement, "rssi", None)
            if isinstance(rssi, bool) or not isinstance(rssi, int):
                rssi = None
            summary = PeripheralSummary(
                identifier=identifier,
                name=name,
                rssi=rssi,
                last_seen_epoch=int(self._clock()),
            )
            matches[identifier] = (candidate, summary)
        self._discovered = matches
        return tuple(
            sorted(
                (summary for _, summary in matches.values()),
                key=lambda item: (-(item.rssi if item.rssi is not None else -128), item.name),
            )
        )

    async def connect(self, identifier: str | None = None) -> ConnectedPeripheral:
        try:
            peripherals = await self.scan()
            if identifier is None:
                selected = peripherals[0] if peripherals else None
            else:
                selected = next(
                    (item for item in peripherals if item.identifier == identifier),
                    None,
                )
            if selected is None:
                raise TransportError(
                    f"No AgentMeter display named {self._name_prefix!r} was discovered",
                    retryable=True,
                )
            device = self._discovered[selected.identifier][0]
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
            management_request = client.services.get_characteristic(
                MANAGEMENT_REQUEST_CHARACTERISTIC_UUID
            )
            event_uuid = DEVICE_EVENT_CHARACTERISTIC_UUID
            management_event = client.services.get_characteristic(event_uuid)
            self.management_available = (
                management_request is not None and management_event is not None
            )
            return ConnectedPeripheral(selected, self.management_available)
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

    async def start_management_notify(self, notification) -> None:
        if not self.management_available:
            return
        client = self._require_client()

        def receive(_sender: object, data: bytearray) -> None:
            notification(bytes(data))

        await client.start_notify(DEVICE_EVENT_CHARACTERISTIC_UUID, receive)

    async def write(self, frame: bytes) -> None:
        async with self._write_lock:
            await self._require_client().write_gatt_char(
                DATA_CHARACTERISTIC_UUID,
                frame,
                response=False,
            )

    async def write_management(self, frame: bytes) -> None:
        if not self.management_available:
            raise TransportError(
                "The connected display does not support device management",
                retryable=False,
            )
        async with self._write_lock:
            await self._require_client().write_gatt_char(
                MANAGEMENT_REQUEST_CHARACTERISTIC_UUID,
                frame,
                response=True,
            )

    async def disconnect(self) -> None:
        client = self._client
        self._client = None
        if client is not None:
            await client.disconnect()
        self.management_available = False

    def set_disconnected_callback(self, callback: Callable[[], None]) -> None:
        self._disconnect_callback = callback

    def _require_client(self):
        if self._client is None:
            raise TransportError("AgentMeter Bluetooth display is not connected", retryable=True)
        return self._client

    def _disconnected(self, _client: object) -> None:
        self._client = None
        self.management_available = False
        if self._disconnect_callback is not None:
            self._disconnect_callback()


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
        management_timeout_seconds: float = 2,
        monotonic: Callable[[], float] = time.monotonic,
    ) -> None:
        self._backend = backend
        self._ack_timeout_seconds = ack_timeout_seconds
        self._max_attempts = max_attempts
        self._management_timeout_seconds = management_timeout_seconds
        self._monotonic = monotonic
        self._connected = False
        self._management_available = False
        self._connected_peripheral: ConnectedPeripheral | None = None
        self._ack: asyncio.Future[tuple[int, int]] | None = None
        self._management_result: asyncio.Future[dict[str, Any]] | None = None
        self._management_request_id: int | None = None
        self._management_reassembler = ManagementReassembler()
        self._operation_lock = asyncio.Lock()
        self._connect_lock = asyncio.Lock()
        self._event_capacity = 32
        self._device_event_queue: list[dict[str, Any]] = []
        self._device_event_available = asyncio.Event()
        self._closed = False
        set_callback = getattr(self._backend, "set_disconnected_callback", None)
        if set_callback is not None:
            set_callback(self._receive_disconnect)

    @property
    def management_available(self) -> bool:
        return self._management_available

    @property
    def connected_peripheral(self) -> ConnectedPeripheral | None:
        return self._connected_peripheral

    async def scan(self) -> tuple[PeripheralSummary, ...]:
        scan = getattr(self._backend, "scan", None)
        if scan is None:
            return ()
        return await scan()

    async def connect(self, identifier: str | None = None) -> ConnectedPeripheral | None:
        async with self._connect_lock:
            if self._connected:
                if identifier is None or (
                    self._connected_peripheral is not None
                    and self._connected_peripheral.peripheral.identifier == identifier
                ):
                    return self._connected_peripheral
                await self._disconnect()
            try:
                if identifier is None:
                    connected = await self._backend.connect()
                else:
                    connected = await self._backend.connect(identifier)
                await self._backend.start_notify(self._receive_notification)
                self._management_available = bool(
                    getattr(self._backend, "management_available", False)
                )
                if self._management_available:
                    start_management_notify = getattr(
                        self._backend, "start_management_notify", None
                    )
                    if start_management_notify is None:
                        self._management_available = False
                    else:
                        await start_management_notify(self._receive_management_notification)
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
            self._closed = False
            self._connected_peripheral = (
                connected if isinstance(connected, ConnectedPeripheral) else None
            )
            return self._connected_peripheral

    async def send(self, payload: bytes, *, message_id: int) -> None:
        async with self._operation_lock:
            await self._send_locked(payload, message_id=message_id)

    async def _send_locked(self, payload: bytes, *, message_id: int) -> None:
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

    async def request(self, request: dict[str, Any]) -> dict[str, Any]:
        request_id, payload = encode_management_request(request)
        async with self._operation_lock:
            await self.connect()
            if not self._management_available:
                raise TransportError(
                    "The connected display does not support device management",
                    retryable=False,
                )
            frames = fragment_management_payload(
                payload,
                message_id=request_id,
                max_write_size=self._backend.max_write_without_response_size,
            )
            self._management_request_id = request_id
            self._management_result = asyncio.get_running_loop().create_future()
            try:
                write_management = self._backend.write_management
                for frame in frames:
                    await write_management(frame)
                result = await asyncio.wait_for(
                    self._management_result,
                    timeout=self._management_timeout_seconds,
                )
            except TimeoutError:
                raise TransportError(
                    "AgentMeter did not answer the management request",
                    retryable=True,
                ) from None
            finally:
                self._management_request_id = None
                self._management_result = None
            status = result.get("status")
            if status != "ok":
                raise ManagementError(str(status or "invalidResult"), result)
            return result

    def _receive_notification(self, data: bytes) -> None:
        if len(data) != 5 or data[0] != _FRAME_VERSION or data[1] != _ACK_MESSAGE_TYPE:
            return
        ack = self._ack
        if ack is None or ack.done():
            return
        ack.set_result((int.from_bytes(data[2:4], "little"), data[4]))

    def _receive_management_notification(self, data: bytes) -> None:
        try:
            message = self._management_reassembler.push(data, now=self._monotonic())
            if message is None:
                return
            document = decode_management_document(message.payload)
            if message.message_type == MANAGEMENT_RESULT_MESSAGE_TYPE:
                request_id = document.get("requestId")
                if request_id != self._management_request_id or message.message_id != request_id:
                    raise ManagementProtocolError("management result request ID does not match")
                pending = self._management_result
                if pending is not None and not pending.done():
                    pending.set_result(document)
                return
            if message.message_type == DEVICE_EVENT_MESSAGE_TYPE:
                self._enqueue_device_event(document)
        except ManagementProtocolError as error:
            pending = self._management_result
            if pending is not None and not pending.done():
                pending.set_exception(error)

    def _enqueue_device_event(self, document: dict[str, Any]) -> None:
        event_type = document.get("type")
        if isinstance(event_type, str):
            for index in range(len(self._device_event_queue) - 1, -1, -1):
                if self._device_event_queue[index].get("type") == event_type:
                    self._device_event_queue[index] = document
                    self._device_event_available.set()
                    return
        if len(self._device_event_queue) >= self._event_capacity:
            self._device_event_queue.pop(0)
        self._device_event_queue.append(document)
        self._device_event_available.set()

    async def device_events(self):
        while not self._closed:
            while self._device_event_queue:
                yield self._device_event_queue.pop(0)
            self._device_event_available.clear()
            await self._device_event_available.wait()

    def _receive_disconnect(self) -> None:
        self._connected = False
        self._management_available = False
        self._connected_peripheral = None
        self._management_reassembler.reset()
        error = TransportError("AgentMeter Bluetooth display disconnected", retryable=True)
        if self._ack is not None and not self._ack.done():
            self._ack.set_exception(error)
        if self._management_result is not None and not self._management_result.done():
            self._management_result.set_exception(error)

    async def close(self) -> None:
        self._closed = True
        self._device_event_available.set()
        await self._disconnect()

    async def disconnect(self) -> None:
        await self._disconnect()

    async def _disconnect(self) -> None:
        if not self._connected:
            return
        self._connected = False
        self._management_available = False
        self._connected_peripheral = None
        self._management_reassembler.reset()
        await self._backend.disconnect()
