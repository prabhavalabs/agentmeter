# Configuration

AgentMeter reads `~/.config/AgentMeter/config.toml` by default. Run `agentmeter doctor` to print the exact path. Local configuration files are excluded from version control.

The TOML file is the readable source-install baseline. On first desktop-control launch, AgentMeter seeds a private `control-state-v1.json` overlay in Application Support. Later provider, interval, selected-device, and reconnect changes are written atomically to that overlay with mode `0600`. A corrupt overlay is reported and never silently replaced.

## General settings

```toml
[general]
poll_interval_seconds = 300
providers = ["codex", "claude", "gemini", "cursor"]
```

- `poll_interval_seconds` is the delay between completed bridge sends. It must be at least 30 seconds. The recommended five-minute default keeps CPU and network activity low; use 60 seconds only when fresher quota values matter more than efficiency. Provider collection itself can add time between visible updates, while countdowns and full-view rotation continue locally on the display.
- `providers` sets the available provider set and order and accepts one to eight unique IDs using lowercase letters, numbers, `_`, or `-`.
- A configured provider missing from CodexBar appears as unavailable instead of being silently removed.

Use the display's gear menu or the macOS app to hide and order available providers without editing this file or restarting the bridge. This separation keeps the host responsible for collection and the display responsible for presentation. The ESP32 remains authoritative for display settings and confirms each revision before the app shows it as synced.

### Cursor

Cursor usage is collected by CodexBar's [Cursor provider](https://github.com/steipete/CodexBar/blob/main/docs/cursor.md) from the signed-in Cursor browser or desktop-app session. Enable and verify the provider before starting AgentMeter:

```bash
codexbar config enable --provider cursor
codexbar --provider cursor --format json --pretty
```

The resulting AgentMeter card shows Cursor's available plan-usage windows and billing-cycle reset. Account identity, plan details, billing amounts, and raw dashboard responses remain on the Mac.

## Display settings

```toml
[display]
brightness_percent = 55
dim_after_seconds = 300
screen_off_after_seconds = 1800
alert_thresholds = [75, 90]
sound_enabled = false
```

- `brightness_percent` accepts 1–100. Moderate brightness reduces AMOLED wear.
- `dim_after_seconds` must be at least 30.
- `screen_off_after_seconds` must be greater than or equal to the dim delay and no more than 86,400.
- `alert_thresholds` contains one to three strictly increasing, unique percentages. A window generates an alert only when it crosses upward; it can alert again after falling below the threshold, normally after reset.
- `sound_enabled` requests a short device sound for events. The first board version keeps this off because its ES8311 audio path is not yet enabled; visual alerts work now.

Touch, button input, and alerts wake a dimmed or blank screen. The UI also shifts its content by one pixel each minute while lit. The gear menu provides an always-on override that is stored on the ESP32 and bypasses both host-provided idle timers.

## Bluetooth transport

```toml
[transport]
preferred = "ble"
device_name = "AgentMeter"
```

`device_name` is a discovery prefix. The firmware appends four address characters, producing a name such as `AgentMeter-7404`. The bridge scans only for this name and the private AgentMeter service.

Bluetooth is bonded and encrypted. Hold the device's top button for five seconds to remove its saved bonds when moving it to another computer. Remove the corresponding AgentMeter entry from macOS Bluetooth settings if a completely clean pairing is required.

## USB serial transport

```toml
[transport]
preferred = "serial"
device_name = "AgentMeter"
serial_port = "/dev/cu.usbmodem21201"
```

An explicit `serial_port` is required for serial mode so AgentMeter never guesses and writes to an unrelated device. Use `pio device list` to identify the ESP32 `USB JTAG/serial debug unit`.

## Secrets and privacy

Do not put provider API keys, session cookies, OAuth tokens, or account identifiers in this file. Authentication remains inside the local coding-agent tools and CodexBar. AgentMeter generates a temporary bearer token only for its loopback CodexBar child process and never stores it.
