from __future__ import annotations

import asyncio
import copy
import json
from dataclasses import replace

import pytest
from agentmeter_host.config import HostConfig
from agentmeter_host.control.controller import BridgeController
from agentmeter_host.control.events import EventBroker
from agentmeter_host.control.history import HistoryStore
from agentmeter_host.control.models import ConnectionPhase, PeripheralSummary
from agentmeter_host.control.settings import ControlSettingsStore
from agentmeter_host.ipc.protocol import IpcCommandError, IpcRequest
from agentmeter_host.normalization import DisplayPreferences
from agentmeter_host.transport.ble import ConnectedPeripheral, TransportError
from agentmeter_host.transport.management import ManagementError
from helpers import device_snapshot


def device_settings(*, revision: int = 8, always_on: bool = False) -> dict:
    return {
        "revision": revision,
        "alwaysOn": always_on,
        "fullView": False,
        "rotationSeconds": 3,
        "brightnessPercent": 55,
        "dimAfterSeconds": 300,
        "screenOffAfterSeconds": 1_800,
        "alertThresholds": [75, 90],
        "soundEnabled": False,
        "hiddenProviderIds": ["gemini"],
        "providerOrder": ["codex", "claude", "cursor"],
    }


def device_state(*, revision: int = 8, always_on: bool = False) -> dict:
    return {
        "information": {
            "model": "waveshare-amoled-216",
            "name": "AgentMeter-0001",
            "firmwareVersion": "0.1.0",
            "hardwareRevision": "1",
            "snapshotSchemaVersion": 1,
            "managementSchemaVersion": 1,
            "capabilities": {
                "settings": True,
                "identify": True,
                "restart": True,
                "forget": True,
                "brightness": True,
                "battery": True,
                "vbusVoltage": True,
                "inputCurrent": False,
            },
        },
        "telemetry": {
            "uptimeSeconds": 3_600,
            "freeHeapBytes": 183_520,
            "minimumFreeHeapBytes": 172_408,
            "displayOn": True,
            "displayDimmed": False,
            "brightnessPercent": 55,
            "powerSource": "usb",
            "usbPresent": True,
            "batteryPresent": False,
            "charging": None,
            "batteryVoltageMv": None,
            "batteryPercent": None,
            "vbusVoltageMv": 5_012,
            "inputCurrentMa": None,
            "boardTemperatureC": None,
        },
        "settings": device_settings(revision=revision, always_on=always_on),
    }


class FakeCollectorSession:
    def __init__(self, snapshot, *, failure: Exception | None = None) -> None:
        self.snapshot = snapshot
        self.failure = failure
        self.entered = False
        self.exited = False

    async def __aenter__(self):
        self.entered = True
        return self

    async def __aexit__(self, *_args):
        self.exited = True

    async def collect(self, _config, *, message_id: int):
        if self.failure is not None:
            raise self.failure
        result = copy.deepcopy(self.snapshot)
        result["messageId"] = message_id
        return result


class SequenceCollectorFactory:
    def __init__(self, *outcomes) -> None:
        self.outcomes = list(outcomes)
        self.sessions = []

    def __call__(self, _config):
        outcome = self.outcomes.pop(0) if len(self.outcomes) > 1 else self.outcomes[0]
        if isinstance(outcome, Exception):
            session = FakeCollectorSession(None, failure=outcome)
        else:
            session = FakeCollectorSession(outcome)
        self.sessions.append(session)
        return session


class FakeManagedTransport:
    def __init__(
        self,
        *,
        management_available: bool = True,
        state: dict | None = None,
        connect_failures: int = 0,
    ) -> None:
        self.management_available = management_available
        self.device_state = state or device_state()
        self.connect_failures = connect_failures
        self.operations = []
        self.sent = []
        self.connected = False
        self.closed = False
        self.settings_conflict = False
        self.send_failure: TransportError | None = None
        self._events = asyncio.Queue()

    async def scan(self):
        self.operations.append("scan")
        return (PeripheralSummary("device-1", "AgentMeter-0001", -42, 1_000),)

    async def connect(self, identifier=None):
        self.operations.append(f"connect:{identifier}")
        if self.connect_failures:
            self.connect_failures -= 1
            raise TransportError("temporarily unavailable", retryable=True)
        self.connected = True
        return ConnectedPeripheral(
            PeripheralSummary(identifier or "device-1", "AgentMeter-0001", -42, 1_000),
            self.management_available,
        )

    async def send(self, payload: bytes, *, message_id: int) -> None:
        self.operations.append(f"send:{message_id}")
        if self.send_failure is not None:
            raise self.send_failure
        self.sent.append(json.loads(payload))

    async def request(self, request):
        command = request["type"]
        self.operations.append(f"request:{command}")
        if command == "device.get":
            payload = copy.deepcopy(self.device_state)
        elif command == "settings.get":
            payload = copy.deepcopy(self.device_state["settings"])
        elif command == "settings.patch":
            if self.settings_conflict:
                result = {
                    "requestId": request["requestId"],
                    "status": "revisionConflict",
                    "payload": copy.deepcopy(self.device_state["settings"]),
                }
                raise ManagementError("revisionConflict", result)
            patch = request["payload"]
            settings = self.device_state["settings"]
            for key, value in patch.items():
                if key != "baseRevision":
                    settings[key] = value
            settings["revision"] += 1
            payload = copy.deepcopy(settings)
        else:
            payload = {}
        return {
            "schemaVersion": 1,
            "requestId": request["requestId"],
            "type": f"{command.split('.')[0]}.result",
            "status": "ok",
            "payload": payload,
        }

    async def device_events(self):
        while True:
            event = await self._events.get()
            yield event

    async def emit(self, event):
        await self._events.put(event)

    async def disconnect(self):
        self.operations.append("disconnect")
        self.connected = False

    async def close(self):
        self.closed = True


def make_controller(
    tmp_path,
    *,
    transport=None,
    collector_factory=None,
    settings_transform=None,
    sleep=asyncio.sleep,
    clock=lambda: 1_785_607_200,
):
    config = HostConfig(
        poll_interval_seconds=60,
        provider_ids=("codex", "claude"),
        display=DisplayPreferences(55, (75, 90), False),
    )
    settings_store = ControlSettingsStore(tmp_path / "control-state-v1.json")
    if settings_transform is not None:
        settings_store.save(settings_transform(settings_store.load(config)))
    history = HistoryStore(tmp_path / "history.sqlite3")
    controller = BridgeController(
        config,
        transport or FakeManagedTransport(),
        settings_store,
        history,
        EventBroker(),
        collector_session_factory=(
            collector_factory or SequenceCollectorFactory(device_snapshot())
        ),
        clock=clock,
        sleep=sleep,
        jitter=lambda _delay: 0,
    )
    return controller, settings_store, history


@pytest.mark.asyncio
async def test_history_ipc_accepts_bucketed_queries(tmp_path) -> None:
    controller, _settings_store, history = make_controller(tmp_path)
    history.record_usage("claude", "session", 3_610, 11, 9_000)
    history.record_usage("claude", "session", 3_900, 12, 9_000)

    result = await controller.handle_ipc(
        IpcRequest(
            id="history-1",
            type="history.query",
            payload={"sinceEpoch": 3_600, "bucketSeconds": 3_600},
        )
    )

    assert result["usage"] == [
        {
            "providerId": "claude",
            "windowKind": "session",
            "sampledAtEpoch": 3_900,
            "usedPercent": 12,
            "resetAtEpoch": 9_000,
        }
    ]
    history.close()


@pytest.mark.asyncio
async def test_history_summary_ipc_returns_widget_contract(tmp_path) -> None:
    controller, _settings_store, history = make_controller(tmp_path)
    history.record_usage("claude", "session", 1_788_249_600, 11, 1_788_336_000)

    result = await controller.handle_ipc(
        IpcRequest(
            id="summary-1",
            type="history.summary",
            payload={
                "sinceEpoch": 1_788_249_600,
                "providerId": "claude",
                "timeZoneIdentifier": "Europe/Berlin",
            },
        )
    )

    assert set(result) == {"historyStartEpoch", "days"}
    history.close()


@pytest.mark.parametrize(
    "payload",
    [
        {"sinceEpoch": 1_788_249_600, "providerId": "claude"},
        {
            "sinceEpoch": 1_788_249_600,
            "providerId": "claude",
            "timeZoneIdentifier": "Europe/Berlin",
            "limit": 7,
        },
        {
            "sinceEpoch": True,
            "providerId": "claude",
            "timeZoneIdentifier": "Europe/Berlin",
        },
        {
            "sinceEpoch": 1_788_249_600,
            "providerId": "Claude!",
            "timeZoneIdentifier": "Europe/Berlin",
        },
        {
            "sinceEpoch": 1_788_249_600,
            "providerId": "claude",
            "timeZoneIdentifier": "Not/AZone",
        },
        {
            "sinceEpoch": 1_788_249_600,
            "providerId": "claude",
            "timeZoneIdentifier": 123,
        },
        {
            "sinceEpoch": 1_788_249_600,
            "providerId": "claude",
            "timeZoneIdentifier": True,
        },
        {
            "sinceEpoch": 1_788_249_600,
            "providerId": "claude",
            "timeZoneIdentifier": None,
        },
    ],
    ids=[
        "missing-key",
        "extra-key",
        "boolean-epoch",
        "invalid-provider",
        "invalid-zone",
        "integer-zone",
        "boolean-zone",
        "null-zone",
    ],
)
@pytest.mark.asyncio
async def test_history_summary_ipc_rejects_invalid_payloads(tmp_path, payload) -> None:
    controller, _settings_store, history = make_controller(tmp_path)

    with pytest.raises(IpcCommandError) as error:
        await controller.handle_ipc(
            IpcRequest(id="summary-invalid", type="history.summary", payload=payload)
        )

    assert error.value.code == "invalidPayload"
    history.close()


@pytest.mark.asyncio
async def test_cached_provider_keeps_last_successful_update_time(tmp_path) -> None:
    good = device_snapshot(message_id=0)
    failed = copy.deepcopy(good)
    failed["generatedAtEpoch"] += 60
    failed["providers"][0]["status"] = "error"
    failed["providers"][0]["windows"] = []
    controller, _settings_store, history = make_controller(
        tmp_path,
        collector_factory=SequenceCollectorFactory(good, failed),
    )

    await controller.refresh_providers(send_to_device=False)
    await controller.refresh_providers(send_to_device=False)

    provider = controller.state.providers[0]
    assert provider.status == "ok"
    assert provider.updated_at_epoch == good["generatedAtEpoch"]
    history.close()


@pytest.mark.asyncio
async def test_controller_connects_syncs_and_publishes_confirmed_state(tmp_path) -> None:
    transport = FakeManagedTransport(state=device_state(revision=8))
    controller, _settings_store, history = make_controller(tmp_path, transport=transport)

    await controller.connect("device-1")

    assert controller.state.connection.phase is ConnectionPhase.CONNECTED
    assert controller.state.settings.revision == 8
    assert transport.operations == [
        "connect:device-1",
        "request:device.get",
        "request:settings.get",
        "send:0",
    ]
    assert transport.sent[0]["providers"][0]["id"] == "codex"
    history.close()


@pytest.mark.asyncio
async def test_legacy_firmware_still_receives_snapshots_with_management_unavailable(
    tmp_path,
) -> None:
    transport = FakeManagedTransport(management_available=False)
    controller, _settings_store, history = make_controller(tmp_path, transport=transport)

    await controller.connect("device-1")

    assert controller.state.connection.phase is ConnectionPhase.CONNECTED
    assert controller.state.connection.management_available is False
    assert controller.state.settings is None
    assert not any(operation.startswith("request:") for operation in transport.operations)
    assert transport.operations[-1] == "send:0"
    history.close()


@pytest.mark.asyncio
async def test_scan_does_not_replace_a_healthy_connected_phase(tmp_path) -> None:
    transport = FakeManagedTransport()
    controller, _settings_store, history = make_controller(tmp_path, transport=transport)
    await controller.connect("device-1")

    await controller.scan()

    assert controller.state.connection.phase is ConnectionPhase.CONNECTED
    assert controller.state.connection.management_available is True
    assert controller.state.settings is not None
    history.close()


@pytest.mark.asyncio
async def test_completed_scan_returns_a_saved_but_disconnected_device_to_stopped(
    tmp_path,
) -> None:
    controller, _settings_store, history = make_controller(
        tmp_path,
        settings_transform=lambda settings: replace(
            settings,
            selected_device_id="device-1",
            selected_device_name="AgentMeter-0001",
        ),
    )

    await controller.scan()

    assert controller.state.connection.phase is ConnectionPhase.STOPPED
    history.close()


@pytest.mark.asyncio
async def test_settings_patch_is_persisted_until_firmware_confirms(tmp_path) -> None:
    transport = FakeManagedTransport(state=device_state(revision=8))
    controller, settings_store, history = make_controller(tmp_path, transport=transport)
    await controller.connect("device-1")

    result = await controller.patch_settings({"baseRevision": 8, "alwaysOn": True})

    assert result["syncStatus"] == "synced"
    assert controller.state.settings.revision == 9
    assert controller.state.settings.always_on is True
    assert settings_store.load(controller._base_config).pending_device_patch is None
    history.close()


@pytest.mark.asyncio
async def test_revision_conflict_updates_state_and_preserves_reapply_patch(tmp_path) -> None:
    transport = FakeManagedTransport(state=device_state(revision=9))
    controller, settings_store, history = make_controller(tmp_path, transport=transport)
    await controller.connect("device-1")
    transport.settings_conflict = True

    with pytest.raises(IpcCommandError) as error:
        await controller.patch_settings({"baseRevision": 8, "alwaysOn": True})

    assert error.value.code == "revisionConflict"
    assert controller.state.settings.revision == 9
    pending = settings_store.load(controller._base_config).pending_device_patch
    assert pending is not None and pending.values == {"alwaysOn": True}
    history.close()


@pytest.mark.asyncio
async def test_touchscreen_device_event_updates_settings_immediately(tmp_path) -> None:
    transport = FakeManagedTransport()
    controller, _settings_store, history = make_controller(tmp_path, transport=transport)
    await controller.connect("device-1")
    consumer = asyncio.create_task(controller._consume_device_events())
    changed = device_state(revision=9, always_on=True)

    await transport.emit({"type": "device.state", "payload": changed})
    for _ in range(10):
        if controller.state.settings.revision == 9:
            break
        await asyncio.sleep(0)

    assert controller.state.settings.always_on is True
    consumer.cancel()
    await asyncio.gather(consumer, return_exceptions=True)
    history.close()


@pytest.mark.asyncio
async def test_provider_failure_does_not_change_healthy_ble_phase(tmp_path) -> None:
    transport = FakeManagedTransport()
    collectors = SequenceCollectorFactory(
        device_snapshot(),
        RuntimeError("raw provider response must not escape"),
    )
    controller, _settings_store, history = make_controller(
        tmp_path,
        transport=transport,
        collector_factory=collectors,
    )
    await controller.connect("device-1")

    with pytest.raises(IpcCommandError) as error:
        await controller.refresh_providers()

    assert error.value.code == "providerRefreshFailed"
    assert controller.state.connection.phase is ConnectionPhase.CONNECTED
    assert controller.state.bridge.last_error_code == "providerRefreshFailed"
    assert "raw provider" not in json.dumps(controller.diagnostics())
    history.close()


@pytest.mark.asyncio
async def test_overlapping_provider_refreshes_share_one_collection_when_disconnected(
    tmp_path,
) -> None:
    started = asyncio.Event()
    release = asyncio.Event()

    class BlockingCollector:
        calls = 0

        async def __aenter__(self):
            return self

        async def __aexit__(self, *_args):
            pass

        async def collect(self, _config, *, message_id: int):
            self.calls += 1
            started.set()
            await release.wait()
            result = copy.deepcopy(device_snapshot())
            result["messageId"] = message_id
            return result

    collector = BlockingCollector()
    controller, _settings_store, history = make_controller(
        tmp_path,
        collector_factory=lambda _config: collector,
    )

    first = asyncio.create_task(controller.refresh_providers())
    await started.wait()
    second = asyncio.create_task(controller.refresh_providers())
    await asyncio.sleep(0)
    release.set()
    await asyncio.gather(first, second)

    assert collector.calls == 1
    assert [provider.identifier for provider in controller.state.providers] == ["codex"]
    assert controller.state.connection.phase is ConnectionPhase.STOPPED
    history.close()


@pytest.mark.asyncio
async def test_reconnect_uses_bounded_exponential_delays(tmp_path) -> None:
    transport = FakeManagedTransport(connect_failures=2)
    delays = []

    async def record_sleep(delay):
        delays.append(delay)
        await asyncio.sleep(0)

    controller, _settings_store, history = make_controller(
        tmp_path,
        transport=transport,
        settings_transform=lambda settings: replace(
            settings,
            selected_device_id="device-1",
            selected_device_name="AgentMeter-0001",
        ),
        sleep=record_sleep,
    )
    stop = asyncio.Event()
    controller._reconnect_needed.set()
    task = asyncio.create_task(controller._connection_loop(stop))
    for _ in range(30):
        if controller.state.connection.phase is ConnectionPhase.CONNECTED:
            break
        await asyncio.sleep(0)
    stop.set()
    controller._reconnect_needed.set()
    await task

    assert delays == [1.0, 2.0]
    assert transport.operations.count("connect:device-1") == 3
    history.close()


@pytest.mark.asyncio
async def test_disconnected_patch_waits_without_losing_user_choice(tmp_path) -> None:
    transport = FakeManagedTransport()
    controller, settings_store, history = make_controller(tmp_path, transport=transport)

    result = await controller.patch_settings({"baseRevision": 8, "alwaysOn": True})

    assert result == {"syncStatus": "waitingForDevice", "settings": None}
    pending = settings_store.load(controller._base_config).pending_device_patch
    assert pending is not None and pending.values["alwaysOn"] is True
    assert not any(operation.startswith("request:") for operation in transport.operations)
    history.close()


@pytest.mark.asyncio
async def test_sleep_disconnects_without_retry_and_wake_requests_reconnect(tmp_path) -> None:
    transport = FakeManagedTransport()
    controller, _settings_store, history = make_controller(tmp_path, transport=transport)
    await controller.connect("device-1")

    await controller.sleep_system()

    assert controller.state.connection.phase is ConnectionPhase.STOPPED
    assert not controller._reconnect_needed.is_set()
    await controller.wake_system()
    assert controller._reconnect_needed.is_set()
    history.close()


@pytest.mark.asyncio
async def test_snapshot_nack_moves_connection_to_retrying(tmp_path) -> None:
    transport = FakeManagedTransport()
    transport.send_failure = TransportError(
        "snapshot rejected",
        retryable=False,
        code="snapshotRejected",
    )
    controller, _settings_store, history = make_controller(tmp_path, transport=transport)

    with pytest.raises(IpcCommandError) as error:
        await controller.connect("device-1")

    assert error.value.code == "snapshotRejected"
    assert controller.state.connection.phase is ConnectionPhase.RETRYING
    history.close()


@pytest.mark.asyncio
async def test_invalid_settings_patch_is_an_actionable_ipc_error(tmp_path) -> None:
    controller, _settings_store, history = make_controller(tmp_path)

    with pytest.raises(IpcCommandError) as error:
        await controller.patch_settings({"alwaysOn": True})

    assert error.value.code == "invalidPayload"
    history.close()


@pytest.mark.asyncio
async def test_provider_collection_settings_are_persisted_and_published(tmp_path) -> None:
    controller, settings_store, history = make_controller(tmp_path)

    await controller.update_providers(
        {"providerIds": ["codex", "cursor"], "pollIntervalSeconds": 120}
    )

    assert controller.state.bridge.configured_provider_ids == ("codex", "cursor")
    assert controller.state.bridge.poll_interval_seconds == 120
    saved = settings_store.load(controller._base_config)
    assert saved.provider_ids == ("codex", "cursor")
    assert saved.poll_interval_seconds == 120
    history.close()
