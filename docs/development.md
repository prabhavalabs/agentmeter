# Development

## Working areas

- `host/` contains the Python bridge, transports, alert engine, service manager, and tests.
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

Useful manual commands are:

```bash
.venv/bin/agentmeter snapshot --pretty
.venv/bin/agentmeter send
.venv/bin/agentmeter run
```

Do not run an interactive bridge and the background service at the same time; they would compete for one BLE connection.

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
```

`make test` runs both host and native firmware tests. Hardware-dependent changes must additionally be flashed to the exact board and tested over the affected transport.

## Contract changes

Any device-message change must update:

1. The JSON Schema under `schemas/`
2. At least one safe fixture under `fixtures/`
3. Host validation or normalization tests
4. Firmware parser tests
5. `docs/protocol.md`

Breaking changes require a new `schemaVersion`. Never add raw CodexBar responses as fixtures. Synthetic data should explicitly prove that identity, billing, status, and error fields are removed.

## UI changes

Keep important states readable without relying on color alone. Test one-, two-, three-, and four-provider layouts, unknown percentages, the longest permitted labels, three detail windows, warning and critical progress, stale content, and a blank screen wake-up.

AMOLED changes must preserve dimming, screen-off, and pixel shifting. Avoid large static bright areas.

## Pull requests

Keep changes focused and explain their effect on users or contributors. Hardware changes should state the exact board revision, serial port type, firmware build result, and physical acceptance performed. Inspect logs before attaching them and never publish credentials or personal provider data.

See [CONTRIBUTING.md](../CONTRIBUTING.md) for the checklist.
