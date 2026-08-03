def dashboard_snapshot() -> dict[str, object]:
    return {
        "schemaVersion": 1,
        "generatedAt": "2026-08-01T18:00:00Z",
        "staleAfterSeconds": 180,
        "host": {
            "codexBarVersion": "0.37.2",
            "refreshIntervalSeconds": 60,
        },
        "providers": [
            {
                "id": "codex",
                "name": "Codex",
                "enabled": True,
                "source": "oauth",
                "status": {
                    "level": "ok",
                    "label": "Operational",
                    "updatedAt": "2026-08-01T17:59:00Z",
                },
                "identity": {
                    "accountEmail": "redacted@example.test",
                    "plan": "Pro 20x",
                },
                "windows": [
                    {
                        "kind": "session",
                        "label": "Session",
                        "usedPercent": 28,
                        "remainingPercent": 72,
                        "resetAt": "2026-08-01T20:00:00Z",
                    }
                ],
                "credits": {"remaining": 112.4, "unit": "credits"},
                "cost": {"todayUSD": 1.04, "last30DaysUSD": 18.22},
                "display": {
                    "accentColor": "#49A3B0",
                    "sortKey": 0,
                    "priority": "normal",
                },
                "error": None,
                "updatedAt": "2026-08-01T17:59:45Z",
            }
        ],
    }


def provider_usage(provider_id: str = "codex") -> dict[str, object]:
    return {
        "provider": provider_id,
        "source": "oauth",
        "usage": {
            "primary": {
                "usedPercent": 27.6,
                "resetsAt": "2026-08-01T20:00:00Z",
            },
            "secondary": {
                "usedPercent": 41.2,
                "resetsAt": "2026-08-08T18:00:00Z",
            },
            "tertiary": None,
            "extraRateWindows": [],
            "updatedAt": "2026-08-01T17:59:45Z",
            "identity": {"accountEmail": "redacted@example.test"},
        },
        "account": {"email": "also-private@example.test"},
        "error": None,
    }


def device_snapshot(*, message_id: int = 15) -> dict[str, object]:
    return {
        "schemaVersion": 1,
        "messageId": message_id,
        "generatedAtEpoch": 1_785_607_200,
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
                        "resetAtEpoch": 1_785_614_400,
                    }
                ],
            }
        ],
        "display": {
            "brightnessPercent": 55,
            "alertThresholds": [75, 90],
            "soundEnabled": False,
        },
        "event": None,
    }
