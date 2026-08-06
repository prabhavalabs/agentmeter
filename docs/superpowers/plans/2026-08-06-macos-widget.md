# AgentMeter macOS Widget Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add highly configurable Agent Dashboard and Agent Focus widgets for macOS that prioritize weekly/monthly allowances, show shorter reset windows, and optionally render a truthful 30-day heat map or trend graph.

**Architecture:** The Python bridge adds a bounded per-provider daily history summary. A new `AgentMeterWidgetCore` Swift package target converts bridge state into a versioned, privacy-safe snapshot stored atomically in an App Group. A WidgetKit extension reads that snapshot, resolves App Intent configuration into size-aware presentation models, and renders Dashboard or Focus views without connecting to IPC, Bluetooth, or provider services.

**Tech Stack:** Python 3.11, SQLite, Swift 6, SwiftUI, WidgetKit, AppIntents, Charts, Swift Testing, Xcode 26, XcodeGen 2.45.4, macOS 14+

**Design Spec:** `docs/superpowers/specs/2026-08-06-macos-widget-design.md`

## Global Constraints

- Deployment target remains macOS 14 and later.
- Preserve app identifier `com.prabhavalabs.agentmeter.desktop`.
- Use extension identifier `com.prabhavalabs.agentmeter.desktop.widget` and App Group `group.com.prabhavalabs.agentmeter.shared`.
- Use widget kinds `com.prabhavalabs.agentmeter.dashboard` and `com.prabhavalabs.agentmeter.focus`.
- Shared snapshots are limited to 8 providers, 8 current windows per provider, 4 history-enabled windows per provider, 30 days, and 256 KiB encoded.
- The outer ring prioritizes monthly/billing, then exact weekly, then another non-session window; the inner ring prioritizes exact session, then daily/short, then another remaining window.
- Unknown percentages, reset times, and history stay unknown; never invent zero values.
- Heat-map cells mean positive percentage points consumed during a local calendar day, not tokens, prompts, coding time, or commits.
- The extension must not access IPC, SQLite, CodexBar, Bluetooth, the network, keychain, or provider credentials.
- The managed build embeds the signed widget extension; the ad-hoc community DMG remains app-only.
- Do not add runtime third-party dependencies. XcodeGen is a build-time project generator only.
- Preserve all existing Swift Package, Python host, firmware, community packaging, and privacy tests.

---

## File Map

### Host history and IPC

- Modify `host/src/agentmeter_host/control/history.py`: aggregate positive daily percentage deltas in an IANA time zone.
- Modify `host/src/agentmeter_host/control/controller.py`: serve the bounded `history.summary` command.
- Modify `host/src/agentmeter_host/ipc/protocol.py`: allow `history.summary`.
- Modify `host/tests/test_control_history.py`, `host/tests/test_control_controller.py`, and `host/tests/test_ipc_protocol.py`: cover resets, gaps, DST, validation, and response shape.

### Shared Swift code

- Modify `desktop/Package.swift`: add `AgentMeterWidgetCore` and tests; connect `AgentMeterUI` to it.
- Create `desktop/Sources/AgentMeterCore/Models/WidgetHistory.swift`: decode bridge summaries.
- Modify `desktop/Sources/AgentMeterIPC/BridgeAPI.swift` and `FakeBridgeAPI.swift`: request and fake summaries.
- Create `desktop/Sources/AgentMeterWidgetCore/WidgetSnapshot.swift`: versioned safe snapshot types.
- Create `desktop/Sources/AgentMeterWidgetCore/WidgetSnapshotBuilder.swift`: apply bounds and merge bridge state/history.
- Create `desktop/Sources/AgentMeterWidgetCore/WidgetSnapshotStore.swift`: atomic App Group persistence.
- Create `desktop/Sources/AgentMeterWidgetCore/WidgetWindowSelector.swift`: deterministic ring selection.
- Create `desktop/Sources/AgentMeterWidgetCore/WidgetConfiguration.swift`: platform-independent customization values.
- Create `desktop/Sources/AgentMeterWidgetCore/WidgetHistoryProjection.swift`: heat-map/trend projection.
- Create `desktop/Sources/AgentMeterWidgetCore/WidgetPresentationResolver.swift`: size-aware view models.
- Create `desktop/Sources/AgentMeterWidgetCore/WidgetTimelinePlanner.swift`: stale/reset checkpoints.
- Create `desktop/Sources/AgentMeterWidgetCore/AgentMeterRoute.swift`: validated deep links.
- Create `desktop/Sources/AgentMeterCore/ProviderVisuals.swift`: shared provider accent hex values.
- Create `desktop/Tests/AgentMeterWidgetCoreTests/WidgetSnapshotTests.swift`, `WidgetWindowSelectorTests.swift`, `WidgetHistoryProjectionTests.swift`, `WidgetPresentationResolverTests.swift`, `WidgetTimelinePlannerTests.swift`, `WidgetSnapshotStoreTests.swift`, and `AgentMeterRouteTests.swift`: unit coverage for every shared rule.

### Host app, extension, and packaging

- Create `desktop/Sources/AgentMeterUI/Widgets/WidgetSnapshotCoordinator.swift`: query history, write snapshots, and deduplicate reloads.
- Modify `desktop/Sources/AgentMeterUI/State/AppModel.swift`, `desktop/Sources/AgentMeterApp/AppEnvironment.swift`, and `desktop/Sources/AgentMeterApp/AgentMeterApplication.swift`: publish snapshots and route URLs.
- Modify `desktop/Sources/AgentMeterUI/Features/Overview/OverviewView.swift`: open requested provider details.
- Create `desktop/project.yml`, `desktop/AgentMeter.xcodeproj/project.pbxproj`, and `desktop/scripts/generate-xcode-project.sh`: define and generate the host/extension project.
- Create `desktop/Widgets/Resources/Info.plist`, `desktop/Widgets/Resources/AgentMeterWidget.entitlements`, `desktop/Widgets/Sources/AgentMeterWidgetBundle.swift`, `desktop/Widgets/Sources/Configuration/WidgetIntents.swift`, `desktop/Widgets/Sources/Timeline/DashboardTimelineProvider.swift`, `desktop/Widgets/Sources/Dashboard/DashboardWidgetView.swift`, and `desktop/Widgets/Sources/Focus/FocusWidgetView.swift`: extension metadata and its primary configuration, timeline, and view units.
- Modify `desktop/scripts/package-app.sh`, CI, Makefile, and documentation: build, verify, and explain the managed widget release while preserving community packaging.

---

### Task 1: Add bounded daily allowance aggregation to the host

**Files:**
- Modify: `host/src/agentmeter_host/control/history.py`
- Modify: `host/tests/test_control_history.py`

**Interfaces:**
- Consumes: existing `usage_sample(provider_id, window_kind, sampled_at, used_percent, reset_at)` rows.
- Produces: `HistoryStore.query_widget_summary(*, since_epoch: int, provider_id: str, time_zone_identifier: str) -> dict[str, object]` returning `historyStartEpoch` and `days`.

- [ ] **Step 1: Write failing aggregation tests**

Add fixed-epoch tests proving positive deltas are summed, a reset drop is ignored, a post-reset increase is counted, all-unknown days are omitted, zero-activity days remain `0`, and only the requested provider is returned:

```python
def test_widget_summary_counts_positive_deltas_without_counting_resets(tmp_path) -> None:
    history = HistoryStore(tmp_path / "history.sqlite3")
    for sampled_at, percent, reset_at in (
        (1_788_249_600, 10, 1_788_336_000),
        (1_788_253_200, 16, 1_788_336_000),
        (1_788_256_800, 3, 1_788_422_400),
        (1_788_260_400, 8, 1_788_422_400),
    ):
        history.record_usage("claude", "weekly", sampled_at, percent, reset_at)

    result = history.query_widget_summary(
        since_epoch=1_788_249_600,
        provider_id="claude",
        time_zone_identifier="UTC",
    )

    assert result["days"] == [{
        "providerId": "claude",
        "windowKind": "weekly",
        "dayStartEpoch": 1_788_249_600,
        "consumedPercentPoints": 11,
        "latestUsedPercent": 8,
        "resetAtEpoch": 1_788_422_400,
    }]
```

Add a Europe/Berlin DST test with `datetime` and `ZoneInfo` asserting spring-transition day starts are 82,800 seconds apart.

- [ ] **Step 2: Run the focused tests and confirm failure**

Run: `.venv/bin/pytest host/tests/test_control_history.py -q`

Expected: FAIL because `HistoryStore` has no `query_widget_summary` method.

- [ ] **Step 3: Implement local-day aggregation**

Validate IDs/epochs, construct `ZoneInfo`, read the requested provider's retained rows in chronological order, preserve a pre-boundary baseline, and emit one document per window/day:

```python
def query_widget_summary(
    self,
    *,
    since_epoch: int,
    provider_id: str,
    time_zone_identifier: str,
) -> dict[str, object]:
    self._validate_epoch(since_epoch, "history boundary")
    self._validate_id(provider_id, "provider ID")
    try:
        zone = ZoneInfo(time_zone_identifier)
    except (ZoneInfoNotFoundError, ValueError) as error:
        raise HistoryError("time zone identifier is invalid") from error
    rows = self._connection.execute(
        """
        SELECT provider_id, window_kind, sampled_at, used_percent, reset_at
        FROM usage_sample WHERE provider_id = ?
        ORDER BY window_kind ASC, sampled_at ASC
        """,
        (provider_id,),
    ).fetchall()
    return self._widget_summary_document(rows, since_epoch=since_epoch, zone=zone)
```

In `_widget_summary_document`, add `current - previous` only when both percentages are known, the reset epoch is unchanged, and the percentage did not decrease. A changed reset epoch or decrease updates the baseline with delta zero. Omit days with no known percentage.

- [ ] **Step 4: Add validation/privacy assertions**

Assert invalid IANA zones and provider IDs raise `HistoryError`, `historyStartEpoch` is the first retained usable sample, and output never includes provider names, identities, prompts, or raw values.

- [ ] **Step 5: Run the history suite**

Run: `.venv/bin/pytest host/tests/test_control_history.py -q`

Expected: all tests PASS.

- [ ] **Step 6: Commit the host aggregation**

```bash
git add host/src/agentmeter_host/control/history.py host/tests/test_control_history.py
git commit -m "feat(host): summarize daily allowance usage"
```

### Task 2: Expose and decode `history.summary`

**Files:**
- Modify: `host/src/agentmeter_host/ipc/protocol.py`
- Modify: `host/src/agentmeter_host/control/controller.py`
- Modify: `host/tests/test_ipc_protocol.py`
- Modify: `host/tests/test_control_controller.py`
- Create: `desktop/Sources/AgentMeterCore/Models/WidgetHistory.swift`
- Modify: `desktop/Sources/AgentMeterIPC/BridgeAPI.swift`
- Modify: `desktop/Sources/AgentMeterIPC/FakeBridgeAPI.swift`
- Modify: `desktop/Tests/AgentMeterIPCTests/FakeBridgeAPITests.swift`
- Modify: `desktop/Tests/AgentMeterCoreTests/ModelDecodingTests.swift`

**Interfaces:**
- Consumes: `HistoryStore.query_widget_summary` from Task 1.
- Produces: `BridgeCommand.queryWidgetHistory(sinceEpoch:providerId:timeZoneIdentifier:)` and `WidgetHistorySummary`.

- [ ] **Step 1: Write failing Python IPC tests**

Add `history.summary` to the protocol parameterization and test:

```python
result = await controller.handle_ipc(IpcRequest(
    id="summary-1",
    type="history.summary",
    payload={
        "sinceEpoch": 1_788_249_600,
        "providerId": "claude",
        "timeZoneIdentifier": "Europe/Berlin",
    },
))
assert set(result) == {"historyStartEpoch", "days"}
```

Assert missing required keys, extra keys, booleans for epochs, and invalid zones produce `IpcCommandError.code == "invalidPayload"`.

- [ ] **Step 2: Run Python tests and verify the new command fails**

Run: `.venv/bin/pytest host/tests/test_ipc_protocol.py host/tests/test_control_controller.py -q`

Expected: FAIL because `history.summary` is not in `COMMAND_TYPES`.

- [ ] **Step 3: Implement the host command**

Add `history.summary` to `COMMAND_TYPES`. In `BridgeController.handle_ipc`, require exactly the three approved keys and call Task 1:

```python
if command == "history.summary":
    required = {"sinceEpoch", "providerId", "timeZoneIdentifier"}
    if set(request.payload) != required:
        raise IpcCommandError("invalidPayload", "History summary query is invalid")
    try:
        return self._history.query_widget_summary(
            since_epoch=request.payload["sinceEpoch"],
            provider_id=request.payload["providerId"],
            time_zone_identifier=request.payload["timeZoneIdentifier"],
        )
    except HistoryError as error:
        raise IpcCommandError("invalidPayload", str(error)) from error
```

- [ ] **Step 4: Write failing Swift request/decoding tests**

```swift
let command = BridgeCommand.queryWidgetHistory(
    sinceEpoch: 1_788_249_600,
    providerId: "claude",
    timeZoneIdentifier: "Europe/Berlin"
)
#expect(try command.payload() == [
    "sinceEpoch": .integer(1_788_249_600),
    "providerId": .string("claude"),
    "timeZoneIdentifier": .string("Europe/Berlin"),
])
```

Decode one summary day and assert every field.

- [ ] **Step 5: Run Swift tests and verify the types are missing**

Run: `swift test --package-path desktop --filter 'history|WidgetHistory'`

Expected: FAIL because `queryWidgetHistory` and `WidgetHistorySummary` do not exist.

- [ ] **Step 6: Implement Swift models and command**

```swift
public struct WidgetHistoryDay: Codable, Equatable, Sendable {
    public let providerId: String
    public let windowKind: String
    public let dayStartEpoch: Int
    public let consumedPercentPoints: Int
    public let latestUsedPercent: Int?
    public let resetAtEpoch: Int?
}

public struct WidgetHistorySummary: Codable, Equatable, Sendable {
    public let historyStartEpoch: Int?
    public let days: [WidgetHistoryDay]
}
```

Provide explicit public initializers for both structs. Map the new `BridgeCommand` case to `history.summary`, encode all three keys, and return an empty `WidgetHistorySummary` from `FakeBridgeAPI`.

- [ ] **Step 7: Run both focused suites**

Run: `.venv/bin/pytest host/tests/test_ipc_protocol.py host/tests/test_control_controller.py -q`

Run: `swift test --package-path desktop --filter 'history|WidgetHistory'`

Expected: all focused tests PASS.

- [ ] **Step 8: Commit the IPC contract**

```bash
git add host/src/agentmeter_host/ipc/protocol.py host/src/agentmeter_host/control/controller.py host/tests/test_ipc_protocol.py host/tests/test_control_controller.py desktop/Sources/AgentMeterCore/Models/WidgetHistory.swift desktop/Sources/AgentMeterIPC/BridgeAPI.swift desktop/Sources/AgentMeterIPC/FakeBridgeAPI.swift desktop/Tests/AgentMeterIPCTests/FakeBridgeAPITests.swift desktop/Tests/AgentMeterCoreTests/ModelDecodingTests.swift
git commit -m "feat: expose widget history summaries"
```

### Task 3: Build the versioned snapshot and window-selection core

**Files:**
- Modify: `desktop/Package.swift`
- Create: `desktop/Sources/AgentMeterCore/ProviderVisuals.swift`
- Modify: `desktop/Sources/AgentMeterUI/DesignSystem/AgentMeterTheme.swift`
- Create: `desktop/Sources/AgentMeterWidgetCore/WidgetSnapshot.swift`
- Create: `desktop/Sources/AgentMeterWidgetCore/WidgetSnapshotBuilder.swift`
- Create: `desktop/Sources/AgentMeterWidgetCore/WidgetWindowSelector.swift`
- Create: `desktop/Tests/AgentMeterWidgetCoreTests/WidgetSnapshotTests.swift`
- Create: `desktop/Tests/AgentMeterWidgetCoreTests/WidgetWindowSelectorTests.swift`
- Modify: `desktop/Tests/AgentMeterUITests/ThemeTests.swift`

**Interfaces:**
- Consumes: `ControlState`, `ProviderWindow`, and `[String: WidgetHistorySummary]`.
- Produces: `WidgetSnapshot`, `WidgetSnapshotBuilder.build(state:summaries:)`, and `WidgetWindowSelector.select(from:)`.

- [ ] **Step 1: Add targets and failing snapshot tests**

Add `AgentMeterWidgetCore` depending on `AgentMeterCore`, add its test target, and add WidgetCore to `AgentMeterUI` dependencies. Test schema/bounds:

```swift
let snapshot = try WidgetSnapshotBuilder().build(
    state: makeWidgetState(providerCount: 10, windowsPerProvider: 10),
    summaries: [:]
)
#expect(snapshot.schemaVersion == 1)
#expect(snapshot.providers.count == 8)
#expect(snapshot.providers.allSatisfy { $0.windows.count == 8 })
#expect(snapshot.pollIntervalSeconds == 300)
```

Encode the result and assert fixture email, prompt, repository path, and OAuth token strings are absent.

- [ ] **Step 2: Write failing selection tests**

Cover monthly/session, weekly/session, model-specific weekly versus exact weekly, one-window fallback, missing percentages, and Focus overrides:

```swift
let selection = WidgetWindowSelector.select(from: [
    window("session", "Session"),
    window("claude-weekly-opus", "Opus weekly"),
    window("weekly", "Weekly"),
])
#expect(selection.outer?.kind == "weekly")
#expect(selection.inner?.kind == "session")
```

- [ ] **Step 3: Run WidgetCore tests and verify the target is missing**

Run: `swift test --package-path desktop --filter AgentMeterWidgetCoreTests`

Expected: FAIL because the package target and snapshot types do not exist.

- [ ] **Step 4: Implement allowlisted snapshot types**

```swift
public struct WidgetSnapshot: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let generatedAtEpoch: Int
    public let pollIntervalSeconds: Int
    public let historyStartEpoch: Int?
    public let providers: [WidgetProviderSnapshot]
}

public struct WidgetProviderSnapshot: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let status: String
    public let updatedAtEpoch: Int?
    public let windows: [WidgetWindowSnapshot]
    public let history: [WidgetHistoryDay]
}
```

Give `WidgetWindowSnapshot` only kind, label, used percentage, and reset epoch. Preserve configured provider order; clamp invalid percentages to `nil`; enforce all global bounds; derive generation time from the newest provider/bridge refresh so identical state stays identical.

- [ ] **Step 5: Implement window priorities and shared accents**

Return `WidgetWindowSelection(outer:inner:additional:)`. Normalize kind/label tokens, implement the exact global priority order, and accept explicit Focus outer/inner kinds only when they belong to the provider. Move the color hex mapping to `ProviderVisuals.accentHex(for:)` and make `ProviderPalette` delegate to it.

- [ ] **Step 6: Run focused tests**

Run: `swift test --package-path desktop --filter 'AgentMeterWidgetCoreTests|ThemeTests'`

Expected: all focused tests PASS.

- [ ] **Step 7: Commit the snapshot core**

```bash
git add desktop/Package.swift desktop/Sources/AgentMeterCore/ProviderVisuals.swift desktop/Sources/AgentMeterUI/DesignSystem/AgentMeterTheme.swift desktop/Sources/AgentMeterWidgetCore desktop/Tests/AgentMeterWidgetCoreTests desktop/Tests/AgentMeterUITests/ThemeTests.swift
git commit -m "feat(widget): add shared snapshot model"
```

### Task 4: Resolve heat maps, layouts, freshness, and timeline checkpoints

**Files:**
- Create: `desktop/Sources/AgentMeterWidgetCore/WidgetConfiguration.swift`
- Create: `desktop/Sources/AgentMeterWidgetCore/WidgetHistoryProjection.swift`
- Create: `desktop/Sources/AgentMeterWidgetCore/WidgetPresentationResolver.swift`
- Create: `desktop/Sources/AgentMeterWidgetCore/WidgetTimelinePlanner.swift`
- Create: `desktop/Tests/AgentMeterWidgetCoreTests/WidgetHistoryProjectionTests.swift`
- Create: `desktop/Tests/AgentMeterWidgetCoreTests/WidgetPresentationResolverTests.swift`
- Create: `desktop/Tests/AgentMeterWidgetCoreTests/WidgetTimelinePlannerTests.swift`

**Interfaces:**
- Consumes: `WidgetSnapshot` and `WidgetWindowSelector` from Task 3.
- Produces: `WidgetRenderConfiguration`, `WidgetPresentation`, `WidgetHistoryProjection`, and `WidgetTimelinePlanner.plan(snapshot:nowEpoch:)`.

- [ ] **Step 1: Write failing heat-map tests**

Test fixed bands `zero`, `low`, `moderate`, `high`, `veryHigh`, missing gaps, 7/30-day clipping, single-provider scope, and combined averages that exclude missing providers:

```swift
let cells = WidgetHistoryProjection.heatMap(
    providers: [codexHistory(5), claudeHistory(nil)],
    range: .days30,
    scope: .combined,
    endingAtDayEpoch: day30
)
#expect(cells.last?.band == .low)
#expect(cells.last?.hasData == true)
```

- [ ] **Step 2: Write failing family/timeline tests**

Assert Dashboard maxima of 2/4/5/8 providers, `overflowCount`, small/medium history removal, module-removal order, Focus explicit windows, and **History unavailable for this window** beyond the four history-enabled windows. With injected epochs, assert stale at `max(2 * pollIntervalSeconds, 900)`, reset checkpoints inside 24 hours, **Refresh pending** after a passed reset, and a reload deadline no later than 24 hours.

- [ ] **Step 3: Run tests and verify the presentation types are missing**

Run: `swift test --package-path desktop --filter AgentMeterWidgetCoreTests`

Expected: FAIL because the configuration, projection, presentation, and timeline types do not exist.

- [ ] **Step 4: Implement platform-independent configuration**

Define `Codable`, `Equatable`, `Sendable`, `CaseIterable` enums for kind, family, percentage mode, modules, history style/period, heat scope, layout, density, theme, and tap destination. Use this boundary:

```swift
public struct WidgetRenderConfiguration: Equatable, Sendable {
    public let kind: WidgetKind
    public let providerIDs: [String]
    public let focusProviderID: String?
    public let outerWindowKind: String?
    public let innerWindowKind: String?
    public let percentageMode: WidgetPercentageMode
    public let modules: Set<WidgetModule>
    public let historyStyle: WidgetHistoryStyle
    public let historyPeriod: WidgetHistoryPeriod
    public let heatMapScope: WidgetHeatMapScope
    public let layout: WidgetLayoutPreset
    public let density: WidgetDensity
    public let theme: WidgetTheme
    public let tapDestination: WidgetTapDestination
}
```

- [ ] **Step 5: Implement projection and family resolution**

Map consumed points to `0`, `1...5`, `6...15`, `16...30`, and `31...Int.max`. Build `WidgetPresentation` with resolved providers, rings, reset state, history, status, freshness, and overflow. Remove unsupported modules in the fixed order history → status/freshness → additional providers, while retaining usage and primary reset.

- [ ] **Step 6: Implement timeline planning**

Return current, earliest future reset within 24 hours, stale transition, and 24-hour ceiling checkpoints. Mark reset epochs at or before `nowEpoch` as pending without changing percentage values.

- [ ] **Step 7: Run WidgetCore tests**

Run: `swift test --package-path desktop --filter AgentMeterWidgetCoreTests`

Expected: all tests PASS.

- [ ] **Step 8: Commit presentation rules**

```bash
git add desktop/Sources/AgentMeterWidgetCore desktop/Tests/AgentMeterWidgetCoreTests
git commit -m "feat(widget): resolve configurable presentations"
```

### Task 5: Persist snapshots and publish them from the host app

**Files:**
- Create: `desktop/Sources/AgentMeterWidgetCore/WidgetSnapshotStore.swift`
- Create: `desktop/Sources/AgentMeterUI/Widgets/WidgetSnapshotCoordinator.swift`
- Modify: `desktop/Sources/AgentMeterUI/State/AppModel.swift`
- Modify: `desktop/Sources/AgentMeterApp/AppEnvironment.swift`
- Create: `desktop/Tests/AgentMeterWidgetCoreTests/WidgetSnapshotStoreTests.swift`
- Create: `desktop/Tests/AgentMeterUITests/WidgetSnapshotCoordinatorTests.swift`
- Modify: `desktop/Tests/AgentMeterUITests/AppModelTests.swift`

**Interfaces:**
- Consumes: Task 2 history command and Task 3 snapshot builder.
- Produces: `WidgetSnapshotCoordinating.refresh(state:)` and atomic `widget-snapshot-v1.json` publication.

- [ ] **Step 1: Write failing store tests**

Use a temporary directory to prove round-trip decoding, `0o600` permissions, identical-write deduplication, 256 KiB rejection, temporary-file cleanup, newer-schema rejection, and preservation of the previous valid file after failure.

- [ ] **Step 2: Run store tests and verify the store is missing**

Run: `swift test --package-path desktop --filter WidgetSnapshotStoreTests`

Expected: FAIL because `WidgetSnapshotStore` does not exist.

- [ ] **Step 3: Implement the atomic store**

```swift
public struct WidgetSnapshotStore: Sendable {
    public static let fileName = "widget-snapshot-v1.json"
    public static let maximumBytes = 262_144
    public let url: URL

    public func load() throws -> WidgetSnapshot?
    @discardableResult
    public func writeIfChanged(_ snapshot: WidgetSnapshot) throws -> Bool
}
```

Encode with sorted keys, compare complete data, write a sibling temporary file, set owner read/write permissions, then replace atomically. Decode the schema header first and throw `WidgetSnapshotStoreError.unsupportedSchema(Int)` unless it equals `1`.

- [ ] **Step 4: Write failing coordinator tests**

Use a recording `BridgeAPI`, temporary store, and `WidgetTimelineReloading` spy. Assert one `history.summary` request per visible provider, a 30-day boundary, current time-zone identifier, no reload for identical state, one reload after changed usage, and preservation of cached history when one provider summary fails.

- [ ] **Step 5: Run coordinator tests and verify the coordinator is missing**

Run: `swift test --package-path desktop --filter WidgetSnapshotCoordinatorTests`

Expected: FAIL because the coordinator protocols and actor do not exist.

- [ ] **Step 6: Implement coordinator protocols and actor**

```swift
public protocol WidgetSnapshotCoordinating: Sendable {
    func refresh(state: ControlState) async
}

public protocol WidgetTimelineReloading: Sendable {
    func reloadWidgetTimelines() async
}

public actor WidgetSnapshotCoordinator: WidgetSnapshotCoordinating {
    public func refresh(state: ControlState) async
}
```

Query at most eight providers, merge successful summaries with cached failures, build/write the snapshot, and reload both widget kinds only after a changed file. Diagnostics contain only category, age, and byte count.

- [ ] **Step 7: Inject and invoke the coordinator**

Add a no-op default to `AppModel`. Refresh after startup supplemental data, explicit provider refresh, and newer `providers.changed`/`state.changed` events. In `AppEnvironment`, create one `UnixBridgeClient`, resolve the App Group URL, and create the real coordinator when available; otherwise use no-op so community SwiftPM builds remain functional.

- [ ] **Step 8: Run focused and full Swift tests**

Run: `swift test --package-path desktop --filter 'WidgetSnapshot|AppModel'`

Run: `swift test --package-path desktop`

Expected: all tests PASS.

- [ ] **Step 9: Commit host-app publication**

```bash
git add desktop/Sources/AgentMeterWidgetCore/WidgetSnapshotStore.swift desktop/Sources/AgentMeterUI/Widgets desktop/Sources/AgentMeterUI/State/AppModel.swift desktop/Sources/AgentMeterApp/AppEnvironment.swift desktop/Tests/AgentMeterWidgetCoreTests/WidgetSnapshotStoreTests.swift desktop/Tests/AgentMeterUITests/WidgetSnapshotCoordinatorTests.swift desktop/Tests/AgentMeterUITests/AppModelTests.swift
git commit -m "feat(macos): publish widget snapshots"
```

### Task 6: Add validated widget deep links

**Files:**
- Create: `desktop/Sources/AgentMeterWidgetCore/AgentMeterRoute.swift`
- Modify: `desktop/Sources/AgentMeterUI/State/AppModel.swift`
- Modify: `desktop/Sources/AgentMeterApp/AgentMeterApplication.swift`
- Modify: `desktop/Sources/AgentMeterUI/Features/Overview/OverviewView.swift`
- Modify: `desktop/Resources/Info.plist`
- Create: `desktop/Tests/AgentMeterWidgetCoreTests/AgentMeterRouteTests.swift`
- Modify: `desktop/Tests/AgentMeterUITests/AppModelTests.swift`

**Interfaces:**
- Consumes: normalized provider IDs and `NavigationSection`.
- Produces: `AgentMeterRoute(url:)`, `url`, and `AppModel.navigate(to:)`.

- [ ] **Step 1: Write failing route/navigation tests**

Cover `agentmeter://overview`, `agentmeter://agents`, percent-encoded valid providers, unknown hosts, extra path components, long IDs, and unsafe characters. Invalid routes fall back to Overview; provider routes select Overview and set `requestedProviderDetailID`.

- [ ] **Step 2: Run route tests and verify the route type is missing**

Run: `swift test --package-path desktop --filter 'AgentMeterRoute|AppModel'`

Expected: FAIL because `AgentMeterRoute` and widget navigation state do not exist.

- [ ] **Step 3: Implement routes**

```swift
public enum AgentMeterRoute: Equatable, Sendable {
    case overview
    case agents
    case provider(String)

    public init(url: URL)
    public var url: URL { get }
}
```

Reuse `[a-z0-9_-]{1,23}` and construct URLs with `URLComponents`.

- [ ] **Step 4: Register and handle the URL scheme**

Add `CFBundleURLTypes` for `agentmeter`. Attach `.onOpenURL` to main window content, call `model.navigate(to:)`, restore regular activation, and expose/consume `requestedProviderDetailID`.

- [ ] **Step 5: Open provider detail from Overview**

Observe the requested ID, match visible providers, assign existing `selectedProvider`, and clear only after a match. Preserve the request while unavailable.

- [ ] **Step 6: Run focused tests**

Run: `swift test --package-path desktop --filter 'AgentMeterRoute|AppModel'`

Expected: all focused tests PASS.

- [ ] **Step 7: Commit deep links**

```bash
git add desktop/Sources/AgentMeterWidgetCore/AgentMeterRoute.swift desktop/Sources/AgentMeterUI/State/AppModel.swift desktop/Sources/AgentMeterApp/AgentMeterApplication.swift desktop/Sources/AgentMeterUI/Features/Overview/OverviewView.swift desktop/Resources/Info.plist desktop/Tests/AgentMeterWidgetCoreTests/AgentMeterRouteTests.swift desktop/Tests/AgentMeterUITests/AppModelTests.swift
git commit -m "feat(macos): handle widget deep links"
```

### Task 7: Create the Xcode host project and embedded widget extension

**Files:**
- Create: `desktop/project.yml`
- Create: `desktop/AgentMeter.xcodeproj/project.pbxproj`
- Create: `desktop/scripts/generate-xcode-project.sh`
- Create: `desktop/Resources/AgentMeter.entitlements`
- Create: `desktop/Widgets/Resources/Info.plist`
- Create: `desktop/Widgets/Resources/AgentMeterWidget.entitlements`
- Create: `desktop/Widgets/Sources/AgentMeterWidgetBundle.swift`
- Create: `desktop/Widgets/Sources/Timeline/PlaceholderWidgets.swift`

**Interfaces:**
- Consumes: local Swift package products `AgentMeterCore`, `AgentMeterIPC`, `AgentMeterUI`, and `AgentMeterWidgetCore`.
- Produces: buildable `AgentMeter` app and embedded `AgentMeterWidgets.appex` targets.

- [ ] **Step 1: Add deterministic project generation**

The script runs `xcodegen --version`, rejects versions older than `2.45.4`, then executes:

```zsh
xcodegen generate --spec "${DESKTOP_ROOT}/project.yml" --project "${DESKTOP_ROOT}"
```

Define a local package at `path: .`; macOS 14 app, extension, and unit-test targets; the existing app sources; local package dependencies; and an embedded extension dependency.

- [ ] **Step 2: Add exact entitlements and extension metadata**

The app entitlement file contains only:

```xml
<key>com.apple.security.application-groups</key>
<array><string>group.com.prabhavalabs.agentmeter.shared</string></array>
```

The widget entitlement file contains that App Group plus:

```xml
<key>com.apple.security.app-sandbox</key>
<true/>
```

Do not grant the widget network, Bluetooth, user-selected-file, or keychain access.

The extension Info.plist uses package type `XPC!` and `NSExtensionPointIdentifier` value `com.apple.widgetkit-extension`.

- [ ] **Step 3: Add a compileable placeholder bundle**

Create `@main struct AgentMeterWidgetBundle: WidgetBundle` with two temporary `StaticConfiguration` widgets using the approved kinds. Each reads no state and renders fictional usage with `.containerBackground(for: .widget)`.

- [ ] **Step 4: Generate and build**

Install XcodeGen 2.45.4 from its official release or Homebrew, run `desktop/scripts/generate-xcode-project.sh`, then:

```bash
xcodebuild -project desktop/AgentMeter.xcodeproj -scheme AgentMeter -configuration Debug -derivedDataPath desktop/.build/xcode-derived CODE_SIGNING_ALLOWED=NO build
```

Expected: `** BUILD SUCCEEDED **` and the app contains `Contents/PlugIns/AgentMeterWidgets.appex`.

- [ ] **Step 5: Commit the scaffold**

```bash
git add desktop/project.yml desktop/AgentMeter.xcodeproj desktop/scripts/generate-xcode-project.sh desktop/Resources/AgentMeter.entitlements desktop/Widgets
git commit -m "build(macos): add WidgetKit extension target"
```

### Task 8: Add App Intent customization and dynamic entities

**Files:**
- Create: `desktop/Widgets/Sources/Configuration/WidgetEntities.swift`
- Create: `desktop/Widgets/Sources/Configuration/WidgetIntents.swift`
- Create: `desktop/Widgets/Sources/Configuration/IntentConfigurationAdapter.swift`
- Modify: `desktop/Widgets/Sources/Timeline/PlaceholderWidgets.swift`
- Create: `desktop/Widgets/Tests/WidgetIntentAdapterTests.swift`
- Modify: `desktop/project.yml`
- Regenerate: `desktop/AgentMeter.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: shared snapshot store and `WidgetRenderConfiguration`.
- Produces: `DashboardWidgetIntent`, `FocusWidgetIntent`, `ProviderEntity`, `WindowEntity`, and App Intent configurations.

- [ ] **Step 1: Write failing adapter tests**

Test Dashboard defaults: combined agents, used percentages, rings, 30-day heat map, comfortable density, system theme. Test Focus mapping: provider/window selections, remaining mode, trend history, compact density, midnight theme, and provider-detail tap.

- [ ] **Step 2: Run adapter tests and verify intent types are missing**

Run: `xcodebuild -project desktop/AgentMeter.xcodeproj -scheme AgentMeter -configuration Debug -derivedDataPath desktop/.build/xcode-derived CODE_SIGNING_ALLOWED=NO test`

Expected: FAIL because the entity, intent, and adapter types do not exist.

- [ ] **Step 3: Implement dynamic entities**

`ProviderEntity.id` is provider ID. `WindowEntity.id` is `providerID + ":" + windowKind`. Entity queries read the shared snapshot, preserve provider order, and return no entities before setup. Display representations contain only safe provider/window labels.

- [ ] **Step 4: Implement App Enums and intents**

Create AppEnum wrappers for percentage, history style/range, heat scope, trend window, layout, density, theme, and tap destination. Dashboard exposes ordered providers plus toggles for countdown, absolute reset date, provider status, freshness, heat map, and trend. Focus exposes provider plus optional outer/inner window entities and the same applicable toggles. Current allowance usage is mandatory. Use `parameterSummary` to keep editing scannable.

- [ ] **Step 5: Implement the pure adapter**

Map intents into Task 4 `WidgetRenderConfiguration`. Reject Focus windows whose provider differs from the selected provider and fall back to automatic selection.

- [ ] **Step 6: Replace static configurations**

Use `AppIntentConfiguration` for both kinds and support small, medium, large, and extra-large macOS families.

Run: `desktop/scripts/generate-xcode-project.sh`

- [ ] **Step 7: Run Xcode tests**

Run: `xcodebuild -project desktop/AgentMeter.xcodeproj -scheme AgentMeter -configuration Debug -derivedDataPath desktop/.build/xcode-derived CODE_SIGNING_ALLOWED=NO test`

Expected: adapter tests PASS and build succeeds.

- [ ] **Step 8: Commit intents**

```bash
git add desktop/Widgets desktop/project.yml desktop/AgentMeter.xcodeproj
git commit -m "feat(widget): add configurable widget intents"
```

### Task 9: Build shared visual components and the Focus widget

**Files:**
- Create: `desktop/Widgets/Sources/Components/WidgetTheme.swift`
- Create: `desktop/Widgets/Sources/Components/WidgetProviderMark.swift`
- Create: `desktop/Widgets/Sources/Components/DualUsageRing.swift`
- Create: `desktop/Widgets/Sources/Components/ResetSummary.swift`
- Create: `desktop/Widgets/Sources/Components/UsageHeatMap.swift`
- Create: `desktop/Widgets/Sources/Components/UsageTrendChart.swift`
- Create: `desktop/Widgets/Sources/Components/WidgetStateView.swift`
- Create: `desktop/Widgets/Sources/Focus/FocusWidgetView.swift`
- Create: `desktop/Widgets/Sources/Focus/FocusWidgetPreviews.swift`
- Create: `desktop/Widgets/Tests/WidgetComponentRenderingTests.swift`

**Interfaces:**
- Consumes: `WidgetPresentation` and provider accent values.
- Produces: reusable components and responsive `FocusWidgetView`.

- [ ] **Step 1: Write failing component render tests**

Use fictional `WidgetPresentation` fixtures and `ImageRenderer` to render `DualUsageRing`, `UsageHeatMap`, `UsageTrendChart`, and `FocusWidgetView`; assert each `nsImage` is non-nil in Light/Dark appearances.

- [ ] **Step 2: Run component tests and verify views are missing**

Run: `xcodebuild -project desktop/AgentMeter.xcodeproj -scheme AgentMeter -configuration Debug -derivedDataPath desktop/.build/xcode-derived CODE_SIGNING_ALLOWED=NO test`

Expected: FAIL because the component and Focus view types do not exist.

- [ ] **Step 3: Add fictional preview presentations**

Create preview-only Codex, Claude, Gemini, and Cursor snapshots with weekly/monthly and session windows. Include stale, missing percentage/reset, one-window, and history-unavailable states.

- [ ] **Step 4: Implement theme and provider marks**

Map system, midnight, neutral, and provider-tinted themes to semantic colors/container backgrounds. Convert `ProviderVisuals.accentHex` to SwiftUI `Color` and recreate provider glyphs without importing `AgentMeterUI`.

- [ ] **Step 5: Implement rings and reset summaries**

Draw outer/inner progress with trimmed circles rotated -90 degrees. Show used/remaining labels from presentation, omit absent inner rings, use monospaced digits, and provide one accessibility label covering both windows and reset states.

- [ ] **Step 6: Implement truthful history components**

Render gaps distinctly from zero cells and use five fixed bands. Render trends with Swift Charts and a fixed `0...100` Y-domain. Label both as allowance consumption; do not use token/activity wording.

- [ ] **Step 7: Implement Focus layouts**

Small shows provider, dual rings, and two reset summaries. Medium adds additional windows and compact history when enabled. Large/extra-large add full history, status, freshness, and model-specific rows. Apply `.privacySensitive()` and configured deep link.

- [ ] **Step 8: Run component tests and previews**

Run the unsigned Xcode build from Task 7.

Expected: all four family previews compile.

- [ ] **Step 9: Commit Focus UI**

```bash
git add desktop/Widgets/Sources/Components desktop/Widgets/Sources/Focus
git commit -m "feat(widget): build focused allowance views"
```

### Task 10: Build the responsive Dashboard widget

**Files:**
- Create: `desktop/Widgets/Sources/Dashboard/DashboardWidgetView.swift`
- Create: `desktop/Widgets/Sources/Dashboard/DashboardProviderRow.swift`
- Create: `desktop/Widgets/Sources/Dashboard/DashboardHistoryPanel.swift`
- Create: `desktop/Widgets/Sources/Dashboard/DashboardWidgetPreviews.swift`
- Create: `desktop/Widgets/Tests/WidgetRenderingTests.swift`
- Modify: `desktop/Widgets/Sources/Timeline/PlaceholderWidgets.swift`

**Interfaces:**
- Consumes: shared components, family-resolved presentation, and Dashboard intent.
- Produces: final Dashboard layouts and render smoke coverage.

- [ ] **Step 1: Write rendering smoke tests**

For every family, resolve fixtures, render Dashboard/Focus with `ImageRenderer`, set approved sizes, and assert `nsImage != nil`. Include Light/Dark, eight providers, `+N`, long names, unknown values, and unavailable states.

- [ ] **Step 2: Run rendering tests and verify Dashboard views are missing**

Run: `xcodebuild -project desktop/AgentMeter.xcodeproj -scheme AgentMeter -configuration Debug -derivedDataPath desktop/.build/xcode-derived CODE_SIGNING_ALLOWED=NO test`

Expected: FAIL because Dashboard view types do not exist.

- [ ] **Step 3: Implement provider rows and history panel**

Rows show provider mark, name, outer usage/reset, and inner usage when permitted. Medium+ uses dual rings; small is compact. History defaults to heat map, switches to trend, shows range labels, and calls combined scope **Average allowance consumed**.

- [ ] **Step 4: Implement family layouts**

Small: at most 2 providers, no history. Medium: at most 4, no history. Large: provider list plus history. Extra-large: up to 8, additional windows, wider history. Never scroll.

- [ ] **Step 5: Connect real Dashboard/Focus views**

Replace placeholder content closures with resolved views; retain fictional gallery placeholders.

- [ ] **Step 6: Run rendering tests**

Run: `xcodebuild -project desktop/AgentMeter.xcodeproj -scheme AgentMeter -configuration Debug -derivedDataPath desktop/.build/xcode-derived CODE_SIGNING_ALLOWED=NO test`

Expected: rendering tests PASS.

- [ ] **Step 7: Commit Dashboard UI**

```bash
git add desktop/Widgets/Sources/Dashboard desktop/Widgets/Sources/Timeline desktop/Widgets/Tests
git commit -m "feat(widget): build multi-agent dashboard"
```

### Task 11: Complete timeline loading and failure behavior

**Files:**
- Create: `desktop/Widgets/Sources/Timeline/WidgetSnapshotLoader.swift`
- Create: `desktop/Widgets/Sources/Timeline/DashboardTimelineProvider.swift`
- Create: `desktop/Widgets/Sources/Timeline/FocusTimelineProvider.swift`
- Delete: `desktop/Widgets/Sources/Timeline/PlaceholderWidgets.swift`
- Modify: `desktop/Widgets/Sources/AgentMeterWidgetBundle.swift`
- Create: `desktop/Widgets/Tests/WidgetTimelineProviderTests.swift`
- Modify: `desktop/Widgets/Tests/WidgetRenderingTests.swift`

**Interfaces:**
- Consumes: App Intent adapters, snapshot store, presentation resolver, and timeline planner.
- Produces: production `AppIntentTimelineProvider` implementations for both kinds.

- [ ] **Step 1: Write provider tests for every load state**

Use a temporary store and fixed clock. Cover no snapshot, valid/stale snapshot, passed reset, selected provider absent, percentage/reset/history missing, corrupt data, and schema `2`. Assert the exact copy **Open AgentMeter to configure this widget**, **Agent unavailable**, **Not reported**, **Reset time unavailable**, **History unavailable for this window**, **Refresh pending**, and **Update AgentMeter to view this widget**.

- [ ] **Step 2: Run provider tests and verify timeline types are missing**

Run: `xcodebuild -project desktop/AgentMeter.xcodeproj -scheme AgentMeter -configuration Debug -derivedDataPath desktop/.build/xcode-derived CODE_SIGNING_ALLOWED=NO test`

Expected: FAIL because the production loader and timeline providers do not exist.

- [ ] **Step 3: Implement snapshot loading**

Resolve the App Group URL, load schema `1`, and map store errors to `notConfigured`, `unavailable`, or `updateRequired`. Do not log provider content.

- [ ] **Step 4: Implement timeline providers**

Use fictional privacy-safe gallery data. For timelines, adapt intent, resolve presentation, create Task 4 entries, and use `.after(plan.reloadAfter)`. Dynamic countdowns use `Text(resetDate, style: .timer)` before reset; afterward show **Refresh pending**.

- [ ] **Step 5: Apply links, privacy, and accessibility**

Use one `widgetURL` per small widget and `Link` only where larger layouts expose distinct providers. Mark provider names/usage privacy-sensitive. Give rings, heat maps, errors, and stale states concise accessibility labels.

- [ ] **Step 6: Run package and Xcode tests**

Run: `swift test --package-path desktop`

Run: `xcodebuild -project desktop/AgentMeter.xcodeproj -scheme AgentMeter -configuration Debug -derivedDataPath desktop/.build/xcode-derived CODE_SIGNING_ALLOWED=NO test`

Expected: all tests PASS.

- [ ] **Step 7: Commit production providers**

```bash
git add desktop/Widgets/Sources/Timeline desktop/Widgets/Sources/AgentMeterWidgetBundle.swift desktop/Widgets/Tests
git commit -m "feat(widget): load live snapshot timelines"
```

### Task 12: Package, verify, document, and regression-test

**Files:**
- Modify: `desktop/scripts/package-app.sh`
- Create: `desktop/scripts/verify-widget-bundle.sh`
- Modify: `.github/workflows/ci.yml`
- Modify: `Makefile`
- Modify: `README.md`
- Modify: `docs/macos-app.md`
- Modify: `docs/development.md`
- Modify: `docs/architecture.md`

**Interfaces:**
- Consumes: signed Xcode app/extension and existing bundled bridge.
- Produces: verified managed widget build while preserving community app-only packaging.

- [ ] **Step 1: Write bundle verification first**

Create a zsh script accepting one app path and checking the exact extension path and identifiers:

```zsh
APP_BUNDLE=$1
WIDGET_BUNDLE=${APP_BUNDLE}/Contents/PlugIns/AgentMeterWidgets.appex
test -d "${WIDGET_BUNDLE}"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${WIDGET_BUNDLE}/Contents/Info.plist")" = "com.prabhavalabs.agentmeter.desktop.widget"
test "$(/usr/libexec/PlistBuddy -c 'Print :NSExtension:NSExtensionPointIdentifier' "${WIDGET_BUNDLE}/Contents/Info.plist")" = "com.apple.widgetkit-extension"
```

When signatures exist, assert app/extension entitlements both contain the shared group. Add `--community` mode asserting no `Contents/PlugIns` directory.

- [ ] **Step 2: Run verification against the current community app**

Run: `desktop/scripts/verify-widget-bundle.sh --community desktop/dist/AgentMeter.app`

Expected: PASS when the existing app has no `PlugIns` directory.

Run: `desktop/scripts/verify-widget-bundle.sh desktop/dist/AgentMeter.app`

Expected: FAIL because the current app has no embedded WidgetKit extension.

- [ ] **Step 3: Split community and managed packaging**

Keep the current SwiftPM/manual path equivalent for community. For managed mode, build Release Xcode, copy its app to `desktop/dist`, add the signed PyInstaller bridge/resources, preserve the extension signature, and re-sign only the outer app with app entitlements and without `--deep`.

Require `AGENTMETER_DEVELOPMENT_TEAM`, `AGENTMETER_APP_PROVISIONING_PROFILE`, and `AGENTMETER_WIDGET_PROVISIONING_PROFILE` in managed mode; fail precisely if absent.

- [ ] **Step 4: Add Make and CI entry points**

Add `desktop-project`, `desktop-widget-build`, and `desktop-widget-verify`. CI builds the committed project with signing disabled, verifies extension structure, then runs existing community packaging/DMG checks unchanged.

- [ ] **Step 5: Document behavior and development**

Document families, configuration, used/remaining, heat-map/trend semantics, refresh pending, local snapshot privacy, App Group signing, managed-only first release, XcodeGen 2.45.4+, and unsigned build commands.

- [ ] **Step 6: Run complete verification**

Run: `.venv/bin/ruff check .`

Run: `.venv/bin/ruff format --check .`

Run: `.venv/bin/pytest`

Run: `swift test --package-path desktop`

Run: `xcodebuild -project desktop/AgentMeter.xcodeproj -scheme AgentMeter -configuration Debug -derivedDataPath desktop/.build/xcode-derived CODE_SIGNING_ALLOWED=NO test`

Run: `desktop/scripts/package-app.sh`

Run: `desktop/scripts/create-community-dmg.sh`

Run: `desktop/scripts/verify-community-release.sh`

Expected: every command exits `0`; unsigned Xcode app contains the widget; community DMG remains app-only.

- [ ] **Step 7: Perform signed manual acceptance**

With a real development team/App Group profiles, verify gallery presence; independent instances; all sizes; heat/trend, used/remaining, density, theme; updates with main window closed; bridge interruption; reset-boundary fake fixture; and deep links to Overview, Agents, and provider detail.

- [ ] **Step 8: Commit packaging and docs**

```bash
git add desktop/scripts/package-app.sh desktop/scripts/verify-widget-bundle.sh .github/workflows/ci.yml Makefile README.md docs/macos-app.md docs/development.md docs/architecture.md
git commit -m "build(macos): package and verify widgets"
```

---

## Final Verification Checklist

- [ ] `git status --short` contains no unintended files; `.superpowers/` remains uncommitted.
- [ ] `git diff --check` reports no whitespace errors.
- [ ] Host aggregation handles resets, gaps, DST, and provider isolation.
- [ ] Shared JSON contains no identity, prompt, code, path, token, cookie, or billing fields.
- [ ] Dashboard and Focus instances retain independent configuration.
- [ ] Weekly/monthly values are primary and shorter windows remain visible.
- [ ] Small/medium omit history; large/extra-large honor heat map or trend.
- [ ] Passed resets say **Refresh pending** until fresh provider data.
- [ ] Extension has no IPC, Bluetooth, SQLite, network, or keychain dependency.
- [ ] Managed app/extension share the App Group and pass strict code-sign verification.
- [ ] Community DMG still installs/runs without widget or App Group dependency.
- [ ] Host, Swift package, Xcode widget, packaging, and release verification pass from a clean checkout.
