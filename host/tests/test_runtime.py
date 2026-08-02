import asyncio
import copy
import json

import pytest
from helpers import device_snapshot


class RecordingTransport:
    def __init__(self) -> None:
        self.sent: list[tuple[dict[str, object], int]] = []
        self.closed = False

    async def send(self, payload: bytes, *, message_id: int) -> None:
        self.sent.append((json.loads(payload), message_id))

    async def close(self) -> None:
        self.closed = True


@pytest.mark.asyncio
async def test_runtime_collects_and_sends_incrementing_message_ids() -> None:
    from agentmeter_host.config import HostConfig
    from agentmeter_host.normalization import DisplayPreferences
    from agentmeter_host.runtime import BridgeRuntime

    config = HostConfig(
        poll_interval_seconds=60,
        provider_ids=("codex",),
        display=DisplayPreferences(55, (75, 90), False),
    )
    collected_ids = []

    async def collect(_config, *, message_id):
        collected_ids.append(message_id)
        return device_snapshot(message_id=message_id)

    transport = RecordingTransport()
    runtime = BridgeRuntime(config, transport, collector=collect)

    await runtime.tick()
    await runtime.tick()

    assert collected_ids == [0, 1]
    assert [(snapshot["messageId"], sent_id) for snapshot, sent_id in transport.sent] == [
        (0, 0),
        (1, 1),
    ]


@pytest.mark.asyncio
async def test_runtime_message_id_wraps_after_protocol_maximum() -> None:
    from agentmeter_host.config import HostConfig
    from agentmeter_host.normalization import DisplayPreferences
    from agentmeter_host.runtime import BridgeRuntime

    config = HostConfig(
        poll_interval_seconds=60,
        provider_ids=("codex",),
        display=DisplayPreferences(55, (75, 90), False),
    )

    async def collect(_config, *, message_id):
        return device_snapshot(message_id=message_id)

    runtime = BridgeRuntime(config, RecordingTransport(), collector=collect)
    runtime.message_id = 65_535

    await runtime.tick()

    assert runtime.message_id == 0


@pytest.mark.asyncio
async def test_runtime_keeps_polling_after_a_transient_collection_failure() -> None:
    from agentmeter_host.config import HostConfig
    from agentmeter_host.normalization import DisplayPreferences
    from agentmeter_host.runtime import BridgeRuntime

    config = HostConfig(
        poll_interval_seconds=60,
        provider_ids=("codex",),
        display=DisplayPreferences(55, (75, 90), False),
    )
    attempts = 0

    async def collect(_config, *, message_id):
        nonlocal attempts
        attempts += 1
        if attempts == 1:
            raise RuntimeError("provider temporarily unavailable")
        return device_snapshot(message_id=message_id)

    transport = RecordingTransport()
    runtime = BridgeRuntime(config, transport, collector=collect)
    stop_event = asyncio.Event()
    waits = []
    errors = []

    async def wait(seconds: float) -> None:
        waits.append(seconds)
        if len(waits) == 2:
            stop_event.set()

    await runtime.run(stop_event, wait=wait, on_error=errors.append)

    assert attempts == 2
    assert len(transport.sent) == 1
    assert waits == [60, 60]
    assert [str(error) for error in errors] == ["provider temporarily unavailable"]


@pytest.mark.asyncio
async def test_run_bridge_once_sends_live_snapshot_and_closes_transport() -> None:
    from agentmeter_host.config import HostConfig
    from agentmeter_host.normalization import DisplayPreferences
    from agentmeter_host.runtime import run_bridge

    config = HostConfig(
        poll_interval_seconds=60,
        provider_ids=("codex",),
        display=DisplayPreferences(55, (75, 90), False),
    )
    transport = RecordingTransport()

    async def collect(_config, *, message_id):
        return device_snapshot(message_id=message_id)

    await run_bridge(
        config,
        once=True,
        transport_factory=lambda _config: transport,
        collector=collect,
    )

    assert [sent_id for _snapshot, sent_id in transport.sent] == [0]
    assert transport.closed is True


@pytest.mark.asyncio
async def test_run_bridge_continuously_polls_until_stop_event() -> None:
    from agentmeter_host.config import HostConfig
    from agentmeter_host.normalization import DisplayPreferences
    from agentmeter_host.runtime import run_bridge

    config = HostConfig(
        poll_interval_seconds=60,
        provider_ids=("codex",),
        display=DisplayPreferences(55, (75, 90), False),
    )
    transport = RecordingTransport()
    stop_event = asyncio.Event()

    async def collect(_config, *, message_id):
        return device_snapshot(message_id=message_id)

    async def wait(_seconds: float) -> None:
        stop_event.set()

    await run_bridge(
        config,
        once=False,
        transport_factory=lambda _config: transport,
        collector=collect,
        stop_event=stop_event,
        wait=wait,
    )

    assert [sent_id for _snapshot, sent_id in transport.sent] == [0]
    assert transport.closed is True


@pytest.mark.asyncio
async def test_run_bridge_reuses_one_collection_session_across_polls() -> None:
    from agentmeter_host.config import HostConfig
    from agentmeter_host.normalization import DisplayPreferences
    from agentmeter_host.runtime import run_bridge

    config = HostConfig(
        poll_interval_seconds=60,
        provider_ids=("claude",),
        display=DisplayPreferences(55, (75, 90), False),
    )
    transport = RecordingTransport()
    stop_event = asyncio.Event()

    class RecordingCollectionSession:
        def __init__(self) -> None:
            self.enter_count = 0
            self.exit_count = 0
            self.collected_ids: list[int] = []

        async def __aenter__(self):
            self.enter_count += 1
            return self

        async def __aexit__(self, *_args) -> None:
            self.exit_count += 1

        async def collect(self, _config, *, message_id: int):
            self.collected_ids.append(message_id)
            snapshot = device_snapshot(message_id=message_id)
            snapshot["providers"][0]["id"] = "claude"
            snapshot["providers"][0]["name"] = "Claude"
            return snapshot

    session = RecordingCollectionSession()
    wait_count = 0

    async def wait(_seconds: float) -> None:
        nonlocal wait_count
        wait_count += 1
        if wait_count == 2:
            stop_event.set()

    await run_bridge(
        config,
        once=False,
        transport_factory=lambda _config: transport,
        collector_session_factory=lambda _config: session,
        stop_event=stop_event,
        wait=wait,
    )

    assert session.enter_count == 1
    assert session.exit_count == 1
    assert session.collected_ids == [0, 1]
    assert [sent_id for _snapshot, sent_id in transport.sent] == [0, 1]


@pytest.mark.asyncio
async def test_runtime_keeps_last_good_provider_windows_during_transient_error() -> None:
    from agentmeter_host.config import HostConfig
    from agentmeter_host.normalization import DisplayPreferences
    from agentmeter_host.runtime import BridgeRuntime

    config = HostConfig(
        poll_interval_seconds=60,
        provider_ids=("claude",),
        display=DisplayPreferences(55, (75, 90), False),
    )
    good = device_snapshot(message_id=0)
    good["providers"][0].update(
        {
            "id": "claude",
            "name": "Claude",
            "windows": [
                {
                    "kind": "weekly",
                    "label": "Weekly",
                    "usedPercent": 84,
                    "resetAtEpoch": 1_785_614_400,
                }
            ],
        }
    )
    failed = copy.deepcopy(good)
    failed["messageId"] = 1
    failed["generatedAtEpoch"] += 60
    failed["providers"][0]["status"] = "error"
    failed["providers"][0]["windows"] = []
    snapshots = iter((good, failed))

    async def collect(_config, *, message_id):
        return next(snapshots)

    transport = RecordingTransport()
    runtime = BridgeRuntime(config, transport, collector=collect)

    await runtime.tick()
    await runtime.tick()

    recovered = transport.sent[1][0]["providers"][0]
    assert recovered == {
        "id": "claude",
        "name": "Claude",
        "status": "stale",
        "windows": [
            {
                "kind": "weekly",
                "label": "Weekly",
                "usedPercent": 84,
                "resetAtEpoch": 1_785_614_400,
            }
        ],
    }


@pytest.mark.asyncio
async def test_runtime_expires_last_good_provider_windows_after_one_hour() -> None:
    from agentmeter_host.config import HostConfig
    from agentmeter_host.normalization import DisplayPreferences
    from agentmeter_host.runtime import BridgeRuntime

    config = HostConfig(
        poll_interval_seconds=60,
        provider_ids=("claude",),
        display=DisplayPreferences(55, (75, 90), False),
    )
    good = device_snapshot(message_id=0)
    good["providers"][0].update({"id": "claude", "name": "Claude"})
    failed = copy.deepcopy(good)
    failed["messageId"] = 1
    failed["generatedAtEpoch"] += 3_601
    failed["providers"][0]["status"] = "error"
    failed["providers"][0]["windows"] = []
    snapshots = iter((good, failed))

    async def collect(_config, *, message_id):
        return next(snapshots)

    transport = RecordingTransport()
    runtime = BridgeRuntime(config, transport, collector=collect)

    await runtime.tick()
    await runtime.tick()

    expired = transport.sent[1][0]["providers"][0]
    assert expired["status"] == "error"
    assert expired["windows"] == []
