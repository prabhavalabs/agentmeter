from __future__ import annotations

import json


class DeviceProtocolError(ValueError):
    """A snapshot cannot be sent using the device protocol."""


def project_device_snapshot(snapshot: dict[str, object]) -> dict[str, object]:
    device_snapshot = dict(snapshot)
    providers = snapshot.get("providers")
    if isinstance(providers, list):
        device_snapshot["providers"] = [
            {
                **provider,
                "windows": provider.get("windows", [])[:3],
            }
            if isinstance(provider, dict) and isinstance(provider.get("windows"), list)
            else provider
            for provider in providers
        ]
    return device_snapshot


def encode_device_snapshot(snapshot: dict[str, object]) -> bytes:
    device_snapshot = project_device_snapshot(snapshot)
    payload = json.dumps(device_snapshot, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    if len(payload) > 4_096:
        raise DeviceProtocolError("snapshot exceeds the 4096-byte device limit")
    return payload
