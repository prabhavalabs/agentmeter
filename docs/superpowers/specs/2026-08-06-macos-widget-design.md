# AgentMeter macOS Widget Design

**Date:** 2026-08-06

**Status:** Design approved; written specification awaiting review

**Target:** macOS 14 and later

## Summary

AgentMeter will add a native WidgetKit extension with two highly configurable widgets:

1. **Agent Dashboard** presents selected coding agents together.
2. **Agent Focus** presents one coding agent in greater detail.

Both widgets prioritize the provider's longer allowance window, such as weekly or monthly usage, while retaining a shorter session, five-hour, or daily window as secondary context. Large layouts add a GitHub-inspired 30-day heat map by default; users can replace it with a usage trend graph. Small layouts omit history and focus on allowance usage and reset times.

The design uses curated, size-aware layouts plus per-instance module toggles. This provides extensive customization without allowing combinations that become unreadable at widget sizes.

## Goals

- Make the most important allowance and reset information visible without opening AgentMeter.
- Support both multi-agent overview and single-agent detail workflows.
- Let every widget instance independently select agents, metrics, history, density, appearance, and tap destination.
- Display all reported provider windows honestly, including model-specific limits and missing values.
- Reuse the current provider and 30-day local-history infrastructure.
- Keep credentials, prompts, source code, account identity, and billing details outside widget storage.
- Preserve the existing Swift package boundaries and test workflows.

## Non-goals

- The widget will not collect provider data, open Bluetooth, or connect to the AgentMeter bridge itself.
- The heat map will not claim to show tokens, prompts, coding time, or commits because AgentMeter does not collect those values.
- The first release will not provide drag-and-drop, pixel-level freeform layout editing.
- The widget will not provide scrolling, text input, or arbitrary interactive controls.
- The widget will not reset or alter provider quotas.

## Product Direction

The visual hierarchy is inspired by compact health and nutrition widgets:

- Selected providers form the primary list.
- Dual concentric rings communicate two allowance windows at a glance.
- Reset times sit directly beside the usage values they qualify.
- The history visualization occupies a separate region in larger layouts.
- Provider colors identify series and rings, while the surface remains compatible with macOS widget rendering and Light/Dark appearance.

The approved default is a **30-day daily-consumption heat map**. A trend graph remains available as a per-widget option.

## Widget Families

### Agent Dashboard

The dashboard shows an ordered selection of providers.

| Family | Providers | Default content |
| --- | ---: | --- |
| Small | Up to 2 | Long-term usage, reset time, compact status |
| Medium | Up to 4 | Dual rings, long- and short-window resets |
| Large | Up to 5 | Provider list, dual rings, 30-day heat map |
| Extra large | Up to 8 | Expanded provider list, history, model-specific windows |

If a configuration contains more providers than the current family can display, the widget preserves the full selection, renders the allowed prefix in user-defined order, and displays `+N` for the remainder. Resizing the widget exposes the preserved providers again.

### Agent Focus

The focus widget shows one provider.

| Family | Default content |
| --- | --- |
| Small | Dual rings and both reset summaries |
| Medium | All reported windows plus compact history |
| Large | Detailed allowances, heat map or trend, status and freshness |
| Extra large | Same content with expanded labels and history resolution |

The Focus widget allows the user to explicitly select the two windows assigned to the outer and inner rings. Dashboard widgets use automatic window selection so one configuration can support heterogeneous providers.

## Usage Rings and Window Selection

The outer ring is visually dominant and represents the longer meaningful allowance. The inner ring represents the shorter allowance.

Automatic Dashboard selection follows this order:

1. Prefer an exact monthly or billing-cycle window for the outer ring.
2. Otherwise prefer an exact weekly window.
3. Otherwise prefer a non-session window whose normalized kind or label identifies a monthly, billing, or weekly limit.
4. Otherwise use the first reported non-session window.
5. If only one window exists, use it as the outer ring and omit the inner ring.
6. For the inner ring, prefer an exact `session` window, then the first remaining daily or short-window value, then the first remaining reported window.

Model-specific weekly windows do not displace an exact provider-wide weekly window. They appear as additional rows in layouts with room. A Focus configuration can deliberately place a model-specific window in either ring.

The displayed number can be configured as **used percent** or **remaining percent**. Internally, snapshots continue to store only the normalized used percentage. Remaining percentage is derived as `100 - used` at render time. Unknown percentages display **Not reported** and never become zero.

## Per-instance Customization

Both widgets use `AppIntentConfiguration`. Dynamic provider and window choices are backed by entities read from the shared snapshot.

Each instance stores the relevant subset of these parameters:

- Widget mode: Dashboard or Focus, represented by separate widget kinds in one `WidgetBundle`.
- Selected providers and their order.
- Focus outer and inner windows.
- Percentage display: used or remaining.
- Visible modules: usage, relative reset countdown, absolute reset date, provider status, freshness, heat map, and trend graph.
- History style: heat map, trend, or none.
- History range: heat maps support 7 or 30 days; trends support 7 days, 30 days, or the current cycle. Heat-map default is 30 days.
- Heat-map scope: one provider or combined selected providers.
- Trend window: outer, inner, or a specific Focus window.
- Layout preset: rings, compact rows, or analytics.
- Density: compact or comfortable.
- Theme: system adaptive, midnight, neutral, or provider-tinted.
- Tap destination: Overview, Agents, or the configured provider detail.

The configuration resolver applies family-specific rules after reading the intent. Unsupported modules are hidden in a deterministic order: history first, then secondary status metadata, then additional providers. Allowance usage and the primary reset time are never removed while valid data exists.

## Architecture

### Xcode host and extension

The repository will add an Xcode project that contains:

- A macOS application target for AgentMeter.
- A WidgetKit extension target.
- The existing local Swift package products as dependencies.

The Xcode app target references the existing `AgentMeterApp` entry-point sources and depends on `AgentMeterCore`, `AgentMeterIPC`, and `AgentMeterUI`. The Swift package remains the source of truth for reusable code and continues to support `swift build` and `swift test`.

The WidgetKit extension contains only widget entry points, App Intents, timeline providers, views, and thin snapshot-loading adapters. Snapshot value types, formatting, window selection, history aggregation value types, configuration resolution, and deep-link definitions live in a reusable package target so they can be tested without launching WidgetKit.

### Shared container

The app and extension use the provisioned App Group:

`group.com.prabhavalabs.agentmeter.shared`

Bundle and widget identifiers are:

- App: `com.prabhavalabs.agentmeter`
- Extension: `com.prabhavalabs.agentmeter.widget`
- Dashboard kind: `com.prabhavalabs.agentmeter.dashboard`
- Focus kind: `com.prabhavalabs.agentmeter.focus`

The app atomically writes `widget-snapshot-v1.json` inside the shared group container. The file uses owner-only permissions where the file system honors POSIX modes. The writer encodes to a temporary sibling, synchronizes and closes it, then replaces the current snapshot. The extension never writes provider data.

Apple documents App Groups as the supported way for a host app and extension to share files and preferences: [Configuring App Groups](https://developer.apple.com/documentation/xcode/configuring-app-groups).

### Runtime data flow

1. The existing bridge collects and normalizes provider usage.
2. `AppModel` receives the current provider state through the existing IPC event stream.
3. A new widget snapshot coordinator requests the bounded history summary when current usage changes or the local calendar day changes.
4. The coordinator combines current provider state and history summary into the versioned shared snapshot.
5. After a successful atomic replacement, the app calls `WidgetCenter` to reload the affected widget timelines.
6. A timeline provider reads the last complete snapshot, resolves the instance's App Intent configuration, and produces size-independent view data.
7. The widget renders a family-specific view and opens AgentMeter through a deep link when clicked.

The widget does not access the Unix socket, SQLite history database, CodexBar, Bluetooth, or the bundled Python bridge.

## Shared Snapshot Contract

The version-one snapshot contains:

- Schema version and generation epoch.
- Configured provider-collection interval in seconds for freshness evaluation.
- Provider ID, display name, normalized status, and update epoch.
- Each provider window's kind, label, used percentage, and reset epoch.
- Thirty calendar days of daily allowance-consumption summaries per provider/window.
- Up to 30 daily latest-percentage trend samples per history-enabled provider/window; 7-day and current-cycle views are clipped from this bounded series.
- An explicit history start date so missing history can be distinguished from zero consumption.

The payload is bounded to 8 providers and 8 current windows per provider. History is bounded to the first 4 windows selected by the same priority rules used for display, with at most 30 consumption cells and 30 trend samples per history-enabled window. Encoding fails closed if the complete file would exceed 256 KiB; the previous valid snapshot remains in place and the app records a sanitized diagnostic event. A Focus widget may place any current window in a ring, but a window beyond the history-enabled set displays **History unavailable for this window** instead of requesting unbounded data.

No field may contain account identifiers, email addresses, API keys, OAuth tokens, cookies, prompts, source code, file paths, repository names, raw provider responses, or billing details.

Unknown future schema versions produce an unsupported-data state rather than partial decoding. Older valid snapshot versions may receive explicit migrations in the shared package.

## Heat-map Semantics

Each heat-map cell represents **percentage points of allowance consumed during one local calendar day** for a selected long-term window. It does not represent total token count or time spent coding.

The host history layer adds a bounded summary operation that accepts a 30-day boundary and an IANA time-zone identifier. For each provider/window/day it:

1. Reads the last sample before the day as the baseline when available.
2. Walks samples in chronological order.
3. Adds positive percentage changes.
4. Treats a percentage drop or changed reset epoch as a quota reset and does not add the drop.
5. Continues accumulating positive changes after the reset.
6. Emits `nil` when no usable samples exist, preserving a visual gap.

Day boundaries use the Mac's current IANA time zone so daylight-saving transitions are handled by calendar dates rather than fixed 86,400-second offsets.

For a single-provider heat map, fixed intensity bands are used so days remain comparable: no detected increase, 1–5, 6–15, 16–30, and more than 30 percentage points. A missing value uses a distinct empty-cell appearance.

For a combined heat map, the cell uses the average available consumption band across selected providers. Providers with missing values are excluded from that day's denominator; if every provider is missing, the cell is a gap. This prevents adding providers from automatically making every cell darker.

Trend graphs retain the existing meaning: the latest reported used percentage in each requested time bucket for one selected quota window.

## Timeline and Refresh Behavior

Widgets are snapshot-based and do not assume continuous execution. Apple recommends timelines plus targeted reload requests and notes that reloads are budgeted: [Keeping a Widget Up to Date](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date).

The timeline provider creates an entry for the current snapshot and entries at relevant reset boundaries within the next 24 hours. Relative reset labels use WidgetKit-supported dynamic date rendering so countdown text advances without frequent timeline reloads.

The host app requests a timeline reload only after a materially changed snapshot is committed. Repeated identical bridge updates do not request reloads. A local day change also triggers one summary refresh while AgentMeter is running.

If a reset time passes without a fresh provider snapshot, the widget changes the reset label to **Refresh pending**. It does not infer that usage returned to zero.

## Empty, Stale, and Error States

- No shared snapshot: **Open AgentMeter to configure this widget.**
- AgentMeter has not completed setup: show setup guidance and an app deep link.
- Selected provider is absent: preserve the selection and show **Agent unavailable**.
- Provider reports an error or stale status: retain last reported values, show status, and display freshness.
- Used percentage is missing: **Not reported**.
- Reset epoch is missing: **Reset time unavailable**.
- History is incomplete: render gaps rather than zeros.
- Snapshot is older than twice the configured collection interval, or 15 minutes when the interval is unavailable: mark it stale.
- Snapshot schema is newer than supported: **Update AgentMeter to view this widget.**
- Snapshot read or decode failure: keep the last entry already supplied to WidgetKit when possible and expose a sanitized unavailable state on the next provider request.

## Deep Links

Widget interactions use these routes:

- `agentmeter://overview`
- `agentmeter://agents`
- `agentmeter://agent/<percent-encoded-provider-id>`

Provider IDs must pass the existing normalized provider-ID validation before routing. Unknown routes open Overview. The app activates its main window, selects the appropriate section, and opens provider details when applicable.

## Privacy and Security

- Usage values and provider names are marked privacy-sensitive for system redaction where supported.
- Placeholder previews use fictional data.
- The shared snapshot follows the same allowlist-only privacy boundary as existing device and history payloads.
- The extension has no network, Bluetooth, keychain, or provider-credential responsibility.
- App Group access is granted only to the app and widget targets.
- Diagnostics may report snapshot version, byte size, age, and error category, but never snapshot contents.
- The widget displays last-known state; it never takes quota-affecting or destructive actions.

## Packaging and Distribution

The widget-enabled build requires consistent Apple Developer signing for the app target, extension target, App Group entitlement, and embedded extension. Local development uses Xcode-managed development signing. Managed releases use the project's Developer ID distribution path and registered App Group.

The current ad-hoc community DMG has no signing team identity and therefore cannot rely on the provisioned shared App Group. It remains app-only in the first widget release. Adding widgets to that distribution is deferred until an entitlement-safe shared-container design is proven on every supported macOS version; the widget implementation must not weaken file permissions or expose a local network service to bypass signing.

The release packaging script will build the Xcode app and embedded extension for widget-enabled managed releases, then embed the existing Python bridge and resources before final signing. `swift build` and `swift test` remain valid for the package modules.

## Testing Strategy

### Unit tests

- Snapshot round-trip, schema rejection, bounds, atomic replacement, and previous-snapshot preservation.
- Allowlist verification proving prohibited identity and content fields cannot be encoded.
- Automatic and explicit outer/inner window selection.
- Used-versus-remaining formatting and unknown values.
- Daily positive-delta aggregation across resets, same-day resets, missing baselines, gaps, DST boundaries, and time-zone changes.
- Combined heat-map averaging and fixed intensity bands.
- Configuration resolution for every widget family and overflow provider count.
- Stale thresholds, passed resets, and deterministic timeline dates using an injected clock.
- Deep-link validation and routing.

### View and integration tests

- SwiftUI previews for every supported family, theme, density, and widget kind.
- Long provider names, eight providers, one-window providers, model-specific windows, unknown percentages, stale data, and absent history.
- Multiple simultaneous widget instances with independent App Intent configurations.
- Snapshot update followed by targeted WidgetCenter reload.
- Main-window closure while the menu-bar app remains running.
- App restart, bridge interruption, provider removal, system time-zone change, and reset-boundary behavior.

### Packaging verification

- Xcode build of the app and WidgetKit extension on macOS 14+ SDKs.
- The extension is embedded in the correct PlugIns directory.
- App, extension, provisioning, and App Group entitlements agree.
- Deep links activate the installed application.
- Existing `swift test --package-path desktop` and Python host test suites pass.
- The managed packaged app appears in the macOS widget gallery and supports adding, editing, resizing, removing, and re-adding both widget kinds.

## Acceptance Criteria

1. A user can add Dashboard and Focus widgets from the macOS widget gallery.
2. Each widget instance independently selects providers and presentation settings.
3. Weekly or monthly usage is visually primary when the provider reports it.
4. A shorter session, five-hour, or daily window remains visible as an inner ring or secondary row.
5. Large layouts show the 30-day heat map by default and can switch to a trend graph.
6. Small layouts remain legible without a history graph.
7. Reset countdowns and absolute reset times are accurate, and passed resets never imply an unobserved zero value.
8. Missing or stale data is explicit and never fabricated.
9. The widget continues showing the last valid snapshot when the main window is closed and AgentMeter remains in the menu bar.
10. Shared widget data contains only normalized provider usage and bounded history fields.
11. The managed release passes extension embedding, signing, entitlement, and regression-test verification.

## References

- [Creating a Widget Extension](https://developer.apple.com/documentation/widgetkit/creating-a-widget-extension)
- [AppIntentConfiguration](https://developer.apple.com/documentation/widgetkit/appintentconfiguration)
- [Configuring App Groups](https://developer.apple.com/documentation/xcode/configuring-app-groups)
- [Developing a WidgetKit Strategy](https://developer.apple.com/documentation/widgetkit/developing-a-widgetkit-strategy)
- Existing AgentMeter provider model: `desktop/Sources/AgentMeterCore/Models/ProviderUsage.swift`
- Existing AgentMeter history model: `desktop/Sources/AgentMeterCore/Models/UsageHistory.swift`
- Existing bounded history store: `host/src/agentmeter_host/control/history.py`
