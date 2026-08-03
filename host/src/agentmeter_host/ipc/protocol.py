from __future__ import annotations

import json
import re
from dataclasses import dataclass
from typing import Any

IPC_SCHEMA_VERSION = 1
MAXIMUM_IPC_LINE_BYTES = 65_536

COMMAND_TYPES = frozenset(
    {
        "hello",
        "status.get",
        "events.subscribe",
        "device.scan",
        "device.connect",
        "device.disconnect",
        "device.forget",
        "device.identify",
        "device.refresh",
        "settings.get",
        "settings.patch",
        "providers.refresh",
        "providers.update",
        "history.query",
        "history.clear",
        "diagnostics.get",
        "bridge.restart",
        "system.sleep",
        "system.wake",
    }
)

_SAFE_ID = re.compile(r"[A-Za-z0-9._-]{1,64}")
_SAFE_TYPE = re.compile(r"[a-z][a-z0-9]*(?:\.[a-z][a-z0-9]*)*")


class IpcProtocolError(ValueError):
    """An IPC line does not match the local protocol contract."""

    def __init__(self, code: str, message: str) -> None:
        super().__init__(message)
        self.code = code


class IpcCommandError(RuntimeError):
    """A valid IPC command could not be completed."""

    def __init__(self, code: str, message: str, *, recoverable: bool = True) -> None:
        super().__init__(message)
        self.code = code
        self.recoverable = recoverable


@dataclass(frozen=True, slots=True)
class IpcRequest:
    id: str
    type: str
    payload: dict[str, Any]


def decode_request(line: bytes) -> IpcRequest:
    if not line or len(line) > MAXIMUM_IPC_LINE_BYTES:
        raise IpcProtocolError("lineTooLarge", "IPC request exceeds 65536 bytes")
    if not line.endswith(b"\n") or b"\n" in line[:-1] or b"\r" in line:
        raise IpcProtocolError("invalidEnvelope", "IPC request must contain exactly one line")
    try:
        document = json.loads(line[:-1].decode("utf-8"))
    except UnicodeDecodeError as error:
        raise IpcProtocolError("invalidEncoding", "IPC request is not valid UTF-8") from error
    except json.JSONDecodeError as error:
        raise IpcProtocolError("invalidJson", "IPC request is not valid JSON") from error
    if not isinstance(document, dict) or set(document) != {
        "schemaVersion",
        "id",
        "type",
        "payload",
    }:
        raise IpcProtocolError("invalidEnvelope", "IPC request envelope is invalid")
    if document["schemaVersion"] != IPC_SCHEMA_VERSION:
        raise IpcProtocolError("unsupportedSchema", "IPC schema version is not supported")
    request_id = document["id"]
    if not isinstance(request_id, str) or _SAFE_ID.fullmatch(request_id) is None:
        raise IpcProtocolError("invalidId", "IPC request ID is invalid")
    request_type = document["type"]
    if not isinstance(request_type, str) or request_type not in COMMAND_TYPES:
        raise IpcProtocolError("unsupportedCommand", "IPC command is not supported")
    payload = document["payload"]
    if not isinstance(payload, dict):
        raise IpcProtocolError("invalidPayload", "IPC payload must be an object")
    return IpcRequest(id=request_id, type=request_type, payload=payload)


def result_type(command_type: str) -> str:
    if command_type == "hello":
        return "hello.result"
    noun = command_type.split(".", maxsplit=1)[0]
    return f"{noun}.result"


def encode_result(request_id: str, response_type: str, payload: object) -> bytes:
    return _encode(
        {
            "schemaVersion": IPC_SCHEMA_VERSION,
            "id": request_id,
            "type": response_type,
            "status": "ok",
            "payload": payload,
        }
    )


def encode_error(
    request_id: str,
    code: str,
    message: str,
    *,
    recoverable: bool = True,
) -> bytes:
    return _encode(
        {
            "schemaVersion": IPC_SCHEMA_VERSION,
            "id": request_id,
            "type": "error",
            "status": "error",
            "payload": {
                "code": code[:64],
                "message": message[:256],
                "recoverable": recoverable,
            },
        }
    )


def encode_event(sequence: int, event_type: str, payload: object) -> bytes:
    if sequence < 1:
        raise ValueError("event sequence must be positive")
    if _SAFE_TYPE.fullmatch(event_type) is None:
        raise ValueError("event type is invalid")
    return _encode(
        {
            "schemaVersion": IPC_SCHEMA_VERSION,
            "id": f"event-{sequence}",
            "type": event_type,
            "payload": payload,
        }
    )


def _encode(document: dict[str, object]) -> bytes:
    try:
        encoded = json.dumps(document, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    except (TypeError, ValueError) as error:
        raise ValueError("IPC payload must be JSON serializable") from error
    if len(encoded) + 1 > MAXIMUM_IPC_LINE_BYTES:
        raise ValueError("IPC response exceeds 65536 bytes")
    return encoded + b"\n"
