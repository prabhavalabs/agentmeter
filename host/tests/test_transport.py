from types import SimpleNamespace

import pytest


def test_fragment_payload_respects_ble_write_size_and_offsets() -> None:
    from agentmeter_host.transport.ble import fragment_payload

    frames = fragment_payload(
        b"abcdefghijklmnopqrstuvwxyz",
        message_id=7,
        max_write_size=20,
    )

    assert [len(frame) for frame in frames] == [20, 20, 10]
    assert [frame[:2] for frame in frames] == [b"\x01\x01"] * 3
    assert [int.from_bytes(frame[2:4], "little") for frame in frames] == [7, 7, 7]
    assert [int.from_bytes(frame[4:6], "little") for frame in frames] == [26, 26, 26]
    assert [int.from_bytes(frame[6:8], "little") for frame in frames] == [0, 12, 24]
    assert b"".join(frame[8:] for frame in frames) == b"abcdefghijklmnopqrstuvwxyz"


@pytest.mark.parametrize(
    ("payload", "message_id", "max_write_size", "message"),
    [
        (b"{}", 1, 19, "between 20 and 512"),
        (b"{}", 1, 513, "between 20 and 512"),
        (b"x" * 4_097, 1, 20, "4096-byte"),
        (b"{}", -1, 20, "message_id"),
        (b"{}", 65_536, 20, "message_id"),
    ],
)
def test_fragment_payload_rejects_values_outside_protocol_limits(
    payload: bytes,
    message_id: int,
    max_write_size: int,
    message: str,
) -> None:
    from agentmeter_host.transport.ble import fragment_payload

    with pytest.raises(ValueError, match=message):
        fragment_payload(
            payload,
            message_id=message_id,
            max_write_size=max_write_size,
        )


class RecordingBleBackend:
    def __init__(
        self,
        *,
        drop_ack_count: int = 0,
        status: int = 0,
        fail_write_count: int = 0,
        fail_connect_count: int = 0,
        ack_message_id_delta: int = 0,
    ) -> None:
        self.max_write_without_response_size = 20
        self.drop_ack_count = drop_ack_count
        self.status = status
        self.fail_write_count = fail_write_count
        self.fail_connect_count = fail_connect_count
        self.ack_message_id_delta = ack_message_id_delta
        self.frames: list[bytes] = []
        self.connect_count = 0
        self.disconnect_count = 0
        self._notification = None

    async def connect(self) -> None:
        self.connect_count += 1
        if self.fail_connect_count:
            self.fail_connect_count -= 1
            raise ConnectionError("Bluetooth temporarily unavailable")

    async def start_notify(self, notification) -> None:
        self._notification = notification

    async def write(self, frame: bytes) -> None:
        if self.fail_write_count:
            self.fail_write_count -= 1
            raise ConnectionError("device disconnected")
        self.frames.append(frame)
        total = int.from_bytes(frame[4:6], "little")
        offset = int.from_bytes(frame[6:8], "little")
        if offset + len(frame[8:]) != total:
            return
        if self.drop_ack_count:
            self.drop_ack_count -= 1
            return
        message_id = (int.from_bytes(frame[2:4], "little") + self.ack_message_id_delta) & 0xFFFF
        self._notification(b"\x01\x81" + message_id.to_bytes(2, "little") + bytes([self.status]))

    async def disconnect(self) -> None:
        self.disconnect_count += 1


@pytest.mark.asyncio
async def test_ble_transport_retries_the_complete_message_after_missing_ack() -> None:
    from agentmeter_host.transport.ble import BleTransport

    backend = RecordingBleBackend(drop_ack_count=1)
    transport = BleTransport(backend, ack_timeout_seconds=0.01)

    await transport.send(b"abcdefghijklmnopqrstuvwxyz", message_id=8)

    first_frame_writes = [frame for frame in backend.frames if frame[6:8] == b"\x00\x00"]
    assert len(first_frame_writes) == 2
    assert backend.connect_count == 1


@pytest.mark.asyncio
async def test_ble_transport_maps_device_nack_to_actionable_error() -> None:
    from agentmeter_host.transport.ble import BleTransport, TransportError

    backend = RecordingBleBackend(status=4)
    transport = BleTransport(backend, ack_timeout_seconds=0.01)

    with pytest.raises(TransportError, match="unsupported schema") as error:
        await transport.send(b"{}", message_id=9)

    assert error.value.retryable is False


@pytest.mark.asyncio
async def test_ble_transport_reconnects_and_restarts_after_write_disconnect() -> None:
    from agentmeter_host.transport.ble import BleTransport

    backend = RecordingBleBackend(fail_write_count=1)
    transport = BleTransport(backend, ack_timeout_seconds=0.01)

    await transport.send(b"abcdefghijklmnopqrstuvwxyz", message_id=10)

    assert backend.connect_count == 2
    assert backend.disconnect_count == 1
    assert int.from_bytes(backend.frames[0][6:8], "little") == 0


@pytest.mark.asyncio
async def test_ble_transport_retries_initial_connection_failure() -> None:
    from agentmeter_host.transport.ble import BleTransport

    backend = RecordingBleBackend(fail_connect_count=1)
    transport = BleTransport(backend, ack_timeout_seconds=0.01)

    await transport.send(b"{}", message_id=10)

    assert backend.connect_count == 2


@pytest.mark.asyncio
async def test_ble_transport_never_accepts_ack_for_another_message() -> None:
    from agentmeter_host.transport.ble import BleTransport, TransportError

    backend = RecordingBleBackend(ack_message_id_delta=1)
    transport = BleTransport(backend, ack_timeout_seconds=0.01)

    with pytest.raises(TransportError, match="did not acknowledge") as error:
        await transport.send(b"{}", message_id=11)

    assert error.value.retryable is True


@pytest.mark.asyncio
async def test_bleak_backend_discovers_agentmeter_and_uses_protocol_characteristics() -> None:
    from agentmeter_host.transport.ble import (
        DATA_CHARACTERISTIC_UUID,
        SERVICE_UUID,
        STATUS_CHARACTERISTIC_UUID,
        BleakBackend,
    )

    matching_device = SimpleNamespace(name="AgentMeter-A1B2", address="device-id")

    class Scanner:
        @staticmethod
        async def discover(**kwargs):
            assert kwargs["service_uuids"] == [SERVICE_UUID]
            return {
                "other": (
                    SimpleNamespace(name="Headphones", address="other"),
                    SimpleNamespace(local_name="Headphones", service_uuids=[SERVICE_UUID]),
                ),
                "match": (
                    matching_device,
                    SimpleNamespace(local_name="AgentMeter-A1B2", service_uuids=[SERVICE_UUID]),
                ),
            }

    class Client:
        def __init__(self) -> None:
            self.services = SimpleNamespace(
                get_characteristic=lambda uuid: SimpleNamespace(
                    uuid=uuid,
                    max_write_without_response_size=64,
                )
            )
            self.connected = False
            self.notification = None
            self.writes = []

        async def connect(self) -> None:
            self.connected = True

        async def start_notify(self, uuid, notification) -> None:
            self.notification = (uuid, notification)

        async def write_gatt_char(self, uuid, data, *, response) -> None:
            self.writes.append((uuid, data, response))

        async def disconnect(self) -> None:
            self.connected = False

    client = Client()
    selected_devices = []

    def client_factory(device, **_kwargs):
        selected_devices.append(device)
        return client

    backend = BleakBackend(
        name_prefix="AgentMeter",
        scanner=Scanner,
        client_factory=client_factory,
    )
    notifications = []

    await backend.connect()
    await backend.start_notify(notifications.append)
    client.notification[1](None, bytearray(b"ack"))
    await backend.write(b"frame")
    await backend.disconnect()

    assert selected_devices == [matching_device]
    assert backend.max_write_without_response_size == 64
    assert client.notification[0] == STATUS_CHARACTERISTIC_UUID
    assert notifications == [b"ack"]
    assert client.writes == [(DATA_CHARACTERISTIC_UUID, b"frame", False)]
    assert client.connected is False


@pytest.mark.asyncio
async def test_bleak_backend_reports_missing_display_as_retryable() -> None:
    from agentmeter_host.transport.ble import BleakBackend, TransportError

    class EmptyScanner:
        @staticmethod
        async def discover(**_kwargs):
            return {}

    backend = BleakBackend(
        name_prefix="AgentMeter",
        scanner=EmptyScanner,
        client_factory=lambda *_args, **_kwargs: None,
    )

    with pytest.raises(TransportError, match="No AgentMeter display") as error:
        await backend.connect()

    assert error.value.retryable is True


class RecordingSerialPort:
    def __init__(self, response: bytes | list[bytes]) -> None:
        self.responses = [response] if isinstance(response, bytes) else list(response)
        self.writes = []
        self.closed = False
        self.reset_count = 0

    def write(self, data: bytes) -> None:
        self.writes.append(data)

    def flush(self) -> None:
        pass

    def reset_input_buffer(self) -> None:
        self.reset_count += 1

    def readline(self) -> bytes:
        return self.responses.pop(0) if self.responses else b""

    def close(self) -> None:
        self.closed = True


@pytest.mark.asyncio
async def test_serial_transport_writes_one_json_line_and_requires_matching_ack() -> None:
    from agentmeter_host.transport.serial import SerialTransport

    serial_port = RecordingSerialPort(b"ACK 12 0\n")
    opened_with = []

    def serial_factory(**kwargs):
        opened_with.append(kwargs)
        return serial_port

    transport = SerialTransport(
        port="/dev/cu.usbmodem-test",
        serial_factory=serial_factory,
    )

    await transport.send(b'{"schemaVersion":1}', message_id=12)
    await transport.close()

    assert opened_with == [
        {
            "port": "/dev/cu.usbmodem-test",
            "baudrate": 115_200,
            "timeout": 2,
            "write_timeout": 2,
        }
    ]
    assert serial_port.writes == [b'{"schemaVersion":1}\n']
    assert serial_port.reset_count == 1
    assert serial_port.closed is True


@pytest.mark.asyncio
async def test_serial_transport_skips_firmware_diagnostics_before_ack() -> None:
    from agentmeter_host.transport.serial import SerialTransport

    serial_port = RecordingSerialPort([b"Snapshot: message=12 providers=3\n", b"ACK 12 0\n"])
    transport = SerialTransport(
        port="/dev/cu.usbmodem-test",
        serial_factory=lambda **_kwargs: serial_port,
    )

    await transport.send(b"{}", message_id=12)


@pytest.mark.asyncio
async def test_serial_transport_throttles_large_lines_for_device_receive_buffer() -> None:
    from agentmeter_host.transport.serial import SerialTransport

    serial_port = RecordingSerialPort(b"ACK 15 0\n")
    transport = SerialTransport(
        port="/dev/cu.usbmodem-test",
        serial_factory=lambda **_kwargs: serial_port,
    )

    await transport.send(b"x" * 130, message_id=15)

    assert [len(chunk) for chunk in serial_port.writes] == [64, 64, 3]
    assert b"".join(serial_port.writes) == b"x" * 130 + b"\n"


@pytest.mark.asyncio
async def test_serial_transport_rejects_device_nack() -> None:
    from agentmeter_host.transport.ble import TransportError
    from agentmeter_host.transport.serial import SerialTransport

    serial_port = RecordingSerialPort(b"ACK 13 3\n")
    transport = SerialTransport(
        port="/dev/cu.usbmodem-test",
        serial_factory=lambda **_kwargs: serial_port,
    )

    with pytest.raises(TransportError, match="status 3") as error:
        await transport.send(b"{}", message_id=13)

    assert error.value.retryable is False


@pytest.mark.asyncio
async def test_serial_transport_wraps_port_errors_for_cli_reporting() -> None:
    from agentmeter_host.transport.ble import TransportError
    from agentmeter_host.transport.serial import SerialTransport

    transport = SerialTransport(
        port="/dev/cu.missing",
        serial_factory=lambda **_kwargs: (_ for _ in ()).throw(OSError("missing")),
    )

    with pytest.raises(TransportError, match="Could not communicate") as error:
        await transport.send(b"{}", message_id=14)

    assert error.value.retryable is True
