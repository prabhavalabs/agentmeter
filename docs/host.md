# Host bridge

The AgentMeter host converts a local CodexBar dashboard snapshot into the provider-neutral device document and delivers it over encrypted Bluetooth LE or explicit USB serial.

## Data source

Install a recent CodexBar CLI and confirm:

```bash
codexbar --version
codexbar serve --help
```

The upstream [CLI guide](https://github.com/steipete/CodexBar/blob/main/docs/cli.md) documents installation options. Configure each provider inside CodexBar. AgentMeter never asks for provider keys, cookies, or OAuth tokens.

For each refresh, AgentMeter starts `codexbar serve` on `127.0.0.1` with a temporary 256-bit bearer token, fetches one schema-versioned snapshot, and stops the child. It applies a stricter allowlist before encoding the device message.

## Commands

```bash
agentmeter doctor
agentmeter snapshot --pretty
agentmeter send
agentmeter run
agentmeter service install --source .
agentmeter service status
agentmeter service uninstall
```

- `doctor` checks Python, required libraries, CodexBar, and configuration.
- `snapshot` collects and prints one privacy-filtered model without contacting the display.
- `send` collects, sends, waits for ACK, and exits.
- `run` repeats collection and delivery until interrupted.
- `service` installs or manages the isolated macOS launch-at-login bridge.

The first uncached multi-provider snapshot can take about a minute. The configured poll interval begins after each completed attempt, so the interval between device updates also includes collection time.

## Bluetooth behavior

The bridge scans for the AgentMeter service and the configured device-name prefix, connects, subscribes to status notifications, and uses the largest safe write size reported by macOS. A message is successful only when its matching ACK reports status zero.

Transient scan, connection, write, and ACK-timeout errors are retried. The continuous bridge reports the error and continues polling rather than exiting. After one successful connection it keeps the link open for later updates.

## Alerts

The bridge tracks the highest crossed threshold for each provider/window pair during its process lifetime. It emits one short event at a time, prioritizing the highest simultaneous crossing. Staying above a threshold does not repeat an alert; falling below it arms that threshold again.

Restarting the bridge clears this in-memory history and may show one current high-usage alert again. No usage history database is created.

## Background installation

`service install` creates:

- Runtime: `~/Library/Application Support/AgentMeter/venv`
- Logs: `~/Library/Application Support/AgentMeter/logs`
- LaunchAgent: `~/Library/LaunchAgents/com.prabhavalabs.agentmeter.plist`
- Configuration: `~/.config/AgentMeter/config.toml`

The application support directory is independent of the clone or development virtual environment. Reinstall from the repository after updating the code. Uninstall removes the LaunchAgent but keeps configuration, logs, and the isolated runtime for recovery.

## Privacy

The device may receive provider names, quota labels, percentages, reset epochs, small health states, display preferences, and short-lived alert metadata. It does not receive identity, email domain, plan, source, credits, costs, raw errors, bearer tokens, credentials, or upstream responses.

AgentMeter suppresses CodexBar child output because provider tools can include private diagnostics. Inspect any manually collected log before sharing it.

## Troubleshooting

- **CodexBar command missing:** install it from CodexBar preferences and ensure `/opt/homebrew/bin` or `/usr/local/bin` is on `PATH`.
- **Unsupported dashboard schema:** update AgentMeter and CodexBar to compatible releases.
- **Provider unavailable:** enable and verify it in CodexBar, then keep its lowercase ID in the AgentMeter configuration.
- **No display discovered:** confirm Bluetooth is enabled and the screen shows its `AgentMeter-XXXX` waiting state. Hold the top button for five seconds if an old bond must be cleared.
- **First send times out:** approve the macOS Bluetooth prompt, wait for pairing to finish, and retry once.
- **Background bridge appears idle:** run `agentmeter service status`, then inspect `bridge-error.log`. An uncached collection can take about a minute before BLE activity begins.
- **USB serial failure:** stop the background service, confirm the exact ESP32 port with `pio device list`, and ensure no serial monitor owns it.
