import asyncio
import json
import tempfile
from pathlib import Path

import pytest
from agentmeter_host.ipc.fake import SCENARIOS, FakeControlApi, run_fake_server
from agentmeter_host.ipc.protocol import IpcCommandError, IpcRequest


@pytest.mark.parametrize("scenario", SCENARIOS)
def test_fake_scenarios_are_deterministic_and_private(scenario: str) -> None:
    api = FakeControlApi(scenario)

    encoded = json.dumps(api.state)
    assert "@" not in encoded
    assert "token" not in encoded.lower()
    assert "prompt" not in encoded.lower()


def test_fake_server_rejects_unknown_scenario() -> None:
    with pytest.raises(ValueError, match="unknown fake-server scenario"):
        FakeControlApi("unknown")


@pytest.mark.asyncio
async def test_settings_conflict_scenario_returns_stable_error() -> None:
    api = FakeControlApi("settings-conflict")

    with pytest.raises(IpcCommandError) as error:
        await api.handle_ipc(IpcRequest("1", "settings.patch", {"alwaysOn": True}))

    assert error.value.code == "revisionConflict"


@pytest.mark.asyncio
async def test_fake_server_serves_status_without_hardware_or_collectors() -> None:
    with tempfile.TemporaryDirectory(prefix="agentmeter-fake-", dir="/tmp") as directory:
        path = Path(directory) / "bridge.sock"
        stop = asyncio.Event()
        task = asyncio.create_task(run_fake_server("connected-usb", path, stop))
        for _ in range(20):
            if path.exists():
                break
            await asyncio.sleep(0)
        reader, writer = await asyncio.open_unix_connection(path)
        writer.write(b'{"schemaVersion":1,"id":"1","type":"status.get","payload":{}}\n')
        await writer.drain()

        response = json.loads(await reader.readline())

        assert response["payload"]["connection"]["phase"] == "connected"
        writer.close()
        await writer.wait_closed()
        stop.set()
        await task
