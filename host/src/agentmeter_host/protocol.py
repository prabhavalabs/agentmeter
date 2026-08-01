from __future__ import annotations

import json


class DeviceProtocolError(ValueError):
    """A snapshot cannot be sent using the device protocol."""


def encode_device_snapshot(snapshot: dict[str, object]) -> bytes:
    payload = json.dumps(snapshot, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    if len(payload) > 4_096:
        raise DeviceProtocolError("snapshot exceeds the 4096-byte device limit")
    return payload
