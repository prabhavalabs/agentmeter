# Device protocol

Protocol version 1 exchanges compact UTF-8 JSON between the desktop bridge and the display. The canonical contracts are [`schemas/device-snapshot-v1.schema.json`](../schemas/device-snapshot-v1.schema.json) and [`schemas/device-management-v1.schema.json`](../schemas/device-management-v1.schema.json).

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
| Management request | `a77e0004-8f7b-4f63-9a53-65f93f0d6d01` | Encrypted write with response |
| Device state and events | `a77e0005-8f7b-4f63-9a53-65f93f0d6d01` | Encrypted read / notify |

The ESP32 requests secure-connections bonding with no input/output capability. A long physical-button press clears its saved bonds.

## Fragment framing

The negotiated BLE write size varies, so a snapshot is divided into frames. Each frame begins with an eight-byte little-endian header:

```text
byte 0      frame version = 1
byte 1      message type
bytes 2..3  message ID
bytes 4..5  total JSON byte length
bytes 6..7  fragment offset
bytes 8..N  JSON bytes
```

Fragments must be ordered and contiguous. A different message ID may replace an incomplete message only when its first fragment has offset zero. Reassembly expires after two seconds.

Message types are `0x01` for a snapshot, `0x02` for a management request,
`0x81` for a snapshot ACK, `0x82` for a management result, and `0x83` for a
device event. Snapshot JSON remains limited to 4096 bytes. Management JSON is
limited to 2048 bytes.

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

## Device management

Management uses a strict, correlated envelope:

```json
{
  "schemaVersion": 1,
  "requestId": 17,
  "type": "settings.patch",
  "payload": {
    "baseRevision": 8,
    "alwaysOn": true
  }
}
```

The 16-bit frame message ID must match the low 16 bits of `requestId`. Every
accepted request receives a result with the same request ID, a matching
`*.result` type, a stable status string, and a payload. The request commands
are:

| Command | Purpose |
| --- | --- |
| `device.get` | Read information, capabilities, telemetry, and settings |
| `telemetry.get` | Read current capability-gated telemetry |
| `settings.get` | Read the confirmed device settings revision |
| `settings.patch` | Apply a validated patch at `baseRevision` |
| `device.identify` | Show an identification banner on the display |
| `device.restart` | Restart after the result has entered the BLE queue |
| `device.forget` | Clear bonds after the result has entered the BLE queue |

Management envelopes and patches reject unknown fields. Status values are
`ok`, `malformedFrame`, `tooLarge`, `invalidJson`, `unsupportedSchema`,
`invalidRequest`, `revisionConflict`, `unsupportedCommand`, and
`persistenceFailed`.

Display settings are device-authoritative. A patch is applied to a candidate,
validated as a complete model, written as one checksummed NVS blob, assigned a
new revision, and only then applied and confirmed. Touchscreen changes follow
the same path and emit a `device.state` event. No-op patches do not write NVS.

Telemetry fields are nullable when the hardware cannot produce a trustworthy
measurement. In particular, the firmware does not treat a configured USB
current limit as measured power consumption. RSSI is a host-side Bluetooth
measurement and is not included in device telemetry.

## USB serial fallback

USB serial runs at 115,200 baud. The host writes one minified JSON document followed by `\n`. The firmware sends `ACK <message-id> <status>\n` after the same model validation used by BLE. Oversized input is discarded through the next newline.
