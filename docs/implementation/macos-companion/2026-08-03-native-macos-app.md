# Native AgentMeter macOS Application Implementation Plan

**Goal:** Build a polished native SwiftUI menu-bar application that presents the bridge state,
manages one AgentMeter, edits confirmed device settings, and remains responsive in System, Light,
and Dark appearances.

**Architecture:** Use a SwiftPM-first app with framework-independent core models, an actor-based
Unix-socket IPC client, a `@MainActor @Observable` application model, and small SwiftUI feature
views. The app observes the bridge's event stream instead of polling and uses a deterministic fake
bridge for previews, tests, and development without hardware.

**Tech stack:** Swift 6, macOS 14+, SwiftUI, Observation, Swift Charts, Network, ServiceManagement,
OSLog, XCTest, AppKit only for macOS-specific integration.

## Global constraints

- Native macOS only; no Electron, browser view, JavaScript runtime, or third-party UI framework.
- Target macOS 14 or later and compile with Swift 6 strict concurrency.
- The app never imports CoreBluetooth and never starts CodexBar or a provider CLI directly.
- The bridge is the only BLE/data owner; the app speaks IPC schema v1.
- Main window default is approximately 1120 x 760 points and minimum 900 x 620 points.
- Closing the window leaves the menu bar and synchronization running; explicit Quit stops them.
- Support System, Light, and Dark appearance, native full screen, keyboard navigation, VoiceOver,
  Reduce Motion, Increase Contrast, and Reduce Transparency.
- Use nullable UI for unavailable metrics; never turn missing values into zero.
- Do not display or persist credentials, account identity, prompts, raw provider errors, or code.
- Keep every screen functional with one through eight providers and long allowed labels.

## File map

| File group | Responsibility |
| --- | --- |
| `desktop/Sources/AgentMeterCore/Models` | Codable bridge/device/provider/settings state |
| `desktop/Sources/AgentMeterUI/State` | Main-actor app state, preferences, and user intents |
| `desktop/Sources/AgentMeterIPC` | Unix socket, request correlation, event stream |
| `desktop/Sources/AgentMeterUI/DesignSystem` | Semantic colours, typography, status components |
| `desktop/Sources/AgentMeterUI/Features` | Window content and all feature screens |
| `desktop/Sources/AgentMeterUI/Resources` | Asset catalogue and localizable copy |
| `desktop/Sources/AgentMeterApp` | App scene, menu bar scene, commands, service adapters |
| `desktop/Tests` | Core, IPC, view-model, snapshot, and accessibility-focused tests |

---

### Task 1: Scaffold SwiftPM modules and decode the IPC contract

**Files:**

- Create: `desktop/Package.swift`
- Create: `desktop/Sources/AgentMeterCore/Models/ConnectionPhase.swift`
- Create: `desktop/Sources/AgentMeterCore/Models/ProviderUsage.swift`
- Create: `desktop/Sources/AgentMeterCore/Models/DeviceState.swift`
- Create: `desktop/Sources/AgentMeterCore/Models/DeviceSettings.swift`
- Create: `desktop/Sources/AgentMeterCore/Models/ControlState.swift`
- Create: `desktop/Sources/AgentMeterCore/Formatting.swift`
- Create: `desktop/Tests/AgentMeterCoreTests/ModelDecodingTests.swift`
- Create: `desktop/Tests/AgentMeterCoreTests/FormattingTests.swift`
- Copy as test resources: `fixtures/desktop-ipc-*.json`

**Interfaces:**

- Produces `ControlState: Codable, Equatable, Sendable` matching Python camelCase exactly.
- Produces `ConnectionPhase: String, Codable, CaseIterable, Sendable`.
- Produces pure `UsageFormatting` and `TelemetryFormatting` functions.
- Consumed by IPC, app state, and every view.

- [ ] **Step 1: Add `Package.swift` with focused targets**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AgentMeterDesktop",
    platforms: [.macOS(.v14)],
    products: [.library(name: "AgentMeterCore", targets: ["AgentMeterCore"])],
    targets: [
        .target(name: "AgentMeterCore"),
        .testTarget(
            name: "AgentMeterCoreTests",
            dependencies: ["AgentMeterCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
```

- [ ] **Step 2: Write failing fixture-decoding tests**

```swift
@Test func statusFixturePreservesUnavailableBatteryValues() throws {
    let data = try Fixture.data(named: "desktop-ipc-status-v1")
    let envelope = try JSONDecoder().decode(StatusEnvelope.self, from: data)

    #expect(envelope.payload.connection.phase == .connected)
    #expect(envelope.payload.telemetry?.batteryPresent == false)
    #expect(envelope.payload.telemetry?.batteryPercent == nil)
    #expect(envelope.payload.telemetry?.inputCurrentMa == nil)
}
```

Use Swift Testing (`import Testing`) for core, IPC, state, and view-model tests. Reserve XCTest for
the AppKit image-rendering target where `XCTestCase` lifecycle is useful.

- [ ] **Step 3: Run tests and verify missing-model failure**

```bash
swift test --package-path desktop
```

- [ ] **Step 4: Implement exact Codable models**

Use value types and explicit optional fields. Core shapes include:

```swift
public enum ConnectionPhase: String, Codable, CaseIterable, Sendable {
    case stopped
    case bluetoothUnavailable
    case searching
    case connecting
    case authenticating
    case synchronizing
    case connected
    case degraded
    case retrying
}

public struct DeviceTelemetry: Codable, Equatable, Sendable {
    public let powerSource: String?
    public let usbPresent: Bool?
    public let batteryPresent: Bool?
    public let charging: Bool?
    public let batteryPercent: Int?
    public let batteryVoltageMv: Int?
    public let vbusVoltageMv: Int?
    public let inputCurrentMa: Int?
    public let uptimeSeconds: Int?
    public let freeHeapBytes: Int?
    public let minimumFreeHeapBytes: Int?
    public let displayOn: Bool?
    public let displayDimmed: Bool?
    public let brightnessPercent: Int?
    public let boardTemperatureC: Double?
}
```

Define provider windows with optional `usedPercent` and `resetAtEpoch`; validate percentages for
presentation without failing the entire state when a future bridge sends an unknown status.

- [ ] **Step 5: Implement pure formatting and state labels**

Formatting functions accept a fixed `now` for tests. Return `Unavailable`, `Not installed`,
`USB`, `42%`, `Resets in 2h 14m`, and `Updated 3m ago` from typed values. Never derive a battery
percentage from voltage in Swift.

- [ ] **Step 6: Run core tests and build**

```bash
swift test --package-path desktop --filter AgentMeterCoreTests
swift build --package-path desktop
```

- [ ] **Step 7: Commit the core package**

```bash
git add desktop/Package.swift desktop/Sources/AgentMeterCore \
  desktop/Tests/AgentMeterCoreTests
git commit -m "feat(mac): add desktop state models"
```

---

### Task 2: Implement the actor-based Unix IPC client and fake bridge

**Files:**

- Create: `desktop/Sources/AgentMeterIPC/BridgeAPI.swift`
- Create: `desktop/Sources/AgentMeterIPC/IpcEnvelope.swift`
- Create: `desktop/Sources/AgentMeterIPC/UnixBridgeClient.swift`
- Create: `desktop/Sources/AgentMeterIPC/JsonLineDecoder.swift`
- Create: `desktop/Sources/AgentMeterIPC/FakeBridgeAPI.swift`
- Create: `desktop/Tests/AgentMeterIPCTests/JsonLineDecoderTests.swift`
- Create: `desktop/Tests/AgentMeterIPCTests/UnixBridgeClientTests.swift`
- Modify: `desktop/Package.swift`

**Interfaces:**

- Produces `BridgeAPI: Sendable`.
- Produces `UnixBridgeClient` using `NWConnection` with a Unix endpoint.
- Produces `FakeBridgeAPI` that replays repository fixtures.
- Consumed by `AppModel` in Task 3.

- [ ] **Step 1: Add IPC library and test targets**

Add `.library(name: "AgentMeterIPC", targets: ["AgentMeterIPC"])`, a target depending on
`AgentMeterCore`, and `AgentMeterIPCTests` depending on `AgentMeterIPC` to `Package.swift`.

- [ ] **Step 2: Define the app-facing API**

```swift
public protocol BridgeAPI: Sendable {
    func connect() async throws
    func status() async throws -> ControlState
    func scan() async throws -> [PeripheralSummary]
    func perform(_ command: BridgeCommand) async throws -> BridgeResult
    func events() -> AsyncThrowingStream<BridgeEvent, Error>
    func close() async
}
```

`BridgeCommand` has cases for connect, disconnect, forget, identify, refresh device/providers,
patch settings, update providers, clear/query history, restart bridge, sleep, and wake. Encode each
case to the exact IPC type from the bridge plan.

- [ ] **Step 3: Write failing incremental-line-decoder tests**

```swift
@Test func decoderHandlesSplitAndCombinedFrames() throws {
    var decoder = JsonLineDecoder(maximumBytes: 65_536)
    #expect(try decoder.append(Data("{\"schema".utf8)).isEmpty)
    let frames = try decoder.append(
        Data("Version\":1}\n{\"schemaVersion\":1}\n".utf8)
    )

    #expect(frames.count == 2)
}
```

Test invalid UTF-8, a 65537-byte line, clean EOF, response/error/event distinction, and unknown
event types.

- [ ] **Step 4: Write failing request-correlation tests with a temporary Unix server**

Start an `NWListener` or POSIX test server on a temporary socket. Send responses in reverse order
and an event between them; prove each continuation gets its own request ID and the event stream
receives only the event. Test disconnect fails all pending requests exactly once.

- [ ] **Step 5: Run IPC tests and verify failure**

```bash
swift test --package-path desktop --filter AgentMeterIPCTests
```

- [ ] **Step 6: Implement `UnixBridgeClient` as an actor**

Use `NWEndpoint.unix(path:)`, a fresh 64-character safe request ID, one receive loop, and a
dictionary of checked continuations keyed by ID. `connect()` performs `hello`, checks schema
version 1, requests initial state, then subscribes. Enforce the 65536-byte line limit before JSON
decoding. Cancel the receive task and finish the event stream during `close()`.

Do not log payloads. OSLog may include message type and private request ID only.

- [ ] **Step 7: Implement deterministic `FakeBridgeAPI`**

Load the checked-in fixtures, expose scripted connection/provider/settings transitions, and keep
all operations in memory. Provide presets for connected USB-only, disconnected, pairing,
provider-unavailable, legacy firmware, and settings-conflict states.

Expose these test controls with the same names used by later tasks:

```swift
public static func connected(revision: UInt64) -> FakeBridgeAPI
public static func disconnected(settingsRevision: UInt64) -> FakeBridgeAPI
public func emitState(revision: UInt64, phase: ConnectionPhase)
public func connectAndConfirm(settingsRevision: UInt64, alwaysOn: Bool)
public func drain() async
```

- [ ] **Step 8: Run IPC tests and complete Swift build**

```bash
swift test --package-path desktop --filter AgentMeterIPCTests
swift build --package-path desktop
```

- [ ] **Step 9: Commit IPC**

```bash
git add desktop/Package.swift desktop/Sources/AgentMeterIPC desktop/Tests/AgentMeterIPCTests
git commit -m "feat(mac): connect to the bridge over private IPC"
```

---

### Task 3: Add the main-actor application model and user intents

**Files:**

- Create: `desktop/Sources/AgentMeterUI/State/AppModel.swift`
- Create: `desktop/Sources/AgentMeterUI/State/AppPreferences.swift`
- Create: `desktop/Sources/AgentMeterUI/State/NavigationSection.swift`
- Create: `desktop/Tests/AgentMeterUITests/AppModelTests.swift`
- Create: `desktop/Tests/AgentMeterUITests/AppPreferencesTests.swift`
- Modify: `desktop/Package.swift`

**Interfaces:**

- Produces `@MainActor @Observable final class AppModel`.
- Produces `AppearancePreference.system/light/dark` and window/navigation state.
- Consumed by the app scene and every feature view.

- [ ] **Step 1: Add the UI library and state test target**

Add `.library(name: "AgentMeterUI", targets: ["AgentMeterUI"])`, an `AgentMeterUI` target depending
on `AgentMeterCore` and `AgentMeterIPC`, and `AgentMeterUITests` depending on those three modules.
Do not declare resources until the design-system task creates them.

- [ ] **Step 2: Write failing startup and event tests**

```swift
@MainActor
@Test func startLoadsStateThenAppliesOnlyNewerEvents() async throws {
    let bridge = FakeBridgeAPI.connected(revision: 4)
    let model = AppModel(bridge: bridge, preferences: .inMemory)

    await model.start()
    await bridge.emitState(revision: 3, phase: .retrying)
    await bridge.emitState(revision: 5, phase: .connected)
    await bridge.drain()

    #expect(model.state.revision == 5)
    #expect(model.state.connection.phase == .connected)
}
```

Test start failure, reconnect, command-in-progress disabling, settings Saving/Synced/Waiting,
revision conflict presentation, provider reorder, history clear confirmation, and event task
cancellation on stop.

- [ ] **Step 3: Write failing appearance persistence tests**

```swift
@Test func appearanceDefaultsToSystemAndRoundTrips() {
    let defaults = isolatedDefaults()
    let preferences = AppPreferences(defaults: defaults)
    #expect(preferences.appearance == .system)

    preferences.appearance = .light

    #expect(AppPreferences(defaults: defaults).appearance == .light)
}
```

- [ ] **Step 4: Run app-model tests and verify failure**

```bash
swift test --package-path desktop --filter AgentMeterUITests
```

- [ ] **Step 5: Implement one observable source of truth**

`AppModel` owns current `ControlState`, selected navigation section, discovery results, active
sheet, transient banner, command states, appearance preference, and bridge reachability. It starts
one event task and maps user methods directly to `BridgeCommand`:

```swift
public func reconnect() async
public func scan() async
public func connect(to identifier: String) async
public func disconnect() async
public func forgetDevice() async
public func identifyDevice() async
public func refreshProviders() async
public func patchSettings(_ patch: DeviceSettingsPatch) async
public func reorderProviders(from: IndexSet, to: Int) async
public func clearHistory() async
public func restartBridge() async
```

Never mutate confirmed device settings optimistically. Keep a separate pending patch and derive
Saving/Synced/Waiting from command and connection state.

- [ ] **Step 6: Implement bounded user preferences**

Persist appearance, selected sidebar section, sidebar visibility, onboarding completion, launch
at login preference, and notification choices. Let macOS autosave the window frame by a stable
window identifier. Do not put device/provider state in UserDefaults.

- [ ] **Step 7: Run model tests and full Swift build**

```bash
swift test --package-path desktop --filter AgentMeterUITests
swift build --package-path desktop
```

- [ ] **Step 8: Commit application state**

```bash
git add desktop/Package.swift desktop/Sources/AgentMeterUI/State \
  desktop/Tests/AgentMeterUITests/AppModelTests.swift \
  desktop/Tests/AgentMeterUITests/AppPreferencesTests.swift
git commit -m "feat(mac): manage desktop application state"
```

---

### Task 4: Build the native scene, menu bar, and design system

**Files:**

- Create: `desktop/Sources/AgentMeterApp/App/AgentMeterApplication.swift`
- Create: `desktop/Sources/AgentMeterApp/App/AppEnvironment.swift`
- Create: `desktop/Sources/AgentMeterUI/Root/RootView.swift`
- Create: `desktop/Sources/AgentMeterUI/Root/MenuBarContent.swift`
- Create: `desktop/Sources/AgentMeterUI/Root/Sidebar.swift`
- Create: `desktop/Sources/AgentMeterUI/DesignSystem/AgentMeterTheme.swift`
- Create: `desktop/Sources/AgentMeterUI/DesignSystem/StatusPill.swift`
- Create: `desktop/Sources/AgentMeterUI/DesignSystem/ProviderMark.swift`
- Create: `desktop/Sources/AgentMeterUI/DesignSystem/MetricCard.swift`
- Create: `desktop/Sources/AgentMeterUI/Resources/Assets.xcassets/Contents.json`
- Create: `desktop/Tests/AgentMeterUITests/ThemeTests.swift`
- Create: `desktop/Tests/AgentMeterUITests/MenuBarModelTests.swift`
- Modify: `desktop/Package.swift`

**Interfaces:**

- Produces the running window/menu shell used by all feature screens.
- Consumes `AppModel` and semantic state only.

- [ ] **Step 1: Add the executable, app tests, and UI resources**

Add the `AgentMeter` executable product, `AgentMeterApp` executable target depending on Core, IPC,
and UI, and `AgentMeterAppTests` depending on those modules. Add
`resources: [.process("Resources")]` to `AgentMeterUI` now that the resource directory exists.

- [ ] **Step 2: Write failing semantic-theme tests**

Test that System maps to no override, Light/Dark map to the correct `ColorScheme`, all provider
accents remain distinct, warning/critical states include text symbols, and increased-contrast
tokens strengthen borders without changing provider identity.

- [ ] **Step 3: Implement semantic colours and provider marks**

Use dynamic `Color(nsColor:)` surfaces and asset colours with Any/Dark variants. Keep violet as
the app accent and draw provider marks with SwiftUI `Shape`/SF Symbols rather than remote images.
Unknown providers use a purple initial in a labelled circle. Every mark has an accessibility
label and is hidden from VoiceOver when adjacent text already names the provider.

- [ ] **Step 4: Implement the app scenes**

```swift
@main
@MainActor
struct AgentMeterApplication: App {
    @State private var model: AppModel

    init() {
        let environment = AppEnvironment.current
        _model = State(initialValue: AppModel(
            bridge: environment.bridge,
            preferences: environment.preferences
        ))
    }

    var body: some Scene {
        WindowGroup("AgentMeter", id: "main") {
            RootView(model: model)
                .frame(minWidth: 900, minHeight: 620)
                .preferredColorScheme(model.preferences.appearance.colorScheme)
                .task { await model.start() }
        }
        .defaultSize(width: 1120, height: 760)

        MenuBarExtra {
            MenuBarContent(model: model)
        } label: {
            Label("AgentMeter", systemImage: model.menuBarSymbol)
        }
    }
}
```

`AppEnvironment.current` creates `UnixBridgeClient` for normal launches and accepts
`--fake-bridge <preset>` only from a debug build. It injects the shared preferences store and does
not hide a live-bridge startup failure behind fake data.

Do not use `.windowResizability(.contentSize)` because it blocks responsive resizing. Native full
screen remains enabled. Give the main window a stable autosave name through AppKit interop.

- [ ] **Step 5: Implement sidebar and compact menu behaviour**

Use `NavigationSplitView` with Overview, Device, Agents, Display, and Diagnostics. Collapse the
sidebar when horizontal size is compact. Menu-bar content shows device/connection, last sync,
brief enabled-provider summary, Open, Reconnect/Disconnect, Refresh Usage, Launch at Login, and
Quit. Use no chart and no independent timer in the menu.

- [ ] **Step 6: Run shell tests and manually inspect both appearances**

```bash
swift test --package-path desktop --filter AgentMeterUITests
swift run --package-path desktop AgentMeter --fake-bridge connected-usb
```

Inspect System/Light/Dark, 900 x 620, 1120 x 760, 1440 x 900, sidebar collapse, window close, menu
open, and native full screen.

- [ ] **Step 7: Commit shell and design system**

```bash
git add desktop/Package.swift desktop/Sources/AgentMeterApp/App \
  desktop/Sources/AgentMeterUI/Root desktop/Sources/AgentMeterUI/DesignSystem \
  desktop/Sources/AgentMeterUI/Resources desktop/Tests/AgentMeterUITests
git commit -m "feat(mac): add native window and menu bar"
```

---

### Task 5: Implement Overview and Device management

**Files:**

- Create: `desktop/Sources/AgentMeterUI/Features/Overview/OverviewView.swift`
- Create: `desktop/Sources/AgentMeterUI/Features/Overview/DeviceHealthStrip.swift`
- Create: `desktop/Sources/AgentMeterUI/Features/Overview/ProviderUsageCard.swift`
- Create: `desktop/Sources/AgentMeterUI/Features/Overview/UsageTrendChart.swift`
- Create: `desktop/Sources/AgentMeterUI/Features/Device/DeviceView.swift`
- Create: `desktop/Sources/AgentMeterUI/Features/Device/PairingSheet.swift`
- Create: `desktop/Sources/AgentMeterUI/Features/Device/TelemetrySection.swift`
- Create: `desktop/Tests/AgentMeterUITests/OverviewViewModelTests.swift`
- Create: `desktop/Tests/AgentMeterUITests/DeviceViewModelTests.swift`

**Interfaces:**

- Produces Overview and Device screens reachable from `RootView`.
- Consumes only `AppModel` intents and typed state.

- [ ] **Step 1: Add failing adaptive-layout and value tests**

Extract pure layout decisions and test four/two/one column thresholds, one through eight providers,
unknown percentages, stale timestamps, no battery, legacy firmware, and long labels. Assert the
USB-only model produces `Battery: Not installed` and no current row.

- [ ] **Step 2: Implement Overview with an adaptive grid**

Use `LazyVGrid(columns: [GridItem(.adaptive(minimum: 210, maximum: 320))])`. Cards contain the
provider mark, name/status, most urgent real percentage, progress ring/bar, reset countdown, and
stale age. A missing percentage shows an em dash and `Unavailable`, not an empty progress value.

The health strip shows Bluetooth, power, battery, firmware, and last sync. The trend chart appears
only with two or more samples and uses provider percentages, not request totals.

- [ ] **Step 3: Implement Device and pairing states**

Device sections show selected peripheral, adapter/permission status, signal quality, protocol and
firmware versions, uptime, power, and supported telemetry. Actions call AppModel and display
progress. PairingSheet scans, sorts by signal, selects one device, connects, and shows the five
onboarding phases. Empty/error states include retry and System Settings actions.

Require confirmation before Forget or Restart. Explain the possible macOS Bluetooth Settings
cleanup after forgetting.

- [ ] **Step 4: Add keyboard and VoiceOver metadata**

Give each provider card a combined readable label, expose progress as a percentage value, order
health metrics before actions, and make pairing rows keyboard selectable. Do not announce
decorative marks twice.

- [ ] **Step 5: Run tests and inspect fake scenarios**

```bash
swift test --package-path desktop --filter AgentMeterUITests
swift run --package-path desktop AgentMeter --fake-bridge connected-usb
swift run --package-path desktop AgentMeter --fake-bridge disconnected
swift run --package-path desktop AgentMeter --fake-bridge legacy
```

- [ ] **Step 6: Commit Overview and Device**

```bash
git add desktop/Sources/AgentMeterUI/Features/Overview \
  desktop/Sources/AgentMeterUI/Features/Device \
  desktop/Tests/AgentMeterUITests/OverviewViewModelTests.swift \
  desktop/Tests/AgentMeterUITests/DeviceViewModelTests.swift
git commit -m "feat(mac): add device overview and pairing"
```

---

### Task 6: Implement Agents, Display, Diagnostics, and first run

**Files:**

- Create: `desktop/Sources/AgentMeterUI/Features/Agents/AgentsView.swift`
- Create: `desktop/Sources/AgentMeterUI/Features/Display/DisplayView.swift`
- Create: `desktop/Sources/AgentMeterUI/Features/Display/DisplayPreview.swift`
- Create: `desktop/Sources/AgentMeterUI/Features/Diagnostics/DiagnosticsView.swift`
- Create: `desktop/Sources/AgentMeterUI/Features/Onboarding/OnboardingView.swift`
- Create: `desktop/Sources/AgentMeterUI/Features/Settings/AppSettingsView.swift`
- Create: `desktop/Sources/AgentMeterUI/Platform/SystemSettingsLink.swift`
- Create: `desktop/Sources/AgentMeterUI/Platform/WorkspacePowerObserver.swift`
- Create: `desktop/Sources/AgentMeterUI/Platform/UserNotificationController.swift`
- Create: `desktop/Tests/AgentMeterUITests/SettingsFlowTests.swift`
- Create: `desktop/Tests/AgentMeterUITests/DiagnosticsTests.swift`
- Create: `desktop/Tests/AgentMeterUITests/UserNotificationControllerTests.swift`

**Interfaces:**

- Completes all application screens and system interactions except release packaging.

- [ ] **Step 1: Write failing bidirectional settings-flow tests**

```swift
@MainActor
@Test func offlineChangeShowsWaitingUntilConfirmedRevisionArrives() async {
    let bridge = FakeBridgeAPI.disconnected(settingsRevision: 8)
    let model = AppModel(bridge: bridge, preferences: .inMemory)
    await model.patchSettings(.init(alwaysOn: true))
    #expect(model.settingsSaveState == .waitingForDevice)

    await bridge.connectAndConfirm(settingsRevision: 9, alwaysOn: true)
    await bridge.drain()
    #expect(model.settingsSaveState == .synced)
}
```

Test a revision conflict, touchscreen event, at-least-one-visible rule, provider reorder, unknown
future provider, unsupported brightness, and System/Light/Dark selection.

- [ ] **Step 2: Implement Agents and Display**

Agents separates host collection enablement from device visibility/order and shows each
provider's last collection and stale/error reason. Display uses native toggles, sliders, steppers,
and drag reordering for always-on, full view, interval 3–60, brightness, dim/off delays,
thresholds, and sound. Hide or disable unsupported fields with an explanation. DisplayPreview
uses the real provider order and semantic colours.

- [ ] **Step 3: Implement Diagnostics and privacy-safe copy**

Show app/bridge/firmware/protocol versions, bridge state, last bounded diagnostic events, and
dependency health. Restart Bridge, Refresh Device State, Clear History, and Copy Diagnostics use
confirmations where destructive. Build the clipboard document from the already-sanitized IPC
diagnostics plus app versions; never read raw logs directly from Swift.

- [ ] **Step 4: Implement onboarding and power notifications**

Onboarding presents bridge, Bluetooth permission, device selection, encrypted sync, and first
provider refresh. `WorkspacePowerObserver` listens for `NSWorkspace.willSleepNotification` and
`didWakeNotification`, sending `system.sleep`/`system.wake` to AppModel. Register once and remove
observers on deinit.

- [ ] **Step 5: Implement app preferences and launch-at-login intent**

AppSettingsView offers System/Light/Dark, Launch at Login, and optional local notifications.
Expose launch-at-login through an injected protocol; the distribution plan implements
`SMAppService.mainApp` and tests error mapping. The source-run implementation reports that app
bundling is required rather than claiming success.

- [ ] **Step 6: Implement opt-in local notifications**

Request notification permission only when the user enables it. Notify for a threshold event, a
reset event, or a connection that remains lost beyond a 60-second grace period. Deduplicate using
the bridge event ID and persist only a bounded set of recent IDs. Notification copy contains the
provider display name and percentage when already allowlisted, never raw errors or account data.
Clicking a notification activates the main AgentMeter window. Tests use an injected notification
center and clock to prove permission, grace, deduplication, opt-out, and bounded ID retention.

- [ ] **Step 7: Run all Swift tests and manual appearance/resizing matrix**

```bash
swift test --package-path desktop
swift build --package-path desktop
swift run --package-path desktop AgentMeter --fake-bridge connected-usb
```

Inspect every sidebar screen in System/Light/Dark at 900 x 620, 1120 x 760, 1440 x 900, and native
full screen. Enable Increase Contrast, Reduce Transparency, and Reduce Motion. Navigate every
control by keyboard and inspect VoiceOver labels.

- [ ] **Step 8: Commit remaining screens**

```bash
git add desktop/Sources/AgentMeterUI/Features/Agents \
  desktop/Sources/AgentMeterUI/Features/Display \
  desktop/Sources/AgentMeterUI/Features/Diagnostics \
  desktop/Sources/AgentMeterUI/Features/Onboarding \
  desktop/Sources/AgentMeterUI/Features/Settings \
  desktop/Sources/AgentMeterUI/Platform \
  desktop/Tests/AgentMeterUITests/SettingsFlowTests.swift \
  desktop/Tests/AgentMeterUITests/DiagnosticsTests.swift \
  desktop/Tests/AgentMeterUITests/UserNotificationControllerTests.swift
git commit -m "feat(mac): add device controls and diagnostics"
```

---

### Task 7: Add deterministic appearance, resize, and accessibility snapshots

**Files:**

- Create: `desktop/Tests/AgentMeterSnapshotTests/SnapshotRenderer.swift`
- Create: `desktop/Tests/AgentMeterSnapshotTests/AgentMeterSnapshotTests.swift`
- Create: `desktop/Tests/AgentMeterSnapshotTests/ReferenceImages/`
- Modify: `desktop/Package.swift`
- Modify: `.github/workflows/ci.yml`
- Modify: `docs/development.md`

**Interfaces:**

- Produces reproducible visual regression coverage and a macOS CI gate.

- [ ] **Step 1: Add the snapshot test target**

Add `AgentMeterSnapshotTests` depending on `AgentMeterUI` and `AgentMeterIPC`, with
`resources: [.copy("ReferenceImages")]`. Use XCTest in this target because it hosts AppKit views;
keep the other test targets on Swift Testing.

- [ ] **Step 2: Implement a deterministic AppKit snapshot renderer**

Create an `NSHostingView`, set its frame and appearance explicitly, lay it out, cache display into
an `NSBitmapImageRep`, and compare PNG pixel buffers with a documented small tolerance. Fix locale,
calendar, time zone, font scaling, animation transaction, and `now` in test state. A missing
reference fails with the command needed to record it; CI never creates baselines.

- [ ] **Step 3: Add the required matrix**

Capture Overview, Device, Agents, Display, Diagnostics, and onboarding for:

```text
light and dark
900 x 620 and 1120 x 760
one and four providers
connected, disconnected, stale, unavailable, USB-only, and settings-conflict states
```

Add targeted high-contrast snapshots for Overview and Display. Keep reference PNGs scoped to the
smallest meaningful matrix rather than every state combination.

- [ ] **Step 4: Run locally and inspect changed images**

```bash
AGENTMETER_RECORD_SNAPSHOTS=1 swift test --package-path desktop \
  --filter AgentMeterSnapshotTests
swift test --package-path desktop --filter AgentMeterSnapshotTests
```

Review each baseline visually before staging it.

- [ ] **Step 5: Add a macOS CI job**

Use a pinned supported macOS runner, print `swift --version`, run `swift test --package-path
desktop`, and run `swift build --package-path desktop -c release`. Keep existing Ubuntu host and
firmware jobs unchanged.

- [ ] **Step 6: Run the complete repository matrix**

```bash
swift test --package-path desktop
swift build --package-path desktop -c release
.venv/bin/ruff check .
.venv/bin/ruff format --check .
.venv/bin/pytest
.venv/bin/pio test -d firmware -e native
.venv/bin/pio run -d firmware
```

- [ ] **Step 7: Commit visual verification**

```bash
git add desktop/Tests/AgentMeterSnapshotTests desktop/Package.swift \
  .github/workflows/ci.yml docs/development.md
git commit -m "test(mac): cover themes and responsive layouts"
```

## Plan completion gate

Do not begin release packaging until:

- the app builds and tests with Swift 6 on macOS 14+;
- the menu bar remains functional after closing the main window;
- no Swift target imports CoreBluetooth or invokes provider tools;
- all five sections and onboarding work against the fake and real IPC contract;
- System/Light/Dark, minimum/default/wide, native full screen, and accessibility states pass;
- unavailable telemetry and usage are never presented as zero;
- settings remain pending until a confirmed device revision arrives;
- macOS CI passes alongside existing host and firmware jobs.
