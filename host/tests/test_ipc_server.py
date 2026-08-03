import asyncio
import json
import stat
import tempfile
from pathlib import Path

import pytest
from agentmeter_host.control.events import ControlEvent, EventBroker
from agentmeter_host.ipc.protocol import IpcCommandError
from agentmeter_host.ipc.server import IpcServer, default_ipc_path


class RecordingControlApi:
    def __init__(self) -> None:
        self.events = EventBroker()
        self.requests = []

    async def handle_ipc(self, request):
        self.requests.append(request)
        if request.type == "device.identify":
            raise IpcCommandError("notConnected", "Connect a device first")
        return {"revision": 7, "requestType": request.type}


@pytest.fixture
def socket_path():
    with tempfile.TemporaryDirectory(prefix="agentmeter-", dir="/tmp") as directory:
        yield Path(directory) / "bridge.sock"


def test_default_ipc_path_is_short_and_scoped_to_the_user() -> None:
    path = default_ipc_path(uid=501, temporary_directory="/tmp")

    assert path == Path("/tmp/agentmeter-501/bridge.sock")
    assert len(bytes(path)) < 100


@pytest.mark.asyncio
async def test_ipc_server_accepts_the_real_current_user(socket_path) -> None:
    server = IpcServer(socket_path, api=RecordingControlApi())
    await server.start()
    reader, writer = await asyncio.open_unix_connection(server.path)
    writer.write(b'{"schemaVersion":1,"id":"1","type":"hello","payload":{}}\n')
    await writer.drain()

    response = json.loads(await reader.readline())

    assert response["id"] == "1"
    assert response["type"] == "hello.result"
    writer.close()
    await writer.wait_closed()
    await server.close()


@pytest.mark.asyncio
async def test_ipc_socket_is_private_and_streams_state_events(socket_path) -> None:
    api = RecordingControlApi()
    owner_uid = socket_path.parent.stat().st_uid
    server = IpcServer(
        socket_path,
        api=api,
        current_uid=lambda: owner_uid,
        peer_uid=lambda _socket: owner_uid,
    )
    await server.start()
    reader, writer = await asyncio.open_unix_connection(server.path)
    writer.write(b'{"schemaVersion":1,"id":"1","type":"events.subscribe","payload":{}}\n')
    await writer.drain()

    subscribed = json.loads(await reader.readline())
    api.events.publish(ControlEvent("connection.changed", {"phase": "connected"}))
    event = json.loads(await reader.readline())

    assert stat.S_IMODE(server.path.parent.stat().st_mode) == 0o700
    assert stat.S_IMODE(server.path.stat().st_mode) == 0o600
    assert subscribed["type"] == "events.subscribed"
    assert event["type"] == "connection.changed"
    writer.close()
    await writer.wait_closed()
    await server.close()
    assert not server.path.exists()


@pytest.mark.asyncio
async def test_ipc_server_correlates_results_and_maps_command_errors(socket_path) -> None:
    api = RecordingControlApi()
    owner_uid = socket_path.parent.stat().st_uid
    server = IpcServer(
        socket_path,
        api=api,
        current_uid=lambda: owner_uid,
        peer_uid=lambda _socket: owner_uid,
    )
    await server.start()
    reader, writer = await asyncio.open_unix_connection(server.path)
    writer.write(b'{"schemaVersion":1,"id":"a","type":"status.get","payload":{}}\n')
    writer.write(b'{"schemaVersion":1,"id":"b","type":"device.identify","payload":{}}\n')
    await writer.drain()

    status = json.loads(await reader.readline())
    error = json.loads(await reader.readline())

    assert status["id"] == "a" and status["type"] == "status.result"
    assert error["id"] == "b" and error["payload"]["code"] == "notConnected"
    writer.close()
    await writer.wait_closed()
    await server.close()


@pytest.mark.asyncio
async def test_ipc_server_rejects_another_user_before_decoding(socket_path) -> None:
    api = RecordingControlApi()
    owner_uid = socket_path.parent.stat().st_uid
    server = IpcServer(
        socket_path,
        api=api,
        current_uid=lambda: owner_uid,
        peer_uid=lambda _socket: owner_uid + 1,
    )
    await server.start()
    reader, writer = await asyncio.open_unix_connection(server.path)
    writer.write(b'{"schemaVersion":1,"id":"1","type":"status.get","payload":{}}\n')
    await writer.drain()

    assert await reader.read() == b""
    assert api.requests == []
    writer.close()
    await writer.wait_closed()
    await server.close()


@pytest.mark.asyncio
async def test_ipc_server_refuses_to_replace_a_regular_file(socket_path) -> None:
    path = socket_path
    path.write_text("keep me")
    server = IpcServer(
        path,
        api=RecordingControlApi(),
        current_uid=lambda: path.stat().st_uid,
    )

    with pytest.raises(PermissionError, match="unsafe IPC path"):
        await server.start()

    assert path.read_text() == "keep me"
