# Architecture

AgentMeter separates provider access from the physical display. The computer handles authentication and collection; the ESP32 receives only the values required for presentation.

## Data flow

```mermaid
flowchart LR
    A["Provider credentials and local sessions"] --> B["CodexBar"]
    B -->|"Loopback dashboard API"| C["AgentMeter host"]
    C --> D["Validate and allowlist fields"]
    D --> E["Threshold event engine"]
    E -->|"Encrypted BLE + ACK"| F["Firmware model"]
    E -.->|"USB serial fallback"| F
    F --> G["Overview and details"]
    F --> H["Local countdowns and stale state"]
```

## Desktop host

The Python bridge:

1. Starts `codexbar serve` on `127.0.0.1` and a temporary port.
2. Uses a newly generated 256-bit bearer token for that child process.
3. Fetches and validates dashboard schema version 1.
4. Selects up to four configured providers and three quota windows per provider.
5. Removes identity, credentials, raw errors, costs, credits, and unrelated fields.
6. Creates deduplicated threshold events in memory.
7. Fragments, sends, retries, and waits for a firmware acknowledgement.
8. Runs interactively or as a macOS LaunchAgent installed into an isolated virtual environment.

Provider collection is behind an adapter boundary, so another local source can be added without changing the firmware contract.

## Firmware

The ESP32 application:

1. Advertises a private GATT service as `AgentMeter-XXXX`.
2. Requires an encrypted bonded connection for data and status characteristics.
3. Queues BLE writes outside the callback, reassembles ordered fragments, and rejects incomplete, oversized, or malformed messages.
4. Parses into a fixed-size candidate model and swaps it in only after complete validation.
5. Renders overview, provider detail, alert, waiting, reconnecting, stale, unavailable, and provider-error states.
6. Updates countdowns locally without network time or continuous host traffic.
7. Protects the AMOLED with moderate brightness, dimming, screen-off, and one-pixel shifting.

The same parser accepts newline-delimited USB serial snapshots for diagnosis and recovery.

## Privacy boundary

The display may receive provider IDs and names, short status values, quota labels, usage percentages, reset timestamps, display preferences, and short-lived event IDs. It must never receive API keys, OAuth tokens, cookies, email addresses, account IDs, prompts, code, file paths, repository names, raw responses, or local coding-session logs.

CodexBar stays on loopback. Its temporary bearer token is passed through `CODEXBAR_DASHBOARD_TOKEN`, not command arguments or files. The supervised server is stopped after each collection.

## Reliability rules

- Missing usage remains unknown and is never converted to zero.
- Documents are capped at 4096 bytes.
- Frame and schema versions are checked explicitly.
- Fragments must arrive in order and complete within two seconds.
- A five-byte ACK is sent only after the JSON has been reassembled and parsed.
- The host retries a whole message up to three times and reconnects after link errors.
- Invalid data never replaces the last valid model.
- Old values may remain visible, but the UI marks them stale and reduces opacity.
- Message IDs wrap safely from 65,535 to zero; countdown and stale calculations tolerate `millis()` rollover.

## Supported scope

- Host: macOS 14 or later
- Board: Waveshare ESP32-S3-Touch-AMOLED-2.16
- Acceptance providers: Codex, Claude, and Gemini
- Primary transport: Bluetooth LE
- Recovery transport: USB serial

Linux, Windows, more boards, and additional data adapters remain future work.
