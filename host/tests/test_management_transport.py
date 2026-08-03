from __future__ import annotations

import asyncio
import json
from typing import Any

import pytest
from agentmeter_host.control.models import PeripheralSummary
from agentmeter_host.transport.management import (
    DEVICE_EVENT_MESSAGE_TYPE,
    FRAME_HEADER_SIZE,
    FRAME_VERSION,
    MANAGEMENT_RESULT_MESSAGE_TYPE,
    ManagementError,
    ManagementProtocolError,
    ManagementReassembler,
    fragment_management_payload,
)


def response_frames(
    document: dict[str, Any],
    *,
    message_type: int,
    message_id: int,
    maximum_size: int = 24,
) -> tuple[bytes, ...]:
    payload = json.dumps(document, separators=(",", ":")).encode()
    fragment_size = maximum_size - FRAME_HEADER_SIZE
    result = []
    for offset in range(0, len(payload), fragment_size):
        header = bytes((FRAME_VERSION, message_type))
        header += message_id.to_bytes(2, "little")
        header += len(payload).to_bytes(2, "little")
        header += offset.to_bytes(2, "little")
        result.append(header + payload[offset : offset + fragment_size])
    return tuple(result)


def test_fragment_management_request_uses_type_02_and_2048_limit() -> None:
    frames = fragment_management_payload(
        b'{"schemaVersion":1}',
        message_id=17,
        max_write_size=20,
    )

    assert frames[0][0:2] == bytes((1, 0x02))
    assert int.from_bytes(frames[0][2:4], "little") == 17
    assert b"".join(frame[8:] for frame in frames) == b'{"schemaVersion":1}'
    with pytest.raises(ValueError, match="2048"):
        fragment_management_payload(b"x" * 2_049, message_id=18, max_write_size=64)


def test_management_reassembler_accepts_fragmented_result_and_event() -> None:
    reassembler = ManagementReassembler()
    result_frames = response_frames(
        {"requestId": 17, "status": "ok"},
        message_type=MANAGEMENT_RESULT_MESSAGE_TYPE,
        message_id=17,
    )

    complete = None
    for index, frame in enumerate(result_frames):
        complete = reassembler.push(frame, now=float(index))

    assert complete is not None
    assert complete.message_type == MANAGEMENT_RESULT_MESSAGE_TYPE
    assert json.loads(complete.payload)["requestId"] == 17

    event_frame = response_frames(
        {"type": "device.state", "payload": {}},
        message_type=DEVICE_EVENT_MESSAGE_TYPE,
        message_id=4,
        maximum_size=64,
    )[0]
    event = reassembler.push(event_frame, now=5)
    assert event is not None
    assert event.message_type == DEVICE_EVENT_MESSAGE_TYPE


def test_management_reassembler_rejects_out_of_order_and_expired_fragments() -> None:
    frames = response_frames(
        {"requestId": 17, "status": "ok"},
        message_type=MANAGEMENT_RESULT_MESSAGE_TYPE,
        message_id=17,
    )
    reassembler = ManagementReassembler(timeout_seconds=2)

    with pytest.raises(ManagementProtocolError, match="contiguous"):
        reassembler.push(frames[1], now=0)

    reassembler.push(frames[0], now=0)
    with pytest.raises(ManagementProtocolError, match="contiguous"):
        reassembler.push(frames[1], now=3)


class ManagedBackend:
    max_write_without_response_size = 32
    management_available = True

    def __init__(
        self,
        *,
        result_status: str = "ok",
        result_id_delta: int = 0,
        drop_first_management_response: bool = False,
    ) -> None:
        self.result_status = result_status
        self.result_id_delta = result_id_delta
        self.drop_first_management_response = drop_first_management_response
        self.link_healthy = True
        self.connect_count = 0
        self.disconnect_count = 0
        self.snapshot_frames: list[bytes] = []
        self.management_frames: list[bytes] = []
        self.operations: list[str] = []
        self._snapshot_notification = None
        self._management_notification = None
        self._disconnect_callback = None

    def set_disconnected_callback(self, callback) -> None:
        self._disconnect_callback = callback

    async def scan(self):
        return (PeripheralSummary("device-1", "AgentMeter-0001", -42, 1_000),)

    async def connect(self, _identifier: str | None = None):
        self.connect_count += 1
        self.management_available = True
        self.link_healthy = True
        self.management_frames.clear()
        return None

    async def start_notify(self, notification) -> None:
        self._snapshot_notification = notification

    async def start_management_notify(self, notification) -> None:
        self._management_notification = notification

    async def write(self, frame: bytes) -> None:
        self.operations.append("snapshot")
        self.snapshot_frames.append(frame)
        await asyncio.sleep(0)
        total = int.from_bytes(frame[4:6], "little")
        if int.from_bytes(frame[6:8], "little") + len(frame[8:]) == total:
            message_id = int.from_bytes(frame[2:4], "little")
            acknowledgement = b"\x01\x81" + message_id.to_bytes(2, "little") + b"\x00"
            self._snapshot_notification(acknowledgement)

    async def write_management(self, frame: bytes) -> None:
        self.operations.append("management")
        if not self.link_healthy:
            return
        self.management_frames.append(frame)
        await asyncio.sleep(0)
        total = int.from_bytes(frame[4:6], "little")
        if int.from_bytes(frame[6:8], "little") + len(frame[8:]) != total:
            return
        if self.drop_first_management_response:
            self.drop_first_management_response = False
            self.link_healthy = False
            return
        request_payload = b"".join(item[8:] for item in self.management_frames)
        request = json.loads(request_payload)
        result_id = request["requestId"] + self.result_id_delta
        result = {
            "schemaVersion": 1,
            "requestId": result_id,
            "type": "device.result",
            "status": self.result_status,
            "payload": {},
        }
        for response in response_frames(
            result,
            message_type=MANAGEMENT_RESULT_MESSAGE_TYPE,
            message_id=request["requestId"],
        ):
            self._management_notification(response)

    async def disconnect(self) -> None:
        self.disconnect_count += 1


@pytest.mark.asyncio
async def test_snapshot_and_management_share_one_connection_and_do_not_interleave() -> None:
    from agentmeter_host.transport.ble import BleTransport

    backend = ManagedBackend()
    transport = BleTransport(backend)
    request = {
        "schemaVersion": 1,
        "requestId": 17,
        "type": "device.get",
        "payload": {},
    }

    snapshot_task = asyncio.create_task(transport.send(b"x" * 80, message_id=8))
    management_task = asyncio.create_task(transport.request(request))
    result = await management_task
    await snapshot_task

    transitions = [
        operation
        for index, operation in enumerate(backend.operations)
        if index == 0 or operation != backend.operations[index - 1]
    ]
    assert transitions == ["snapshot", "management"]
    assert backend.connect_count == 1
    assert result["requestId"] == 17


@pytest.mark.asyncio
async def test_management_request_rejects_wrong_correlated_request_id() -> None:
    from agentmeter_host.transport.ble import BleTransport

    transport = BleTransport(ManagedBackend(result_id_delta=1))

    with pytest.raises(ManagementProtocolError, match="request ID"):
        await transport.request(
            {
                "schemaVersion": 1,
                "requestId": 18,
                "type": "settings.get",
                "payload": {},
            }
        )


@pytest.mark.asyncio
async def test_management_request_preserves_device_error_result() -> None:
    from agentmeter_host.transport.ble import BleTransport

    transport = BleTransport(ManagedBackend(result_status="revisionConflict"))

    with pytest.raises(ManagementError) as error:
        await transport.request(
            {
                "schemaVersion": 1,
                "requestId": 19,
                "type": "settings.patch",
                "payload": {"baseRevision": 7, "alwaysOn": True},
            }
        )

    assert error.value.status == "revisionConflict"
    assert error.value.result["requestId"] == 19


@pytest.mark.asyncio
async def test_management_timeout_reconnects_before_the_next_request() -> None:
    from agentmeter_host.transport.ble import BleTransport, TransportError

    backend = ManagedBackend(drop_first_management_response=True)
    transport = BleTransport(backend, management_timeout_seconds=0.01)
    request = {
        "schemaVersion": 1,
        "requestId": 20,
        "type": "device.get",
        "payload": {},
    }

    with pytest.raises(TransportError, match="did not answer"):
        await transport.request(request)

    result = await transport.request(request)

    assert result["requestId"] == 20


@pytest.mark.asyncio
async def test_device_events_are_reassembled_and_coalesced() -> None:
    from agentmeter_host.transport.ble import BleTransport

    backend = ManagedBackend()
    transport = BleTransport(backend)
    await transport.connect()
    stream = transport.device_events()
    for battery_percent in (60, 59):
        event = {
            "schemaVersion": 1,
            "type": "device.state",
            "payload": {"telemetry": {"batteryPercent": battery_percent}},
        }
        for frame in response_frames(
            event,
            message_type=DEVICE_EVENT_MESSAGE_TYPE,
            message_id=battery_percent,
        ):
            backend._management_notification(frame)

    received = await anext(stream)

    assert received["payload"]["telemetry"]["batteryPercent"] == 59
    await stream.aclose()
