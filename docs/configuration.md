# Configuration

AgentMeter reads `~/.config/AgentMeter/config.toml` by default. Run `agentmeter doctor` to print the exact path. Local configuration files are excluded from version control.

## General settings

```toml
[general]
poll_interval_seconds = 60
providers = ["codex", "claude", "gemini"]
```

- `poll_interval_seconds` is the delay between completed bridge sends and also the CodexBar refresh interval. It must be at least 30 seconds. Provider collection itself can add time between visible updates.
- `providers` sets the available provider set and order and accepts one to eight unique IDs using lowercase letters, numbers, `_`, or `-`.
- A configured provider missing from CodexBar appears as unavailable instead of being silently removed.

Use the display's gear menu to hide an available provider from Home without editing this file or restarting the bridge. This separation keeps the host responsible for collection and the display responsible for presentation.

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
