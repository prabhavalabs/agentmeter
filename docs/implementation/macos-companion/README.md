# AgentMeter macOS Companion Implementation Roadmap

**Goal:** Deliver the approved native macOS companion, bidirectional ESP32 management protocol,
lightweight bridge control plane, and installable release without weakening the existing usage
display or privacy boundary.

**Authoritative design:** [macOS companion design](../../design/macos-companion.md)

## Plan set

Implement and review these plans in order:

1. [ESP32 management protocol](2026-08-03-device-management-protocol.md)
2. [Bridge control plane](2026-08-03-bridge-control-plane.md)
3. [Native macOS application](2026-08-03-native-macos-app.md)
4. [Distribution and release](2026-08-03-distribution-release.md)

Each plan produces independently testable software. The firmware plan ends with a documented
management protocol and hardware-verifiable device state. The bridge plan provides a complete
headless control plane and fakeable IPC contract. The SwiftUI plan builds against that contract
without requiring hardware. The distribution plan joins the tested parts into an installable,
signed application and completes hardware, performance, and clean-install acceptance.

## Cross-plan contracts

| Contract | Producer | Consumers |
| --- | --- | --- |
| `schemas/device-management-v1.schema.json` | Firmware plan | Bridge and fixtures |
| Management GATT UUIDs and frame types | Firmware plan | Bridge BLE transport |
| IPC schema v1 and sample event stream | Bridge plan | Swift IPC client |
| `AgentMeterCore` models | macOS plan | SwiftUI views and menu bar |
| Unsigned `AgentMeter.app` bundle | macOS/distribution plans | Signing and clean install |

## Design coverage

| Approved requirement | Implementation evidence |
| --- | --- |
| Native macOS window and menu bar | Native app Tasks 3–6 |
| System, Light, and Dark appearance | Native app Tasks 3, 4, 6, and 7 |
| Responsive resize and native full screen | Native app Tasks 4, 5, and 7 |
| One managed Bluetooth connection | Bridge Tasks 2 and 5 |
| Discovery, pair, reconnect, disconnect, forget | Firmware Task 5; bridge Tasks 2 and 5; native app Task 5 |
| Firmware/device/protocol status | Firmware Tasks 3–5; bridge Tasks 2 and 5; native app Task 5 |
| Honest battery, USB, power, and device metrics | Firmware Task 4; bridge Tasks 1–5; native app Tasks 1 and 5 |
| All supported device settings from Mac and touchscreen | Firmware Tasks 1, 2, and 5; bridge Tasks 3 and 5; native app Task 6 |
| Provider usage and health | Bridge Tasks 5–6; native app Tasks 1 and 5 |
| Menu background operation and launch at login | Native app Task 4; distribution Task 4 |
| Local history, alerts, and diagnostics | Bridge Tasks 3–6; native app Tasks 5–6 |
| Custom app icon | Distribution Task 1 |
| Lightweight operation and no process accumulation | All bridge tasks; distribution Task 5 soak gate |
| Privacy, packaging, signing, and public documentation | Bridge Tasks 3–6; distribution Tasks 2–5 |
| No firmware updater, cloud service, or multi-device scope | Global constraints and final release audit |

## Required gates after every plan

```bash
.venv/bin/ruff check .
.venv/bin/ruff format --check .
.venv/bin/pytest
.venv/bin/pio test -d firmware -e native
.venv/bin/pio run -d firmware
```

After the native app exists, also run:

```bash
swift test --package-path desktop
swift build --package-path desktop
```

Do not combine phases into one commit. Keep implementation commits limited to the files and test
cycle named by each task. Never add assistant configuration, co-author attribution, credentials,
private provider responses, or generated local build output.
