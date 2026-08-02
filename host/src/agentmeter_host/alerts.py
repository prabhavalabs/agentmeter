from __future__ import annotations

from collections import deque
from copy import deepcopy
from dataclasses import dataclass
from typing import Any


@dataclass(frozen=True)
class _PendingAlert:
    provider_id: str
    window_kind: str
    threshold: int

    @property
    def key(self) -> tuple[str, str]:
        return (self.provider_id, self.window_kind)


class AlertEngine:
    """Create one short-lived event when a quota window crosses a threshold."""

    def __init__(self, thresholds: tuple[int, ...]) -> None:
        self._thresholds = tuple(sorted(thresholds))
        self._levels: dict[tuple[str, str], int] = {}
        self._pending: deque[_PendingAlert] = deque()

    def apply(self, snapshot: dict[str, Any]) -> dict[str, Any]:
        result = deepcopy(snapshot)
        observed: set[tuple[str, str]] = set()
        crossed: list[_PendingAlert] = []

        for provider in result.get("providers", []):
            if provider.get("status") != "ok":
                continue
            provider_id = provider.get("id")
            for window in provider.get("windows", []):
                window_kind = window.get("kind")
                used_percent = window.get("usedPercent")
                if (
                    not isinstance(provider_id, str)
                    or not isinstance(window_kind, str)
                    or not isinstance(used_percent, int)
                ):
                    continue
                key = (provider_id, window_kind)
                observed.add(key)
                level = max(
                    (threshold for threshold in self._thresholds if used_percent >= threshold),
                    default=0,
                )
                previous = self._levels.get(key, 0)
                self._levels[key] = level
                if level > previous:
                    crossed.append(_PendingAlert(provider_id, window_kind, level))

        for key in set(self._levels) - observed:
            del self._levels[key]
        crossed.sort(key=lambda alert: alert.threshold, reverse=True)
        for alert in crossed:
            if alert not in self._pending:
                self._pending.append(alert)

        event = None
        while self._pending:
            alert = self._pending.popleft()
            if self._levels.get(alert.key, 0) < alert.threshold:
                continue
            generated_at = int(result["generatedAtEpoch"])
            event = {
                "id": (f"threshold:{alert.provider_id}:{alert.window_kind}:{alert.threshold}"),
                "kind": "threshold",
                "level": ("critical" if alert.threshold == self._thresholds[-1] else "warning"),
                "expiresAtEpoch": generated_at + 90,
            }
            break

        result["event"] = event
        return result
