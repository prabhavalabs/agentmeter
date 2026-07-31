# Configuration

AgentMeter uses a small TOML configuration file on the host. Run `agentmeter doctor` to print the platform-specific path, then copy `config.example.toml` there.

## General settings

```toml
[general]
poll_interval_seconds = 60
providers = ["codex", "claude", "gemini"]
```

- `poll_interval_seconds` controls how often the local source is checked. The minimum supported value will be 30 seconds.
- `providers` controls display order and is limited to four entries.

## Display settings

```toml
[display]
brightness_percent = 55
dim_after_seconds = 300
screen_off_after_seconds = 1800
alert_thresholds = [75, 90]
sound_enabled = false
```

Brightness is deliberately moderate to reduce AMOLED wear. Alerts pair color with text and an icon; sound is off by default.

## Transport settings

```toml
[transport]
preferred = "ble"
device_name = "AgentMeter"
```

Bluetooth LE is the normal connection. USB serial will remain available as a diagnostic and recovery transport.

## Secrets

AgentMeter configuration must not contain provider API keys, session cookies, or OAuth tokens. Provider authentication belongs to the local data source. Local configuration files are excluded from version control.

