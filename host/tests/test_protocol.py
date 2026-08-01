import json

import pytest
from helpers import device_snapshot


def test_encode_device_snapshot_produces_compact_utf8_json() -> None:
    from agentmeter_host.protocol import encode_device_snapshot

    snapshot = device_snapshot()

    assert encode_device_snapshot(snapshot) == json.dumps(
        snapshot,
        ensure_ascii=False,
        separators=(",", ":"),
    ).encode("utf-8")


def test_encode_device_snapshot_rejects_payload_over_4096_bytes() -> None:
    from agentmeter_host.protocol import DeviceProtocolError, encode_device_snapshot

    snapshot = device_snapshot()
    snapshot["padding"] = "x" * 4_096

    with pytest.raises(DeviceProtocolError, match="4096-byte device limit"):
        encode_device_snapshot(snapshot)
