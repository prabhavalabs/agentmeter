# Device protocol

Protocol version 1 sends compact UTF-8 JSON from the desktop bridge to the display. The canonical contract is [`schemas/device-snapshot-v1.schema.json`](../schemas/device-snapshot-v1.schema.json).

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
    "dimAfterSeconds": 300,
    "screenOffAfterSeconds": 1800,
    "alertThresholds": [75, 90],
    "soundEnabled": false
  },
  "event": null
}
```

## Limits

- Document: at most 4096 bytes
- Providers: at most 8
- Windows per provider: at most 3
- Provider and window IDs: 1–23 lowercase ASCII letters, digits, `_`, or `-`
- Display labels: 1–23 characters
- Event ID: at most 96 characters
- Usage: integer 0–100, or `null` when unknown
- Stale interval: 30–3600 seconds

Unknown fields are ignored. An unknown schema version or invalid required value rejects the complete candidate model.

## Time and events

`generatedAtEpoch` anchors the device's monotonic clock when a snapshot arrives. The firmware advances reset countdowns locally and marks the model stale once its age exceeds `staleAfterSeconds`.

A threshold event uses an ID such as `threshold:claude:weekly:90`, a `warning` or `critical` level, and an expiry epoch. Only the short event is sent; the device derives a human-readable message from the already allowlisted provider model. The host queues simultaneous crossings and suppresses repeats until the window falls below the relevant threshold.

## Bluetooth service

| Purpose | UUID | Properties |
| --- | --- | --- |
| AgentMeter service | `a77e0001-8f7b-4f63-9a53-65f93f0d6d01` | Primary service |
| Snapshot data | `a77e0002-8f7b-4f63-9a53-65f93f0d6d01` | Encrypted write / write without response |
| Delivery status | `a77e0003-8f7b-4f63-9a53-65f93f0d6d01` | Encrypted read / notify |

The ESP32 requests secure-connections bonding with no input/output capability. A long physical-button press clears its saved bonds.

## Fragment framing

The negotiated BLE write size varies, so a snapshot is divided into frames. Each frame begins with an eight-byte little-endian header:

```text
byte 0      frame version = 1
byte 1      message type = 1 (snapshot)
bytes 2..3  message ID
bytes 4..5  total JSON byte length
bytes 6..7  fragment offset
bytes 8..N  JSON bytes
```

Fragments must be ordered and contiguous. A different message ID may replace an incomplete message only when its first fragment has offset zero. Reassembly expires after two seconds.

## Acknowledgement

The status characteristic notifies exactly five bytes:

```text
byte 0      frame version = 1
byte 1      message type = 0x81 (ACK)
bytes 2..3  message ID
byte 4      status
```

| Status | Meaning |
| ---: | --- |
| `0` | Accepted and applied |
| `1` | Malformed frame |
| `2` | Payload too large |
| `3` | Invalid JSON |
| `4` | Unsupported schema version |
| `5` | Invalid snapshot model |

The host waits up to two seconds for the matching ACK and retries the complete message up to three times. A nonzero validation status is not retried because resending identical invalid data cannot fix it.

## USB serial fallback

USB serial runs at 115,200 baud. The host writes one minified JSON document followed by `\n`. The firmware sends `ACK <message-id> <status>\n` after the same model validation used by BLE. Oversized input is discarded through the next newline.
