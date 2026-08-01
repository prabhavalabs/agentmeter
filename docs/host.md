# Host data source

The AgentMeter host turns a local CodexBar dashboard snapshot into the small,
provider-neutral document used by the display. This milestone is intentionally
one-shot: `agentmeter snapshot` proves collection and normalization before the
Bluetooth service is added.

## Install CodexBar

AgentMeter requires a recent CodexBar CLI with the `serve` command and dashboard
API. On macOS, install CodexBar and then choose **Preferences → Advanced → Install
CLI**. Confirm that the command is visible:

```bash
codexbar --version
codexbar serve --help
```

The upstream [CLI guide](https://github.com/steipete/CodexBar/blob/main/docs/cli.md)
also documents Homebrew, release archive, and manual installation options.

Configure and verify the providers inside CodexBar before using AgentMeter. The
host does not accept provider keys, cookies, or OAuth tokens in its own TOML file.

## Configure AgentMeter

Run the environment check to find the configuration location:

```bash
.venv/bin/agentmeter doctor
```

Copy `config.example.toml` to the printed path, then choose the providers and
display preferences. Run `doctor` again; all five checks should report `OK`.

## Collect one snapshot

```bash
.venv/bin/agentmeter snapshot --pretty
```

The command starts a temporary CodexBar server, waits until it is ready, fetches
one snapshot, stops the server, and prints device protocol version 1. Omit
`--pretty` to see the exact compact form that will be sent to the ESP32.
An uncached multi-provider collection can take up to 60 seconds; the host keeps a
five-second margin so CodexBar can return its own bounded error response.

Expected top-level fields are `schemaVersion`, `messageId`, `generatedAtEpoch`,
`staleAfterSeconds`, `providers`, `display`, and `event`. A configured provider
that is absent from CodexBar is reported as `unavailable`; missing usage remains
`null` rather than becoming zero.

## Security model

AgentMeter always launches `codexbar serve` on `127.0.0.1` and a temporary local
port. It creates a new 256-bit bearer token for every process and passes it in the
`CODEXBAR_DASHBOARD_TOKEN` environment variable. The token is not written to the
configuration file or placed in the process arguments.

Normalization is an allowlist. The device document keeps provider names, short
status values, window labels, usage percentages, and reset times. It discards
identity, email domain, plan, source, credits, costs, display hints, and raw error
details. The encoded device document is capped at 4096 bytes.

See the upstream
[dashboard API guide](https://github.com/steipete/CodexBar/blob/main/docs/dashboard-api.md)
for the source contract and loopback server behavior.

## Troubleshooting

- `CodexBar command was not found`: install the CLI from CodexBar preferences and
  ensure `codexbar` is on `PATH`.
- `server exited during startup`: run `codexbar serve --help` to confirm the
  installed build includes the dashboard server, then update CodexBar if needed.
- `HTTP 401`: update CodexBar and retry. AgentMeter creates a fresh token for the
  child it supervises, so a persistent authorization failure indicates an
  incompatible local server build.
- `unsupported dashboard schema version`: update AgentMeter or CodexBar so their
  versioned dashboard contracts agree.
- A provider is `unavailable`: enable and verify that provider in CodexBar, then
  keep its lowercase ID in AgentMeter configuration.

AgentMeter intentionally suppresses raw server output because provider tools may
include private diagnostics. Run CodexBar directly only when deeper troubleshooting
is necessary, and inspect logs before sharing them.
