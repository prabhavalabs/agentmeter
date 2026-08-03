from __future__ import annotations

import json
from dataclasses import dataclass
from typing import Any

FRAME_HEADER_SIZE = 8
FRAME_VERSION = 1
MANAGEMENT_REQUEST_MESSAGE_TYPE = 0x02
MANAGEMENT_RESULT_MESSAGE_TYPE = 0x82
DEVICE_EVENT_MESSAGE_TYPE = 0x83
MAXIMUM_MANAGEMENT_BYTES = 2_048


class ManagementProtocolError(ValueError):
    """A management frame or document violates protocol version 1."""


class ManagementError(RuntimeError):
    """The device rejected a correlated management request."""

    def __init__(self, status: str, result: dict[str, Any]) -> None:
        super().__init__(f"AgentMeter management request failed: {status}")
        self.status = status
        self.result = result


@dataclass(frozen=True, slots=True)
class ReassembledManagementMessage:
    message_type: int
    message_id: int
    payload: bytes


def fragment_management_payload(
    payload: bytes,
    *,
    message_id: int,
    max_write_size: int,
) -> tuple[bytes, ...]:
    if not 20 <= max_write_size <= 512:
        raise ValueError("max_write_size must be between 20 and 512 bytes")
    if not payload:
        raise ValueError("management payload cannot be empty")
    if len(payload) > MAXIMUM_MANAGEMENT_BYTES:
        raise ValueError("payload exceeds the 2048-byte device limit")
    if not 0 <= message_id <= 65_535:
        raise ValueError("message_id must be between 0 and 65535")

    fragment_size = max_write_size - FRAME_HEADER_SIZE
    frames = []
    for offset in range(0, len(payload), fragment_size):
        header = bytes((FRAME_VERSION, MANAGEMENT_REQUEST_MESSAGE_TYPE))
        header += message_id.to_bytes(2, "little")
        header += len(payload).to_bytes(2, "little")
        header += offset.to_bytes(2, "little")
        frames.append(header + payload[offset : offset + fragment_size])
    return tuple(frames)


class ManagementReassembler:
    def __init__(self, *, timeout_seconds: float = 2) -> None:
        if timeout_seconds <= 0:
            raise ValueError("timeout_seconds must be positive")
        self._timeout_seconds = timeout_seconds
        self.reset()

    def reset(self) -> None:
        self._message_type: int | None = None
        self._message_id = 0
        self._total_length = 0
        self._payload = bytearray()
        self._last_fragment_at = 0.0

    def push(
        self,
        frame: bytes,
        *,
        now: float,
    ) -> ReassembledManagementMessage | None:
        if self._message_type is not None and now - self._last_fragment_at > self._timeout_seconds:
            self.reset()
        if len(frame) <= FRAME_HEADER_SIZE or frame[0] != FRAME_VERSION:
            self.reset()
            raise ManagementProtocolError("malformed management frame")
        message_type = frame[1]
        if message_type not in {MANAGEMENT_RESULT_MESSAGE_TYPE, DEVICE_EVENT_MESSAGE_TYPE}:
            self.reset()
            raise ManagementProtocolError("unexpected management message type")
        message_id = int.from_bytes(frame[2:4], "little")
        total_length = int.from_bytes(frame[4:6], "little")
        offset = int.from_bytes(frame[6:8], "little")
        fragment = frame[FRAME_HEADER_SIZE:]
        if total_length == 0 or total_length > MAXIMUM_MANAGEMENT_BYTES:
            self.reset()
            raise ManagementProtocolError("management payload exceeds the 2048-byte limit")
        if offset + len(fragment) > total_length:
            self.reset()
            raise ManagementProtocolError("management fragment exceeds its payload")

        if offset == 0:
            self._message_type = message_type
            self._message_id = message_id
            self._total_length = total_length
            self._payload = bytearray()
        elif (
            self._message_type != message_type
            or self._message_id != message_id
            or self._total_length != total_length
            or offset != len(self._payload)
        ):
            self.reset()
            raise ManagementProtocolError("management fragments are not contiguous")

        if offset != len(self._payload):
            self.reset()
            raise ManagementProtocolError("management fragments are out of order")
        self._payload.extend(fragment)
        self._last_fragment_at = now
        if len(self._payload) != self._total_length:
            return None

        complete = ReassembledManagementMessage(
            message_type=message_type,
            message_id=message_id,
            payload=bytes(self._payload),
        )
        self.reset()
        return complete


def encode_management_request(request: dict[str, Any]) -> tuple[int, bytes]:
    request_id = request.get("requestId")
    if isinstance(request_id, bool) or not isinstance(request_id, int):
        raise ValueError("management requestId must be an integer")
    if not 0 <= request_id <= 65_535:
        raise ValueError("management requestId must be between 0 and 65535")
    try:
        payload = json.dumps(request, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    except (TypeError, ValueError) as error:
        raise ValueError("management request must be JSON serializable") from error
    if len(payload) > MAXIMUM_MANAGEMENT_BYTES:
        raise ValueError("management request exceeds the 2048-byte device limit")
    return request_id, payload


def decode_management_document(payload: bytes) -> dict[str, Any]:
    try:
        document = json.loads(payload)
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ManagementProtocolError("invalid management JSON") from error
    if not isinstance(document, dict):
        raise ManagementProtocolError("management document must be an object")
    return document
