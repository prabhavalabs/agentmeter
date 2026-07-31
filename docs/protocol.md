# Device protocol

Protocol version 1 sends a compact UTF-8 JSON snapshot from the desktop host to the display. The canonical machine-readable definition is `schemas/device-snapshot-v1.schema.json`.

## Snapshot example

```json
{
  "schemaVersion": 1,
  "messageId": 42,
  "generatedAtEpoch": 1785508800,
  "staleAfterSeconds": 180,
  "providers": [
    {
      "id": "codex",
      "name": "Codex",
      "status": "ok",
      "windows": [
        {
          "kind": "session",
          "label": "Session",
          "usedPercent": 28,
          "resetAtEpoch": 1785527700
        }
      ]
    }
  ],
  "display": {
    "brightnessPercent": 55,
    "alertThresholds": [75, 90],
    "soundEnabled": false
  },
  "event": null
}
```

## Limits

- Maximum document size: 4096 bytes
- Maximum providers: 4
- Maximum windows per provider: 3
- Provider and window IDs: 1–23 lowercase ASCII characters, digits, `_`, or `-`
- Display labels: 1–23 characters
- Usage: integer from 0 to 100, or `null` when unknown

Unknown fields are ignored. An unknown `schemaVersion` is rejected.

## Staleness and countdowns

`generatedAtEpoch` is the host time when the snapshot was built. A device marks it stale when its age exceeds `staleAfterSeconds`. `resetAtEpoch` is optional; when available, the device updates the countdown locally between host messages.

Missing values are never converted to zero. When a reset time changes, the new timestamp immediately replaces the old countdown.

## Bluetooth framing

Bluetooth messages will use a private service with a data characteristic and a status characteristic. Because the available write size varies by operating system and connection, a snapshot is divided into fragments. Each fragment starts with an eight-byte little-endian header:

```text
byte 0      frame version = 1
byte 1      message type = 1 (snapshot)
bytes 2..3  message ID
bytes 4..5  total JSON byte length
bytes 6..7  fragment offset
bytes 8..N  JSON bytes
```

The firmware acknowledges only after a complete document has been reassembled, parsed, and validated. Detailed status codes and service UUIDs will be frozen with the BLE implementation.

## USB fallback

USB serial carries one minified JSON document followed by a newline. It enters the same validation path as Bluetooth and is intended for setup, diagnostics, and recovery.

