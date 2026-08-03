# macOS companion app

AgentMeter includes a native SwiftUI companion for macOS 14 or later. It keeps one small menu-bar
status item available while the main window is closed and controls one bundled background bridge
over a private Unix socket. The signed release is self-contained and does not require Python, the
source repository, or Xcode. The app never opens a competing Bluetooth connection.

![Agent visibility in light mode](assets/screenshots/macos-agents-light.png)

## What the app manages

- Bridge and ESP32 connection status, discovery, reconnect, disconnect, identify, and forget
- USB power, battery presence, supported voltage, display state, uptime, and device memory
- Codex, Claude, Gemini, Cursor, and future provider health and current usage windows
- Agent visibility and display order
- Always-on mode, full-view rotation, rotation interval, brightness, dimming, and screen-off time
- Firmware and protocol information, bounded history controls, and sanitized diagnostics
- Local usage trends for the last 24 hours, 7 days, 30 days, and the current usage cycle
- First-run setup, sleep/wake recovery, and optional notifications

Firmware installation and updates are intentionally outside the app. Unsupported measurements remain **Unavailable** rather than being estimated.

## Window and appearance

The default window is 1120 × 760 points with a 900 × 620 point content minimum. It can be resized freely above that minimum and supports the normal macOS full-screen control. Adaptive grids reflow before labels or controls are compressed, and long pages scroll.

Choose **AgentMeter → Settings** to select:

- **System** — follows the macOS appearance
- **Light** — always uses the light interface
- **Dark** — always uses the dark interface

The same preference applies to the main window, menu-bar panel, and settings window. Statuses pair colour with text and symbols.

## Local usage history

The Overview chart keeps usage history on the Mac and never uploads it. Choose the range that best
matches what you want to inspect:

- **24H** shows up to 24 hourly points.
- **7D** shows up to seven daily points.
- **30D** shows up to 30 daily points.
- **Cycle** starts at the latest observed usage reset and adapts the number of points to the
  available cycle history.

Missing samples remain gaps rather than being presented as zero usage. Provider details separate
the current session from the overall cycle and show the reset time for each window. Model-specific
rows are included when the local provider source reports them. If a provider names a model window
without reporting its percentage, AgentMeter displays **Not reported** instead of inventing a zero
value.

## Install a release

Move the signed and notarized app to `/Applications`, then open it:

```bash
ditto AgentMeter.app /Applications/AgentMeter.app
open /Applications/AgentMeter.app
```

The first-run assistant prepares the private configuration, requests Bluetooth access only when
you scan, connects to the selected display, verifies encrypted management, and loads provider
usage. The embedded helper remains available when the main window is closed.

If the older `com.prabhavalabs.agentmeter` LaunchAgent is present, the app copies its configuration,
registers the bundled bridge, stops the older process, and archives the legacy plist under
`~/Library/Application Support/AgentMeter/Migration`. History remains in place. Migration is
idempotent and never intentionally runs two Bluetooth bridges after setup completes.

## Build for local development

Install the development and packaging dependencies, then sign with an installed Apple Development
identity so ServiceManagement can authorize the helper:

```bash
make setup
CODE_SIGN_IDENTITY="Apple Development: Your Name (TEAMID)" make desktop-app
ditto desktop/dist/AgentMeter.app /Applications/AgentMeter.app
open /Applications/AgentMeter.app
```

The bundle is written to `desktop/dist/AgentMeter.app`. If no identity is supplied, the script uses
an ad-hoc signature suitable for build and interface checks, but macOS does not authorize its
embedded background item. Use the synthetic bridge workflow below for ad-hoc UI development.

**Launch AgentMeter at login** controls whether the graphical app and menu item open after sign-in.
The bundled bridge is a separate lightweight background item because it maintains collection and
Bluetooth synchronization while the window is closed. **Quit AgentMeter** stops both intentionally.

## Development with synthetic data

Run the deterministic fake bridge from [Development](development.md), then start the Swift executable with `AGENTMETER_IPC_PATH` set to its socket. Available scenarios cover connected USB power, disconnected, pairing, provider unavailable, legacy firmware, and a settings revision conflict.

```bash
swift test --package-path desktop
swift build --package-path desktop
```

No device, provider account, credentials, or Bluetooth permission is required for these tests.

## Packaging and signing

`desktop/scripts/package-app.sh` performs a release Swift build, packages one Python runtime as a
one-folder helper, creates every required `.icns` size from the 1024-pixel source, assembles the
modern ServiceManagement layout, signs it, and validates the complete code signature and property
list.

For a Developer ID build, provide the identity:

```bash
CODE_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
  desktop/scripts/package-app.sh
```

Developer ID credentials, notarization submission, and stapling are release-owner operations. An
ad-hoc signature is sufficient for synthetic-data interface development, but it cannot authorize
the managed background bridge and is not suitable for public distribution.

After packaging with a Developer ID Application identity, notarize and create the release archive:

```bash
NOTARY_KEYCHAIN_PROFILE="AgentMeter Notary" desktop/scripts/notarize-app.sh
```

The keychain profile must already have been created with `xcrun notarytool store-credentials`.
The script submits a temporary archive, staples and validates the app, verifies Gatekeeper, and
writes the distributable zip to `desktop/dist`.

## Troubleshooting

- **Bridge unavailable:** open **AgentMeter → Settings**. If approval is required, allow AgentMeter under **System Settings → General → Login Items & Extensions**, then choose **Try Again**.
- **Device disconnected:** open **Device**, scan, and select the nearby `AgentMeter-XXXX`. This is different from bridge availability.
- **Provider unavailable:** verify the provider in CodexBar, then refresh usage. The last valid value may appear as stale during a transient failure.
- **Launch at login fails:** move the signed app to `/Applications`, reopen it, and retry. macOS also lists it under **System Settings → General → Login Items & Extensions**.
- **Settings waiting for device:** reconnect the ESP32. Device-side settings remain authoritative and are never overwritten silently after a revision conflict.
