from __future__ import annotations

import asyncio
import time
from collections.abc import Callable
from typing import Any

import serial

from agentmeter_host.transport.ble import TransportError

_WRITE_CHUNK_BYTES = 64
_WRITE_PAUSE_SECONDS = 0.005


class SerialTransport:
    """Explicit USB serial fallback using the same device JSON payload."""

    def __init__(
        self,
        *,
        port: str,
        serial_factory: Callable[..., Any] = serial.Serial,
    ) -> None:
        self._path = port
        self._serial_factory = serial_factory
        self._port: Any | None = None

    async def send(self, payload: bytes, *, message_id: int) -> None:
        if b"\n" in payload:
            raise ValueError("serial payload must contain exactly one JSON line")
        try:
            if self._port is None:
                self._port = self._serial_factory(
                    port=self._path,
                    baudrate=115_200,
                    timeout=2,
                    write_timeout=2,
                )
            response = await asyncio.to_thread(self._exchange, payload)
        except (OSError, serial.SerialException) as error:
            await self.close()
            raise TransportError(
                "Could not communicate with the AgentMeter USB serial display",
                retryable=True,
            ) from error
        fields = response.strip().split()
        if len(fields) != 3 or fields[0] != b"ACK":
            raise TransportError(
                "AgentMeter returned an invalid serial acknowledgement",
                retryable=True,
            )
        try:
            ack_message_id = int(fields[1])
            status = int(fields[2])
        except ValueError as error:
            raise TransportError(
                "AgentMeter returned an invalid serial acknowledgement",
                retryable=True,
            ) from error
        if ack_message_id != message_id:
            raise TransportError("AgentMeter acknowledged a different snapshot", retryable=True)
        if status != 0:
            raise TransportError(
                f"AgentMeter rejected the serial snapshot with status {status}",
                retryable=False,
            )

    def _exchange(self, payload: bytes) -> bytes:
        self._port.reset_input_buffer()
        line = payload + b"\n"
        for offset in range(0, len(line), _WRITE_CHUNK_BYTES):
            self._port.write(line[offset : offset + _WRITE_CHUNK_BYTES])
            time.sleep(_WRITE_PAUSE_SECONDS)
        self._port.flush()
        deadline = time.monotonic() + 2
        while time.monotonic() < deadline:
            response = bytes(self._port.readline())
            if response.strip().startswith(b"ACK "):
                return response
            if not response:
                break
        return b""

    async def close(self) -> None:
        port = self._port
        self._port = None
        if port is not None:
            await asyncio.to_thread(port.close)
