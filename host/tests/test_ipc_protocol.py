import json

import pytest
from agentmeter_host.ipc.protocol import (
    COMMAND_TYPES,
    IpcProtocolError,
    decode_request,
    encode_error,
    encode_event,
    encode_result,
)


def request_line(**changes) -> bytes:
    document = {
        "schemaVersion": 1,
        "id": "request-1",
        "type": "status.get",
        "payload": {},
    }
    document.update(changes)
    return json.dumps(document).encode() + b"\n"


def test_decode_status_request() -> None:
    request = decode_request(request_line())

    assert request.id == "request-1"
    assert request.type == "status.get"
    assert request.payload == {}


@pytest.mark.parametrize("command", sorted(COMMAND_TYPES | {"history.summary"}))
def test_decode_accepts_every_documented_command(command: str) -> None:
    assert decode_request(request_line(type=command)).type == command


@pytest.mark.parametrize(
    ("line", "code"),
    [
        (request_line(schemaVersion=2), "unsupportedSchema"),
        (request_line(id=""), "invalidId"),
        (request_line(id="x" * 65), "invalidId"),
        (request_line(type="unknown.command"), "unsupportedCommand"),
        (request_line(payload=[]), "invalidPayload"),
        (b"\xff\n", "invalidEncoding"),
        (b"{}\n{}\n", "invalidEnvelope"),
        (b"x" * 65_537, "lineTooLarge"),
    ],
)
def test_decode_rejects_invalid_envelopes(line: bytes, code: str) -> None:
    with pytest.raises(IpcProtocolError) as error:
        decode_request(line)

    assert error.value.code == code


def test_encoders_create_bounded_correlated_lines() -> None:
    result = json.loads(encode_result("request-1", "status.result", {"revision": 2}))
    error = json.loads(encode_error("request-2", "notConnected", "Connect first"))
    event = json.loads(encode_event(3, "connection.changed", {"phase": "connected"}))

    assert result["id"] == "request-1" and result["status"] == "ok"
    assert error["id"] == "request-2" and error["payload"]["code"] == "notConnected"
    assert event["id"] == "event-3" and "status" not in event
