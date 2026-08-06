# Development

## Working areas

- `host/` contains the Python bridge, transports, alert engine, service manager, and tests.
- `desktop/` contains the native Swift package and macOS application.
- `firmware/` contains the PlatformIO application, fixed-size model, protocol, UI, and board support.
- `schemas/` defines the shared JSON contract.
- `fixtures/` contains safe synthetic messages used by both sides.
- `docs/` explains decisions and user workflows.

Keep provider-specific authentication and parsing on the host. Keep the firmware provider-neutral and avoid dynamic allocation in data models.

## Host workflow

```bash
make setup
make lint
make host-test
```

Ruff checks formatting and static rules. Pytest uses fake CodexBar processes and transport backends, so automated tests need no provider accounts, Bluetooth adapter, or attached hardware.

Claude CLI integration is tested through a fake executable at the process boundary. Keep `agentmeter-claude-probe` limited to direct execution without a shell, persistent state, or user customizations. Live verification should confirm that repeated AgentMeter snapshots do not increase the number of Claude plugin or MCP processes.

Useful manual commands are:

```bash
.venv/bin/agentmeter snapshot --pretty
.venv/bin/agentmeter send
.venv/bin/agentmeter run
.venv/bin/agentmeter ipc-path
```

Do not run an interactive bridge and the background service at the same time; they would compete for one BLE connection.

The fake server supports `connected-usb`, `disconnected`, `pairing`, `provider-unavailable`, `legacy`, and `settings-conflict`. It reads only synthetic checked-in fixtures and does not import provider collectors or Bluetooth code. Use it for SwiftUI work without an attached device or signed-in coding-agent accounts.

## Native macOS workflow

The desktop package targets macOS 14 or later and uses Swift 6, SwiftUI, Network, Observation, and ServiceManagement. It has no third-party Swift dependencies.

```bash
make desktop-test
make desktop-build
make desktop-widget-build
make desktop-widget-verify
make desktop-app
open desktop/dist/AgentMeter.app
```

The committed Xcode project is generated deterministically from `desktop/project.yml`. Regeneration
requires XcodeGen 2.45.4 or newer:

```bash
make desktop-project
git diff --exit-code -- desktop/AgentMeter.xcodeproj
```

`desktop-widget-build` uses the committed project with `CODE_SIGNING_ALLOWED=NO`; it proves the
extension compiles and is embedded but does not prove App Group access or gallery registration.
`desktop-app` creates the existing self-contained, app-only community bundle with the production
icon and bundled bridge. The community build can use `AGENTMETER_IPC_PATH` for interface work, but
macOS will not authorize its embedded launch agent and it contains no widget.

Managed packaging is separate. Set `AGENTMETER_DISTRIBUTION_MODE=managed`, provide
`AGENTMETER_DEVELOPMENT_TEAM`, an installed identity in `CODE_SIGN_IDENTITY`, and exact local
installed-profile UUIDs in `AGENTMETER_APP_PROVISIONING_PROFILE` and
`AGENTMETER_WIDGET_PROVISIONING_PROFILE`. The profiles must target
`com.prabhavalabs.agentmeter.desktop` and `com.prabhavalabs.agentmeter.desktop.widget` and grant
`group.com.prabhavalabs.agentmeter.shared`. The script builds signed Release Xcode output, copies
it before adding the bridge, preserves the extension signature, and re-signs only the outer app
with explicit app entitlements—never `--deep`.

To develop without the bridge service or hardware, create a private fake-server runtime and point the Swift executable to it:

```bash
AGENTMETER_FAKE_RUNTIME="${TMPDIR:-/tmp/}agentmeter-$(id -u)"
mkdir -p "$AGENTMETER_FAKE_RUNTIME"
chmod 700 "$AGENTMETER_FAKE_RUNTIME"

.venv/bin/agentmeter fake-server --scenario connected-usb \
  --ipc-path "$AGENTMETER_FAKE_RUNTIME/development.sock"
```

In a second terminal:

```bash
AGENTMETER_IPC_PATH="$AGENTMETER_FAKE_RUNTIME/development.sock" \
  swift run --package-path desktop AgentMeter
```

Do not point the fake server at the live bridge socket. The checked-in screenshots use only synthetic fixtures.

## Firmware workflow

```bash
make firmware-test
make firmware
.venv/bin/pio device list
.venv/bin/pio run -d firmware -e waveshare_amoled_216 \
  --target upload --upload-port /dev/cu.usbmodemXXXX
.venv/bin/pio device monitor --port /dev/cu.usbmodemXXXX --baud 115200
```

The native test environment exercises JSON parsing, rollover-safe time calculations, reassembly, ACK encoding, and UI text formatting without hardware. The ESP32 build remains the authority for Arduino, NimBLE, and LVGL compatibility.

Board pins and peripheral initialization live under `firmware/src/boards/`. New boards should implement the small board interface without adding conditionals throughout the UI.

## Complete local verification

```bash
make lint
make test
make firmware
make desktop-test
make desktop-widget-build
make desktop-widget-verify
make desktop-app
desktop/scripts/verify-widget-bundle.sh --community desktop/dist/AgentMeter.app
```

`make test` runs both host and native firmware tests. Hardware-dependent changes must additionally be flashed to the exact board and tested over the affected transport.

## Contract changes

Any device-message change must update:

1. The JSON Schema under `schemas/`
2. At least one safe fixture under `fixtures/`
3. Host validation or normalization tests
4. Firmware parser tests
5. `docs/protocol.md`

Desktop IPC changes must also update `schemas/desktop-ipc-v1.schema.json`, every affected `desktop-ipc-*.json` fixture, Python protocol tests, and Swift decoding tests.

Breaking changes require a new `schemaVersion`. Never add raw CodexBar responses as fixtures. Synthetic data should explicitly prove that identity, billing, status, and error fields are removed.

## UI changes

Keep important states readable without relying on color alone. Test one-, two-, three-, and four-provider layouts, unknown percentages, the longest permitted labels, three detail windows, warning and critical progress, stale content, and a blank screen wake-up.

AMOLED changes must preserve dimming, screen-off, and pixel shifting. Avoid large static bright areas.

## Documentation and screenshots

Keep contributor-facing explanations in `docs/` and link the canonical guide rather than copying
commands into several files. When behavior changes, update its user guide in the same pull request.

Store photographed hardware under `docs/assets/photos/` and application captures under
`docs/assets/screenshots/`. Before adding an image:

1. Crop it to the behavior or hardware being explained.
2. Remove location, camera, account, repository, notification, and other private metadata or content.
3. Resize it to a practical web dimension and optimize it without making interface text unreadable.
4. Give it a stable, descriptive, lowercase filename rather than a timestamp or camera sequence.
5. Add meaningful alternative text that describes the information shown.
6. Prefer one strong image over several near-duplicates.

The current project photos are bounded JPEG copies with location metadata removed. Keep original
full-resolution media outside the repository.

## Pull requests

Keep changes focused and explain their effect on users or contributors. Hardware changes should state the exact board revision, serial port type, firmware build result, and physical acceptance performed. Inspect logs before attaching them and never publish credentials or personal provider data.

See [CONTRIBUTING.md](../CONTRIBUTING.md) for the checklist.
