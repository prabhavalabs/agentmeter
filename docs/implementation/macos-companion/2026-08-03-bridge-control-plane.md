# AgentMeter Bridge Control Plane Implementation Plan

**Goal:** Turn the current snapshot loop into a lightweight observable service that remains the
sole BLE owner, provides device management and provider state, and serves the native app through
a private event-driven Unix socket.

**Architecture:** Extend `BleTransport` to carry snapshot and management frames over one Bleak
client. Add a `BridgeController` that owns connection supervision, provider refresh, settings,
telemetry, bounded history, and structured events. Expose that controller through newline-delimited
IPC schema v1 on a user-only Unix socket; retain the current CLI and collect-then-exit CodexBar
lifecycle.

**Tech stack:** Python 3.11+, asyncio, dataclasses, Bleak 3, HTTPX 0.28, sqlite3, platformdirs,
pytest 9, pytest-asyncio, JSON Schema fixtures.

## Global constraints

- Exactly one bridge process, one active Bleak client, and one CodexBar child at a time.
- The app never opens a BLE connection or starts a second collector.
- Preserve `DeviceSnapshotCollector` teardown and `agentmeter-claude-probe --safe-mode` behaviour.
- IPC opens no TCP port, limits a line to 65536 bytes, and validates the peer user.
- Persist normalized percentages and device health only; never persist raw CodexBar responses,
  identity, prompts, credentials, cookies, billing data, or code.
- Bound event queues, pending commands, history, diagnostics, retries, and logs.
- Use events instead of UI polling.
- Legacy firmware without management UUIDs must continue receiving snapshots and report explicit
  unavailable capabilities.
- All file writes are atomic and user-readable only.

## File map

| File | Responsibility |
| --- | --- |
| `host/src/agentmeter_host/control/models.py` | Typed connection, provider, device, settings state |
| `host/src/agentmeter_host/control/events.py` | Bounded event broadcaster |
| `host/src/agentmeter_host/control/settings.py` | Atomic mutable host state and pending patch store |
| `host/src/agentmeter_host/control/history.py` | Bounded SQLite samples and event queries |
| `host/src/agentmeter_host/control/controller.py` | Connection/provider/settings orchestration |
| `host/src/agentmeter_host/ipc/protocol.py` | IPC envelope validation and encoding |
| `host/src/agentmeter_host/ipc/server.py` | User-only Unix server and subscriptions |
| `host/src/agentmeter_host/transport/ble.py` | One-client snapshot and management transport |
| `host/src/agentmeter_host/application.py` | BridgeController, IPC, history, and shutdown composition |
| `schemas/desktop-ipc-v1.schema.json` | Swift/Python IPC contract |
| `fixtures/desktop-ipc-*.json` | Deterministic status, event, settings, and error examples |

---

### Task 1: Define typed control state and bounded event delivery

**Files:**

- Create: `host/src/agentmeter_host/control/__init__.py`
- Create: `host/src/agentmeter_host/control/models.py`
- Create: `host/src/agentmeter_host/control/events.py`
- Create: `host/tests/test_control_models.py`
- Create: `host/tests/test_control_events.py`

**Interfaces:**

- Produces `ConnectionPhase`, `PeripheralSummary`, `DeviceInformation`, `DeviceTelemetry`,
  `DeviceSettings`, `ProviderSummary`, `BridgeStatus`, and `ControlState` frozen dataclasses.
- Produces `ControlState.to_document() -> dict[str, object]` using stable camelCase keys.
- Produces `EventBroker.subscribe() -> AsyncIterator[ControlEvent]` and
  `EventBroker.publish(ControlEvent) -> None`.
- Consumed by every later bridge task and by IPC fixtures.

- [ ] **Step 1: Write failing state serialization tests**

```python
def test_control_state_serializes_unknown_hardware_as_null() -> None:
    from agentmeter_host.control.models import (
        ConnectionPhase,
        ControlState,
        DeviceTelemetry,
    )

    state = ControlState(
        connection=ConnectionPhase.CONNECTED,
        telemetry=DeviceTelemetry(
            power_source="usb",
            usb_present=True,
            battery_present=False,
        ),
    )

    document = state.to_document()

    assert document["connection"]["phase"] == "connected"
    assert document["telemetry"]["batteryPresent"] is False
    assert document["telemetry"]["batteryPercent"] is None
    assert document["telemetry"]["inputCurrentMa"] is None
```

Test every connection phase and verify missing usage remains `None`, not zero.

- [ ] **Step 2: Write failing broker capacity and coalescing tests**

```python
@pytest.mark.asyncio
async def test_event_broker_coalesces_repeated_state_events() -> None:
    broker = EventBroker(capacity=4)
    stream = broker.subscribe()
    broker.publish(ControlEvent("telemetry.changed", {"batteryPercent": 60}))
    broker.publish(ControlEvent("telemetry.changed", {"batteryPercent": 59}))

    event = await anext(stream)

    assert event.type == "telemetry.changed"
    assert event.payload["batteryPercent"] == 59
```

Connection transitions and command results must never be dropped. Repeated telemetry/provider
state may coalesce by type when a subscriber is slow.

- [ ] **Step 3: Run tests and verify import failure**

```bash
.venv/bin/pytest host/tests/test_control_models.py host/tests/test_control_events.py -v
```

- [ ] **Step 4: Implement immutable state and the broker**

Use exact connection values:

```python
class ConnectionPhase(StrEnum):
    STOPPED = "stopped"
    BLUETOOTH_UNAVAILABLE = "bluetoothUnavailable"
    SEARCHING = "searching"
    CONNECTING = "connecting"
    AUTHENTICATING = "authenticating"
    SYNCHRONIZING = "synchronizing"
    CONNECTED = "connected"
    DEGRADED = "degraded"
    RETRYING = "retrying"
```

Represent times as UTC epoch seconds in IPC. `BridgeStatus` includes bridge version, running
state, last provider refresh, last device sync, next retry, last error code, and provider health.
`ControlState` includes a monotonically increasing `revision` so the app can discard old events.

Implement one `asyncio.Queue(maxsize=64)` per subscriber. Coalesce only state event types; close
and remove subscribers in `finally`.

- [ ] **Step 5: Run the new and existing host tests**

```bash
.venv/bin/pytest host/tests/test_control_models.py host/tests/test_control_events.py -v
.venv/bin/pytest
```

- [ ] **Step 6: Commit control models**

```bash
git add host/src/agentmeter_host/control host/tests/test_control_models.py \
  host/tests/test_control_events.py
git commit -m "feat(host): add observable bridge state"
```

---

### Task 2: Extend the single BLE client for discovery and management

**Files:**

- Modify: `host/src/agentmeter_host/transport/ble.py`
- Create: `host/src/agentmeter_host/transport/management.py`
- Modify: `host/tests/test_transport.py`
- Create: `host/tests/test_management_transport.py`

**Interfaces:**

- Produces `BleakBackend.scan() -> tuple[PeripheralSummary, ...]`.
- Changes `BleakBackend.connect(identifier: str | None = None) -> ConnectedPeripheral`.
- Produces `BleTransport.request(request: dict[str, object]) -> dict[str, object]`.
- Produces `BleTransport.device_events() -> AsyncIterator[dict[str, object]]`.
- Preserves `BleTransport.send(payload: bytes, *, message_id: int)` for snapshot callers.
- Consumed by `BridgeController` in Task 5.

- [ ] **Step 1: Add failing discovery and one-client tests**

```python
@pytest.mark.asyncio
async def test_scan_returns_sorted_agentmeter_peripherals_without_connecting() -> None:
    backend = BleakBackend(
        name_prefix="AgentMeter",
        scanner=ScannerWithDevices(
            ("other", "Keyboard", -20),
            ("b", "AgentMeter-BBBB", -70),
            ("a", "AgentMeter-AAAA", -40),
        ),
        client_factory=RecordingBleakClient,
    )

    devices = await backend.scan()

    assert [(item.identifier, item.name) for item in devices] == [
        ("a", "AgentMeter-AAAA"),
        ("b", "AgentMeter-BBBB"),
    ]
    assert RecordingBleakClient.instances == []
```

Add a test proving two concurrent snapshot/management operations share one client and serialize
GATT writes through one lock.

- [ ] **Step 2: Add failing management fragmentation tests**

```python
def test_fragment_management_request_uses_type_02_and_2048_limit() -> None:
    frames = fragment_management_payload(b'{"schemaVersion":1}', message_id=17,
                                         max_write_size=64)

    assert frames[0][0:2] == bytes((1, 0x02))
    assert int.from_bytes(frames[0][2:4], "little") == 17
    with pytest.raises(ValueError, match="2048"):
        fragment_management_payload(b"x" * 2049, message_id=18, max_write_size=64)
```

Test result/event reassembly for types `0x82` and `0x83`, timeout, out-of-order frames, wrong
request ID, and nonzero management error status.

- [ ] **Step 3: Run focused tests and verify failure**

```bash
.venv/bin/pytest host/tests/test_transport.py host/tests/test_management_transport.py -v
```

- [ ] **Step 4: Implement explicit backend operations**

Define constants:

```python
MANAGEMENT_REQUEST_CHARACTERISTIC_UUID = "a77e0004-8f7b-4f63-9a53-65f93f0d6d01"
DEVICE_EVENT_CHARACTERISTIC_UUID = "a77e0005-8f7b-4f63-9a53-65f93f0d6d01"
```

`scan` filters the configured name prefix and returns identifier, name, RSSI, and last-seen epoch.
On macOS the Bleak address is an opaque identifier; do not label it as a MAC address. `connect`
uses the chosen identifier or the remembered single device, starts ACK and event notifications,
and detects missing management characteristics as `management_available=False` without failing
snapshot compatibility.

- [ ] **Step 5: Implement correlated management requests and events**

Use one `asyncio.Lock` for management requests and a separate snapshot-send lock. Only one
management request may be in flight, making the 16-bit frame ID safe. Parse the JSON request ID
from the reassembled result and require an exact match. Put unsolicited `0x83` events into a
bounded coalescing queue. A disconnect fails the current request and completes the event iterator
cleanly.

- [ ] **Step 6: Run transport and regression tests**

```bash
.venv/bin/pytest host/tests/test_transport.py host/tests/test_management_transport.py -v
.venv/bin/pytest
```

- [ ] **Step 7: Commit the managed transport**

```bash
git add host/src/agentmeter_host/transport/ble.py \
  host/src/agentmeter_host/transport/management.py \
  host/tests/test_transport.py host/tests/test_management_transport.py
git commit -m "feat(host): manage device over one BLE connection"
```

---

### Task 3: Add atomic host settings, pending patches, and bounded history

**Files:**

- Create: `host/src/agentmeter_host/control/settings.py`
- Create: `host/src/agentmeter_host/control/history.py`
- Create: `host/tests/test_control_settings.py`
- Create: `host/tests/test_control_history.py`
- Modify: `host/src/agentmeter_host/config.py`
- Modify: `host/tests/test_config.py`

**Interfaces:**

- Produces `ControlSettingsStore.load(base: HostConfig) -> MutableHostSettings`.
- Produces `ControlSettingsStore.save(MutableHostSettings) -> None`.
- Produces `PendingSettingsPatch` persistence with `base_revision`.
- Produces `HistoryStore.record_snapshot`, `record_telemetry`, `record_connection`, `query_usage`,
  `prune`, and `clear`.
- Consumed by `BridgeController` and IPC.

- [ ] **Step 1: Add failing atomic-settings tests**

```python
def test_control_settings_migrate_from_toml_and_write_private_json(tmp_path) -> None:
    store = ControlSettingsStore(tmp_path / "control-state-v1.json")
    settings = store.load(host_config(provider_ids=("codex", "claude")))
    settings = replace(settings, selected_device_id="peripheral-1")

    store.save(settings)

    document = json.loads(store.path.read_text())
    assert document["schemaVersion"] == 1
    assert document["providerIds"] == ["codex", "claude"]
    assert document["selectedDeviceId"] == "peripheral-1"
    assert stat.S_IMODE(store.path.stat().st_mode) == 0o600
    assert not store.path.with_suffix(".tmp").exists()
```

Test invalid/corrupt JSON leaves the original file untouched and returns a clear error rather than
silently overwriting it. Test pending patch round-trip and clear-after-confirmation.

- [ ] **Step 2: Add failing bounded-history tests**

```python
def test_history_downsamples_and_prunes_without_identity(tmp_path) -> None:
    history = HistoryStore(tmp_path / "history.sqlite3")
    history.record_usage("claude", "session", 1000, 41, 5000)
    history.record_usage("claude", "session", 1100, 42, 5000)
    history.record_usage("claude", "session", 1301, 43, 5000)
    history.prune(now_epoch=1000 + 31 * 86400)

    assert history.query_usage(since_epoch=0) == []
    assert "account" not in history.schema_sql.lower()
    assert "prompt" not in history.schema_sql.lower()
```

Prove one sample per provider/window/five-minute bucket and a 30-day retention boundary.

- [ ] **Step 3: Run focused tests and verify failure**

```bash
.venv/bin/pytest host/tests/test_control_settings.py host/tests/test_control_history.py -v
```

- [ ] **Step 4: Implement the private JSON overlay**

Keep `config.toml` readable for CLI users. On first control-plane launch, seed mutable values from
`HostConfig`; afterward, load `control-state-v1.json` from Application Support. Validate provider
IDs and the 30-second minimum poll interval with the same rules as `HostConfig`. Write a sibling
temporary file, flush and `fsync`, chmod `0600`, then `replace` atomically.

Store only provider IDs, poll interval, selected peripheral ID/name, reconnect preference, and an
optional bounded pending device patch. Display settings remain device-owned.

- [ ] **Step 5: Implement SQLite history with fixed columns**

Create tables:

```sql
CREATE TABLE usage_sample (
  provider_id TEXT NOT NULL,
  window_kind TEXT NOT NULL,
  sampled_at INTEGER NOT NULL,
  bucket INTEGER NOT NULL,
  used_percent INTEGER,
  reset_at INTEGER,
  PRIMARY KEY (provider_id, window_kind, bucket)
);
CREATE TABLE connection_event (
  occurred_at INTEGER NOT NULL,
  phase TEXT NOT NULL,
  code TEXT
);
CREATE TABLE device_sample (
  sampled_at INTEGER PRIMARY KEY,
  power_source TEXT,
  battery_percent INTEGER,
  battery_voltage_mv INTEGER,
  vbus_voltage_mv INTEGER
);
```

Use SQLite parameter binding, WAL mode, a busy timeout, and one connection owned by the bridge.
Replace the current five-minute bucket sample with the newest value. Prune after startup and at
most once per day.

- [ ] **Step 6: Run settings/history and full host tests**

```bash
.venv/bin/pytest host/tests/test_control_settings.py host/tests/test_control_history.py -v
.venv/bin/pytest
```

- [ ] **Step 7: Commit persistence**

```bash
git add host/src/agentmeter_host/control/settings.py \
  host/src/agentmeter_host/control/history.py host/src/agentmeter_host/config.py \
  host/tests/test_control_settings.py host/tests/test_control_history.py \
  host/tests/test_config.py
git commit -m "feat(host): persist bounded control state"
```

---

### Task 4: Define and serve private IPC schema v1

**Files:**

- Create: `schemas/desktop-ipc-v1.schema.json`
- Create: `fixtures/desktop-ipc-status-v1.json`
- Create: `fixtures/desktop-ipc-event-v1.json`
- Create: `fixtures/desktop-ipc-settings-v1.json`
- Create: `fixtures/desktop-ipc-error-v1.json`
- Create: `host/src/agentmeter_host/ipc/__init__.py`
- Create: `host/src/agentmeter_host/ipc/protocol.py`
- Create: `host/src/agentmeter_host/ipc/server.py`
- Create: `host/tests/test_ipc_protocol.py`
- Create: `host/tests/test_ipc_server.py`
- Modify: `host/tests/test_schema.py`

**Interfaces:**

- Produces `decode_request(line: bytes) -> IpcRequest`.
- Produces `encode_result`, `encode_error`, and `encode_event`.
- Produces `IpcServer.start()`, `IpcServer.close()`, and event subscription.
- Consumes a `ControlApi` protocol implemented by `BridgeController` in Task 5.

- [ ] **Step 1: Write failing envelope and fixture tests**

```python
def test_decode_status_request() -> None:
    request = decode_request(
        b'{"schemaVersion":1,"id":"request-1","type":"status.get","payload":{}}\n'
    )

    assert request.id == "request-1"
    assert request.type == "status.get"
    assert request.payload == {}
```

Reject unsupported versions, IDs outside 1–64 safe characters, unknown types, missing payload,
extra envelope fields, more than 65536 bytes, malformed UTF-8, and newline injection. Validate all
fixtures through `desktop-ipc-v1.schema.json` in `test_schema.py`.

- [ ] **Step 2: Write failing permission, peer, and subscription tests**

```python
@pytest.mark.asyncio
async def test_ipc_socket_is_private_and_streams_state_events(tmp_path) -> None:
    api = RecordingControlApi()
    server = IpcServer(tmp_path / "run" / "bridge.sock", api=api,
                       current_uid=lambda: 501, peer_uid=lambda _socket: 501)
    await server.start()
    reader, writer = await asyncio.open_unix_connection(server.path)
    writer.write(b'{"schemaVersion":1,"id":"1","type":"events.subscribe","payload":{}}\n')
    await writer.drain()
    api.events.publish(ControlEvent("connection.changed", {"phase": "connected"}))

    assert stat.S_IMODE(server.path.parent.stat().st_mode) == 0o700
    assert stat.S_IMODE(server.path.stat().st_mode) == 0o600
    assert json.loads(await reader.readline())["type"] == "events.subscribed"
    assert json.loads(await reader.readline())["type"] == "connection.changed"
    writer.close()
    await writer.wait_closed()
    await server.close()
```

Add a denied-peer test and a slow-subscriber test that keeps critical results while coalescing
state.

- [ ] **Step 3: Run IPC tests and verify failure**

```bash
.venv/bin/pytest host/tests/test_ipc_protocol.py host/tests/test_ipc_server.py \
  host/tests/test_schema.py -v
```

- [ ] **Step 4: Implement the stable command set**

Schema v1 accepts exactly:

```text
hello
status.get
events.subscribe
device.scan
device.connect
device.disconnect
device.forget
device.identify
device.refresh
settings.get
settings.patch
providers.refresh
providers.update
history.query
history.clear
diagnostics.get
bridge.restart
system.sleep
system.wake
```

Result envelopes echo the request ID and use `<noun>.result`; errors use `status: "error"` and a
stable code. Events use a bridge sequence number as ID and carry the latest complete state or
bounded delta.

- [ ] **Step 5: Implement the user-only Unix server**

Use `asyncio.start_unix_server`, remove only an existing socket owned by the current user, create
the parent with mode `0700`, and chmod the socket to `0600`. On macOS read `socket.getpeereid()`;
on Linux CI read `SO_PEERCRED`. Reject a different UID before decoding commands. Limit each read
with `StreamReader.readline()` and close on overrun.

Use `$TMPDIR/agentmeter-<uid>/bridge.sock` at runtime to stay below the macOS Unix-path limit. The
directory is recreated safely after reboot and contains no persistent data.

- [ ] **Step 6: Run IPC, schema, and complete host tests**

```bash
.venv/bin/pytest host/tests/test_ipc_protocol.py host/tests/test_ipc_server.py \
  host/tests/test_schema.py -v
.venv/bin/pytest
```

- [ ] **Step 7: Commit IPC**

```bash
git add schemas/desktop-ipc-v1.schema.json fixtures/desktop-ipc-*.json \
  host/src/agentmeter_host/ipc host/tests/test_ipc_protocol.py \
  host/tests/test_ipc_server.py host/tests/test_schema.py
git commit -m "feat(host): add private desktop IPC"
```

---

### Task 5: Build the connection and provider controller

**Files:**

- Create: `host/src/agentmeter_host/control/controller.py`
- Create: `host/tests/test_control_controller.py`
- Modify: `host/src/agentmeter_host/runtime.py`
- Modify: `host/tests/test_runtime.py`

**Interfaces:**

- Produces `BridgeController` implementing every `ControlApi` command.
- Produces `BridgeController.run(stop_event: asyncio.Event) -> None`.
- Consumed by `application.py` and IPC in Task 6.

- [ ] **Step 1: Add failing state-machine tests**

```python
@pytest.mark.asyncio
async def test_controller_connects_syncs_and_publishes_confirmed_state() -> None:
    transport = FakeManagedTransport(
        device_state=device_state_fixture(settings_revision=8)
    )
    controller = make_controller(transport=transport)

    await controller.connect("peripheral-1")

    assert controller.state.connection.phase is ConnectionPhase.CONNECTED
    assert controller.state.settings.revision == 8
    assert transport.operations == [
        "connect:peripheral-1",
        "request:device.get",
        "request:settings.get",
        "send:snapshot",
    ]
```

Test Bluetooth unavailable, permission denied, missing device, auth failure, legacy firmware,
snapshot NACK, unexpected disconnect, manual reconnect, sleep/wake, retry delays 1/2/4/8/16/32/60
seconds with injected jitter, and stop during backoff.

- [ ] **Step 2: Add failing settings and provider tests**

Prove app patches are marked pending until firmware confirms, revision conflicts replace local
state and preserve a reapply action, touchscreen `settings.changed` events update immediately,
manual provider refresh cancels no active collection, and provider failures do not change a
healthy BLE phase.

- [ ] **Step 3: Run focused tests and verify failure**

```bash
.venv/bin/pytest host/tests/test_control_controller.py host/tests/test_runtime.py -v
```

- [ ] **Step 4: Implement `BridgeController` around existing collection**

Constructor:

```python
class BridgeController:
    def __init__(
        self,
        config: HostConfig,
        transport: ManagedSnapshotTransport,
        settings_store: ControlSettingsStore,
        history: HistoryStore,
        events: EventBroker,
        collector_session_factory: Callable[[HostConfig], AsyncContextManager],
        clock: Callable[[], float] = time.time,
        monotonic: Callable[[], float] = time.monotonic,
        sleep: Callable[[float], Awaitable[None]] = asyncio.sleep,
        jitter: Callable[[float], float] = random.uniform,
    ) -> None: ...
```

Keep provider collection in a separate task from connection supervision. Use an
`asyncio.Lock` so only one refresh runs. Each refresh creates and closes one
`DeviceSnapshotCollector` session, applies `ProviderHistory` and alerts, records downsampled
history, publishes provider state, and sends the snapshot if connected. A provider error updates
provider health but not connection phase.

- [ ] **Step 5: Implement connection supervision and settings conflicts**

Remember one selected device. On connect: transition searching → connecting → authenticating →
synchronizing, read capabilities/settings when supported, send the latest snapshot, then publish
connected. Legacy firmware skips management reads and reports those fields unavailable.

Unexpected disconnect enters retrying with bounded jittered backoff. `system.sleep` cancels the
timer and disconnects cleanly; `system.wake` resets the delay and reconnects. `settings.patch`
stores the pending patch before sending and clears it only after a confirmed newer revision.

- [ ] **Step 6: Preserve the existing `run_bridge` compatibility API**

Keep `run_bridge(..., once=True)` and `BridgeRuntime` tests working for CLI `send` and simple
fixtures. Move shared snapshot collection/history logic into focused helpers rather than routing
unit tests through IPC.

- [ ] **Step 7: Run focused and full host tests**

```bash
.venv/bin/pytest host/tests/test_control_controller.py host/tests/test_runtime.py -v
.venv/bin/pytest
```

- [ ] **Step 8: Commit the controller**

```bash
git add host/src/agentmeter_host/control/controller.py \
  host/tests/test_control_controller.py host/src/agentmeter_host/runtime.py \
  host/tests/test_runtime.py
git commit -m "feat(host): supervise device and provider state"
```

---

### Task 6: Compose the service, CLI, diagnostics, and documentation

**Files:**

- Create: `host/src/agentmeter_host/application.py`
- Create: `host/src/agentmeter_host/ipc/fake.py`
- Create: `host/tests/test_application.py`
- Create: `host/tests/test_ipc_fake.py`
- Modify: `host/src/agentmeter_host/cli.py`
- Modify: `host/src/agentmeter_host/service.py`
- Modify: `host/tests/test_cli.py`
- Modify: `host/tests/test_service.py`
- Modify: `docs/architecture.md`
- Modify: `docs/host.md`
- Modify: `docs/configuration.md`
- Modify: `docs/development.md`
- Modify: `config.example.toml`

**Interfaces:**

- Produces the real background process invoked by the legacy LaunchAgent and later bundled helper.
- Produces deterministic `diagnostics.get` without private data.
- Produces a fakeable IPC contract for the native macOS plan.

- [ ] **Step 1: Add failing application lifecycle tests**

```python
@pytest.mark.asyncio
async def test_application_starts_one_controller_and_one_ipc_server() -> None:
    controller = RecordingController()
    server = RecordingIpcServer()
    application = BridgeApplication(controller=controller, ipc_server=server)
    stop = asyncio.Event()
    task = asyncio.create_task(application.run(stop))
    await controller.started.wait()
    stop.set()
    await task

    assert controller.run_count == 1
    assert server.start_count == 1
    assert server.close_count == 1
    assert controller.close_count == 1
```

Test SIGTERM-style cancellation, startup failure cleanup, stale-socket recovery, and a diagnostics
document that contains versions, state codes, and bounded event summaries but no configured home
path or provider raw error.

- [ ] **Step 2: Run lifecycle tests and verify failure**

```bash
.venv/bin/pytest host/tests/test_application.py host/tests/test_cli.py \
  host/tests/test_service.py -v
```

- [ ] **Step 3: Implement application composition and CLI entry**

`BridgeApplication.run` starts IPC, runs the controller, responds to `asyncio.Event` shutdown, and
closes IPC, BLE, history, and subscriber tasks in reverse order. Change continuous `agentmeter run`
to use `BridgeApplication`; keep `agentmeter send` on the compatibility one-shot path. Add
`agentmeter ipc-path` for development diagnostics without exposing secrets.

- [ ] **Step 4: Extend service status without changing the label**

Keep `com.prabhavalabs.agentmeter` for legacy source installs. Add `--ipc-path` to its program
arguments, rotate helper logs at startup to a fixed number/size, and report both launchd state and
IPC reachability from `agentmeter service status`. Do not start another process to answer status.

- [ ] **Step 5: Document operation and developer fixtures**

Document process ownership, state transitions, commands, history retention/clear, configuration
overlay, socket location, privacy, legacy firmware behaviour, and manual development commands.
Add `agentmeter fake-server --scenario <name> --ipc-path <path>`, implemented by
`agentmeter_host.ipc.fake`, with exact scenarios `connected-usb`, `disconnected`, `pairing`,
`provider-unavailable`, `legacy`, and `settings-conflict`. It may load only checked-in
`fixtures/desktop-ipc-*.json`, must reject unknown scenarios, and must never import CodexBar or
Bleak. Cover scenario selection and command replies in `test_ipc_fake.py` so Swift development
never requires credentials or attached hardware.

- [ ] **Step 6: Run all project gates**

```bash
.venv/bin/ruff check .
.venv/bin/ruff format --check .
.venv/bin/pytest
.venv/bin/pio test -d firmware -e native
.venv/bin/pio run -d firmware
```

- [ ] **Step 7: Perform a local process-efficiency check**

Run the bridge for three refreshes and confirm the CodexBar/Claude child exits after each refresh:

```bash
.venv/bin/agentmeter run --config config.toml
ps -axo pid,ppid,rss,%cpu,command | rg 'agentmeter|codexbar|claude'
```

After a collection completes, only the bridge should remain. Capture measured idle RSS/CPU in the
pull-request verification notes, not as a fixed cross-machine promise in the UI.

- [ ] **Step 8: Commit service integration**

```bash
git add host/src/agentmeter_host/application.py host/src/agentmeter_host/ipc/fake.py \
  host/tests/test_application.py host/tests/test_ipc_fake.py \
  host/src/agentmeter_host/cli.py host/src/agentmeter_host/service.py \
  host/tests/test_cli.py host/tests/test_service.py config.example.toml \
  docs/architecture.md docs/host.md docs/configuration.md docs/development.md
git commit -m "feat(host): expose the desktop control plane"
```

## Plan completion gate

Do not begin production SwiftUI integration until:

- one bridge owns discovery, connection, management, and snapshot delivery;
- IPC schema fixtures validate and a fake server can replay them;
- all commands return structured results and state events without polling;
- retry, sleep/wake, legacy firmware, settings conflicts, and shutdown are tested;
- history and diagnostics contain no private provider data;
- the full existing host/firmware test matrix passes;
- repeated refresh confirms provider child processes do not accumulate.
