from __future__ import annotations

import os
import re
import sqlite3
from collections import defaultdict
from datetime import datetime, time
from pathlib import Path
from typing import Any
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

_BUCKET_SECONDS = 300
_RETENTION_SECONDS = 30 * 86_400
_SAFE_ID = re.compile(r"[a-z0-9_-]{1,23}")

_SCHEMA_SQL = """
CREATE TABLE IF NOT EXISTS usage_sample (
  provider_id TEXT NOT NULL,
  window_kind TEXT NOT NULL,
  sampled_at INTEGER NOT NULL,
  bucket INTEGER NOT NULL,
  used_percent INTEGER,
  reset_at INTEGER,
  PRIMARY KEY (provider_id, window_kind, bucket)
);
CREATE TABLE IF NOT EXISTS connection_event (
  occurred_at INTEGER NOT NULL,
  phase TEXT NOT NULL,
  code TEXT
);
CREATE INDEX IF NOT EXISTS connection_event_time ON connection_event (occurred_at);
CREATE TABLE IF NOT EXISTS device_sample (
  sampled_at INTEGER PRIMARY KEY,
  power_source TEXT,
  battery_percent INTEGER,
  battery_voltage_mv INTEGER,
  vbus_voltage_mv INTEGER
);
"""


class HistoryError(ValueError):
    """A normalized history value is invalid."""


class HistoryStore:
    schema_sql = _SCHEMA_SQL

    def __init__(self, path: Path, *, retention_seconds: int = _RETENTION_SECONDS) -> None:
        if retention_seconds < _BUCKET_SECONDS:
            raise ValueError("retention_seconds must be at least five minutes")
        self.path = path
        self._retention_seconds = retention_seconds
        path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        os.chmod(path.parent, 0o700)
        self._connection = sqlite3.connect(path, timeout=2)
        os.chmod(path, 0o600)
        self._connection.execute("PRAGMA busy_timeout = 2000")
        self._connection.execute("PRAGMA journal_mode = WAL")
        self._connection.executescript(_SCHEMA_SQL)
        self._connection.commit()

    def record_usage(
        self,
        provider_id: str,
        window_kind: str,
        sampled_at: int,
        used_percent: int | None,
        reset_at: int | None,
    ) -> None:
        self._validate_id(provider_id, "provider ID")
        self._validate_id(window_kind, "window kind")
        self._validate_epoch(sampled_at, "sample time")
        if used_percent is not None and (
            isinstance(used_percent, bool)
            or not isinstance(used_percent, int)
            or not 0 <= used_percent <= 100
        ):
            raise HistoryError("used percent must be between 0 and 100 or null")
        if reset_at is not None:
            self._validate_epoch(reset_at, "reset time")
        bucket = sampled_at // _BUCKET_SECONDS
        self._connection.execute(
            """
            INSERT INTO usage_sample
              (provider_id, window_kind, sampled_at, bucket, used_percent, reset_at)
            VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(provider_id, window_kind, bucket) DO UPDATE SET
              sampled_at = excluded.sampled_at,
              used_percent = excluded.used_percent,
              reset_at = excluded.reset_at
            """,
            (provider_id, window_kind, sampled_at, bucket, used_percent, reset_at),
        )
        self._connection.commit()

    def record_snapshot(self, snapshot: dict[str, Any]) -> None:
        sampled_at = snapshot.get("generatedAtEpoch")
        self._validate_epoch(sampled_at, "snapshot time")
        providers = snapshot.get("providers")
        if not isinstance(providers, list):
            raise HistoryError("snapshot providers must be an array")
        with self._connection:
            for provider in providers:
                if not isinstance(provider, dict):
                    raise HistoryError("snapshot provider is invalid")
                windows = provider.get("windows")
                if not isinstance(windows, list):
                    raise HistoryError("snapshot windows must be an array")
                for window in windows:
                    if not isinstance(window, dict):
                        raise HistoryError("snapshot window is invalid")
                    self._record_usage_without_commit(
                        provider.get("id"),
                        window.get("kind"),
                        sampled_at,
                        window.get("usedPercent"),
                        window.get("resetAtEpoch"),
                    )

    def _record_usage_without_commit(
        self,
        provider_id: object,
        window_kind: object,
        sampled_at: int,
        used_percent: object,
        reset_at: object,
    ) -> None:
        if not isinstance(provider_id, str) or not isinstance(window_kind, str):
            raise HistoryError("snapshot provider or window ID is invalid")
        self._validate_id(provider_id, "provider ID")
        self._validate_id(window_kind, "window kind")
        if used_percent is not None and (
            isinstance(used_percent, bool)
            or not isinstance(used_percent, int)
            or not 0 <= used_percent <= 100
        ):
            raise HistoryError("used percent must be between 0 and 100 or null")
        if reset_at is not None:
            self._validate_epoch(reset_at, "reset time")
        bucket = sampled_at // _BUCKET_SECONDS
        self._connection.execute(
            """
            INSERT INTO usage_sample
              (provider_id, window_kind, sampled_at, bucket, used_percent, reset_at)
            VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(provider_id, window_kind, bucket) DO UPDATE SET
              sampled_at = excluded.sampled_at,
              used_percent = excluded.used_percent,
              reset_at = excluded.reset_at
            """,
            (provider_id, window_kind, sampled_at, bucket, used_percent, reset_at),
        )

    def record_telemetry(
        self,
        sampled_at: int,
        *,
        power_source: str | None,
        battery_percent: int | None,
        battery_voltage_mv: int | None,
        vbus_voltage_mv: int | None,
    ) -> None:
        self._validate_epoch(sampled_at, "telemetry time")
        if power_source not in {None, "unknown", "usb", "battery"}:
            raise HistoryError("power source is invalid")
        if battery_percent is not None and (
            isinstance(battery_percent, bool)
            or not isinstance(battery_percent, int)
            or not 0 <= battery_percent <= 100
        ):
            raise HistoryError("battery percent must be between 0 and 100 or null")
        for value in (battery_voltage_mv, vbus_voltage_mv):
            invalid_type = isinstance(value, bool) or not isinstance(value, int)
            if value is not None and (invalid_type or not 0 <= value <= 65_535):
                raise HistoryError("voltage must be between 0 and 65535 or null")
        bucket = sampled_at // _BUCKET_SECONDS
        normalized_time = bucket * _BUCKET_SECONDS
        self._connection.execute(
            """
            INSERT INTO device_sample
              (sampled_at, power_source, battery_percent, battery_voltage_mv, vbus_voltage_mv)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(sampled_at) DO UPDATE SET
              power_source = excluded.power_source,
              battery_percent = excluded.battery_percent,
              battery_voltage_mv = excluded.battery_voltage_mv,
              vbus_voltage_mv = excluded.vbus_voltage_mv
            """,
            (
                normalized_time,
                power_source,
                battery_percent,
                battery_voltage_mv,
                vbus_voltage_mv,
            ),
        )
        self._connection.commit()

    def record_connection(self, occurred_at: int, phase: str, code: str | None = None) -> None:
        self._validate_epoch(occurred_at, "connection time")
        if not isinstance(phase, str) or not 1 <= len(phase) <= 32:
            raise HistoryError("connection phase is invalid")
        if code is not None and (not isinstance(code, str) or not 1 <= len(code) <= 64):
            raise HistoryError("connection code is invalid")
        self._connection.execute(
            "INSERT INTO connection_event (occurred_at, phase, code) VALUES (?, ?, ?)",
            (occurred_at, phase, code),
        )
        self._connection.commit()

    def query_usage(
        self,
        *,
        since_epoch: int,
        provider_id: str | None = None,
        limit: int = 2_048,
        bucket_seconds: int | None = None,
        current_cycle: bool = False,
    ) -> list[dict[str, object]]:
        self._validate_epoch(since_epoch, "history boundary")
        if not 1 <= limit <= 10_000:
            raise HistoryError("history limit must be between 1 and 10000")
        if bucket_seconds is not None and (
            isinstance(bucket_seconds, bool)
            or not isinstance(bucket_seconds, int)
            or not _BUCKET_SECONDS <= bucket_seconds <= 86_400
            or bucket_seconds % _BUCKET_SECONDS != 0
        ):
            raise HistoryError("history bucket must be a five-minute multiple up to one day")
        if not isinstance(current_cycle, bool):
            raise HistoryError("current cycle must be a boolean")
        parameters: list[object] = [since_epoch]
        where = "sampled_at >= ?"
        if provider_id is not None:
            self._validate_id(provider_id, "provider ID")
            where += " AND provider_id = ?"
            parameters.append(provider_id)

        if current_cycle:
            rows = self._connection.execute(
                f"""
                SELECT provider_id, window_kind, sampled_at, used_percent, reset_at
                FROM usage_sample WHERE {where}
                ORDER BY sampled_at ASC, provider_id ASC, window_kind ASC
                """,  # noqa: S608 - only a fixed optional clause is interpolated
                parameters,
            ).fetchall()
            return self._current_cycle_rows(rows, limit=limit)

        if bucket_seconds is not None:
            ranked_parameters = [since_epoch, bucket_seconds, *parameters, limit]
            rows = self._connection.execute(
                f"""
                WITH ranked AS (
                  SELECT provider_id, window_kind, sampled_at, used_percent, reset_at,
                    ROW_NUMBER() OVER (
                      PARTITION BY provider_id, window_kind,
                        ((sampled_at - ?) / ?)
                      ORDER BY sampled_at DESC
                    ) AS bucket_rank
                  FROM usage_sample WHERE {where}
                )
                SELECT provider_id, window_kind, sampled_at, used_percent, reset_at
                FROM ranked WHERE bucket_rank = 1
                ORDER BY sampled_at ASC, provider_id ASC, window_kind ASC LIMIT ?
                """,  # noqa: S608 - only a fixed optional clause is interpolated
                ranked_parameters,
            ).fetchall()
            return self._usage_documents(rows)

        parameters.append(limit)
        rows = self._connection.execute(
            f"""
            SELECT provider_id, window_kind, sampled_at, used_percent, reset_at
            FROM usage_sample WHERE {where}
            ORDER BY sampled_at ASC, provider_id ASC, window_kind ASC LIMIT ?
            """,  # noqa: S608 - only a fixed optional clause is interpolated
            parameters,
        ).fetchall()
        return self._usage_documents(rows)

    def query_widget_summary(
        self,
        *,
        since_epoch: int,
        provider_id: str,
        time_zone_identifier: str,
    ) -> dict[str, object]:
        self._validate_epoch(since_epoch, "history boundary")
        self._validate_id(provider_id, "provider ID")
        if not isinstance(time_zone_identifier, str):
            raise HistoryError("time zone identifier is invalid")
        try:
            zone = ZoneInfo(time_zone_identifier)
        except (ZoneInfoNotFoundError, ValueError) as error:
            raise HistoryError("time zone identifier is invalid") from error
        rows = self._connection.execute(
            """
            SELECT provider_id, window_kind, sampled_at, used_percent, reset_at
            FROM usage_sample WHERE provider_id = ?
            ORDER BY window_kind ASC, sampled_at ASC
            """,
            (provider_id,),
        ).fetchall()
        return self._widget_summary_document(rows, since_epoch=since_epoch, zone=zone)

    @staticmethod
    def _widget_summary_document(
        rows: list[tuple[Any, ...]],
        *,
        since_epoch: int,
        zone: ZoneInfo,
    ) -> dict[str, object]:
        history_start_epoch = next((row[2] for row in rows if row[3] is not None), None)
        previous: dict[str, tuple[int | None, int | None]] = {}
        known_resets: dict[str, int] = {}
        known_percents: dict[str, int] = {}
        cycle_starts: dict[str, int | None] = {}
        days: dict[tuple[str, int], dict[str, object]] = {}

        for provider_id, window_kind, sampled_at, used_percent, reset_at in rows:
            previous_percent, previous_reset_at = previous.get(window_kind, (None, None))
            cycle_start = cycle_starts.get(window_kind)
            known_reset = known_resets.get(window_kind)
            if reset_at is not None:
                if known_reset is None or reset_at != known_reset:
                    cycle_start = sampled_at
                known_resets[window_kind] = reset_at
            if used_percent is not None:
                known_percent = known_percents.get(window_kind)
                if known_percent is not None and known_percent - used_percent >= 5:
                    cycle_start = sampled_at
                known_percents[window_kind] = used_percent
            cycle_starts[window_kind] = cycle_start
            if sampled_at >= since_epoch and used_percent is not None:
                local_date = datetime.fromtimestamp(sampled_at, zone).date()
                day_start_epoch = int(
                    datetime.combine(local_date, time.min, tzinfo=zone).timestamp()
                )
                day = days.setdefault(
                    (window_kind, day_start_epoch),
                    {
                        "providerId": provider_id,
                        "windowKind": window_kind,
                        "dayStartEpoch": day_start_epoch,
                        "consumedPercentPoints": 0,
                        "latestUsedPercent": used_percent,
                        "resetAtEpoch": reset_at,
                        "cycleStartEpoch": cycle_start,
                    },
                )
                if (
                    previous_percent is not None
                    and previous_reset_at is not None
                    and reset_at is not None
                    and previous_reset_at == reset_at
                    and used_percent >= previous_percent
                ):
                    day["consumedPercentPoints"] += used_percent - previous_percent
                day["latestUsedPercent"] = used_percent
                day["resetAtEpoch"] = reset_at
                day["cycleStartEpoch"] = cycle_start
            previous[window_kind] = (used_percent, reset_at)

        for (window_kind, _), day in days.items():
            day["cycleStartEpoch"] = cycle_starts.get(window_kind)

        return {
            "historyStartEpoch": history_start_epoch,
            "days": sorted(
                days.values(),
                key=lambda day: (day["dayStartEpoch"], day["windowKind"]),
            ),
        }

    @staticmethod
    def _usage_documents(rows: list[tuple[Any, ...]]) -> list[dict[str, object]]:
        return [
            {
                "providerId": row[0],
                "windowKind": row[1],
                "sampledAtEpoch": row[2],
                "usedPercent": row[3],
                "resetAtEpoch": row[4],
            }
            for row in rows
        ]

    @classmethod
    def _current_cycle_rows(
        cls,
        rows: list[tuple[Any, ...]],
        *,
        limit: int,
    ) -> list[dict[str, object]]:
        cycles: dict[tuple[str, str], list[tuple[Any, ...]]] = defaultdict(list)
        previous: dict[tuple[str, str], tuple[int | None, int | None]] = {}
        for row in rows:
            key = (row[0], row[1])
            used_percent = row[3]
            reset_at = row[4]
            previous_percent, previous_reset = previous.get(key, (None, None))
            reset_changed = (
                previous_reset is not None and reset_at is not None and reset_at != previous_reset
            )
            clear_cycle = (
                used_percent is not None
                and previous_percent is not None
                and used_percent < previous_percent
                and (reset_changed or previous_percent - used_percent >= 5)
            )
            if clear_cycle:
                cycles[key].clear()
            cycles[key].append(row)
            previous[key] = (used_percent, reset_at)

        sampled: list[tuple[Any, ...]] = []
        maximum_per_series = 30
        for cycle in cycles.values():
            if len(cycle) <= maximum_per_series:
                sampled.extend(cycle)
                continue
            first_epoch = cycle[0][2]
            span = max(1, cycle[-1][2] - first_epoch + 1)
            bucket_seconds = max(
                _BUCKET_SECONDS,
                ((span + maximum_per_series - 1) // maximum_per_series + _BUCKET_SECONDS - 1)
                // _BUCKET_SECONDS
                * _BUCKET_SECONDS,
            )
            buckets: dict[int, tuple[Any, ...]] = {}
            for row in cycle:
                buckets[(row[2] - first_epoch) // bucket_seconds] = row
            sampled.extend(list(buckets.values())[-maximum_per_series:])

        sampled.sort(key=lambda row: (row[2], row[0], row[1]))
        return cls._usage_documents(sampled[:limit])

    def prune(self, *, now_epoch: int) -> None:
        self._validate_epoch(now_epoch, "prune time")
        boundary = max(0, now_epoch - self._retention_seconds)
        with self._connection:
            self._connection.execute("DELETE FROM usage_sample WHERE sampled_at < ?", (boundary,))
            self._connection.execute(
                "DELETE FROM connection_event WHERE occurred_at < ?", (boundary,)
            )
            self._connection.execute("DELETE FROM device_sample WHERE sampled_at < ?", (boundary,))

    def clear(self) -> None:
        with self._connection:
            self._connection.execute("DELETE FROM usage_sample")
            self._connection.execute("DELETE FROM connection_event")
            self._connection.execute("DELETE FROM device_sample")

    def close(self) -> None:
        self._connection.close()

    @staticmethod
    def _validate_id(value: object, label: str) -> None:
        if not isinstance(value, str) or _SAFE_ID.fullmatch(value) is None:
            raise HistoryError(f"{label} is invalid")

    @staticmethod
    def _validate_epoch(value: object, label: str) -> None:
        if isinstance(value, bool) or not isinstance(value, int) or value < 0:
            raise HistoryError(f"{label} must be a nonnegative integer")

    def __enter__(self) -> HistoryStore:
        return self

    def __exit__(self, *_args: object) -> None:
        self.close()
