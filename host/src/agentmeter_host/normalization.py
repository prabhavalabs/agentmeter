from __future__ import annotations

import re
from dataclasses import dataclass
from datetime import datetime
from typing import Any

_PROVIDER_NAMES = {
    "claude": "Claude",
    "codex": "Codex",
    "cursor": "Cursor",
    "gemini": "Gemini",
}


class NormalizationError(ValueError):
    """The upstream dashboard cannot be represented by the device contract."""


@dataclass(frozen=True)
class DisplayPreferences:
    brightness_percent: int
    alert_thresholds: tuple[int, ...]
    sound_enabled: bool
    dim_after_seconds: int = 300
    screen_off_after_seconds: int = 1_800

    def __post_init__(self) -> None:
        if not isinstance(self.brightness_percent, int) or not 1 <= self.brightness_percent <= 100:
            raise NormalizationError("brightness_percent must be an integer from 1 to 100")
        if (
            not 1 <= len(self.alert_thresholds) <= 3
            or any(
                not isinstance(value, int) or not 1 <= value <= 100
                for value in self.alert_thresholds
            )
            or any(
                current <= previous
                for previous, current in zip(
                    self.alert_thresholds, self.alert_thresholds[1:], strict=False
                )
            )
        ):
            raise NormalizationError(
                "alert_thresholds must contain 1-3 increasing unique integers from 1 to 100"
            )
        if not isinstance(self.sound_enabled, bool):
            raise NormalizationError("sound_enabled must be a boolean")
        if (
            not isinstance(self.dim_after_seconds, int)
            or not 30 <= self.dim_after_seconds <= 86_400
        ):
            raise NormalizationError("dim_after_seconds must be between 30 and 86400")
        if (
            not isinstance(self.screen_off_after_seconds, int)
            or self.screen_off_after_seconds < self.dim_after_seconds
            or self.screen_off_after_seconds > 86_400
        ):
            raise NormalizationError(
                "screen_off_after_seconds must be between dim_after_seconds and 86400"
            )


def _epoch(timestamp: str | None) -> int | None:
    if timestamp is None:
        return None
    parsed = datetime.fromisoformat(timestamp.replace("Z", "+00:00"))
    if parsed.tzinfo is None:
        raise ValueError("timestamp must include a timezone")
    epoch = int(parsed.timestamp())
    if epoch < 0:
        raise ValueError("timestamp predates the device epoch")
    return epoch


def _label(value: object, *, fallback: str) -> str:
    normalized = " ".join(value.split()) if isinstance(value, str) else ""
    return (normalized or fallback)[:23]


def _identifier(value: object) -> str:
    normalized = value.lower() if isinstance(value, str) else ""
    normalized = re.sub(r"[^a-z0-9_-]+", "_", normalized).strip("_-")
    return (normalized or "window")[:23]


def _used_percent(value: object) -> int | None:
    if value is None:
        return None
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not 0 <= value <= 100:
        raise NormalizationError("usedPercent must be between 0 and 100 or null")
    return round(value)


def _provider_status(
    provider: dict[str, Any], *, generated_at_epoch: int, stale_after_seconds: int
) -> str:
    if not provider.get("enabled", True):
        return "unavailable"
    if provider.get("error") is not None:
        return "error"
    updated_at_epoch = _epoch(provider.get("updatedAt"))
    if updated_at_epoch is not None and generated_at_epoch - updated_at_epoch > stale_after_seconds:
        return "stale"
    return "ok"


def _normalize_dashboard_snapshot(
    dashboard: dict[str, Any],
    *,
    provider_ids: tuple[str, ...],
    message_id: int,
    display: DisplayPreferences,
) -> dict[str, Any]:
    if not 1 <= len(provider_ids) <= 8:
        raise NormalizationError("device snapshots require between 1 and 8 providers")
    if not isinstance(message_id, int) or not 0 <= message_id <= 65_535:
        raise NormalizationError("message_id must be an integer from 0 to 65535")

    schema_version = dashboard.get("schemaVersion")
    if schema_version != 1:
        raise NormalizationError(f"unsupported dashboard schema version {schema_version}")

    generated_at_epoch = _epoch(dashboard["generatedAt"])
    if generated_at_epoch is None:
        raise ValueError("generatedAt is required")
    stale_after_seconds = dashboard["staleAfterSeconds"]
    if not isinstance(stale_after_seconds, int) or not 30 <= stale_after_seconds <= 3_600:
        raise NormalizationError("staleAfterSeconds must be an integer from 30 to 3600")
    providers_by_id = {provider["id"]: provider for provider in dashboard["providers"]}
    providers = []
    for provider_id in provider_ids:
        provider = providers_by_id.get(provider_id)
        if provider is None:
            providers.append(
                {
                    "id": provider_id,
                    "name": _PROVIDER_NAMES.get(provider_id, provider_id.title()),
                    "status": "unavailable",
                    "windows": [],
                }
            )
            continue

        windows = [
            {
                "kind": _identifier(window["kind"]),
                "label": _label(window["label"], fallback="Window"),
                "usedPercent": _used_percent(window["usedPercent"]),
                "resetAtEpoch": _epoch(window.get("resetAt")),
            }
            for window in provider["windows"][:3]
        ]
        providers.append(
            {
                "id": provider["id"],
                "name": _label(provider["name"], fallback=provider["id"].title()),
                "status": _provider_status(
                    provider,
                    generated_at_epoch=generated_at_epoch,
                    stale_after_seconds=stale_after_seconds,
                ),
                "windows": windows,
            }
        )

    return {
        "schemaVersion": 1,
        "messageId": message_id,
        "generatedAtEpoch": generated_at_epoch,
        "staleAfterSeconds": stale_after_seconds,
        "providers": providers,
        "display": {
            "brightnessPercent": display.brightness_percent,
            "dimAfterSeconds": display.dim_after_seconds,
            "screenOffAfterSeconds": display.screen_off_after_seconds,
            "alertThresholds": list(display.alert_thresholds),
            "soundEnabled": display.sound_enabled,
        },
        "event": None,
    }


def normalize_dashboard_snapshot(
    dashboard: dict[str, Any],
    *,
    provider_ids: tuple[str, ...],
    message_id: int,
    display: DisplayPreferences,
) -> dict[str, Any]:
    try:
        return _normalize_dashboard_snapshot(
            dashboard,
            provider_ids=provider_ids,
            message_id=message_id,
            display=display,
        )
    except NormalizationError:
        raise
    except (AttributeError, KeyError, OverflowError, TypeError, ValueError) as error:
        raise NormalizationError("dashboard schema version 1 is invalid") from error
