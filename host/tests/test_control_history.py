import stat
from datetime import datetime
from zoneinfo import ZoneInfo

import pytest
from agentmeter_host.control.history import HistoryError, HistoryStore


def test_widget_summary_counts_positive_deltas_without_counting_resets(tmp_path) -> None:
    history = HistoryStore(tmp_path / "history.sqlite3")
    for sampled_at, percent, reset_at in (
        (1_788_249_600, 10, 1_788_336_000),
        (1_788_253_200, 16, 1_788_336_000),
        (1_788_256_800, 3, 1_788_422_400),
        (1_788_260_400, 8, 1_788_422_400),
    ):
        history.record_usage("claude", "weekly", sampled_at, percent, reset_at)

    result = history.query_widget_summary(
        since_epoch=1_788_249_600,
        provider_id="claude",
        time_zone_identifier="UTC",
    )

    assert result["days"] == [
        {
            "providerId": "claude",
            "windowKind": "weekly",
            "dayStartEpoch": 1_788_220_800,
            "consumedPercentPoints": 11,
            "latestUsedPercent": 8,
            "resetAtEpoch": 1_788_422_400,
            "cycleStartEpoch": 1_788_256_800,
        }
    ]
    history.close()


def test_widget_summary_does_not_count_increases_without_known_reset_continuity(tmp_path) -> None:
    history = HistoryStore(tmp_path / "history.sqlite3")
    history.record_usage("claude", "weekly", 1_788_249_600, 10, None)
    history.record_usage("claude", "weekly", 1_788_253_200, 20, None)

    result = history.query_widget_summary(
        since_epoch=1_788_249_600,
        provider_id="claude",
        time_zone_identifier="UTC",
    )

    assert result["days"] == [
        {
            "providerId": "claude",
            "windowKind": "weekly",
            "dayStartEpoch": 1_788_220_800,
            "consumedPercentPoints": 0,
            "latestUsedPercent": 20,
            "resetAtEpoch": None,
            "cycleStartEpoch": None,
        }
    ]
    history.close()


def test_widget_summary_uses_local_day_starts_across_berlin_spring_dst(tmp_path) -> None:
    history = HistoryStore(tmp_path / "history.sqlite3")
    zone = ZoneInfo("Europe/Berlin")
    march_29 = int(datetime(2026, 3, 29, 12, tzinfo=zone).timestamp())
    march_30 = int(datetime(2026, 3, 30, 12, tzinfo=zone).timestamp())
    history.record_usage("claude", "weekly", march_29, 10, 1_800_000_000)
    history.record_usage("claude", "weekly", march_30, 10, 1_800_000_000)

    result = history.query_widget_summary(
        since_epoch=march_29,
        provider_id="claude",
        time_zone_identifier="Europe/Berlin",
    )

    day_starts = [day["dayStartEpoch"] for day in result["days"]]
    assert day_starts[1] - day_starts[0] == 82_800
    history.close()


def test_widget_summary_derives_and_propagates_observed_cycle_starts(tmp_path) -> None:
    history = HistoryStore(tmp_path / "history.sqlite3")
    samples = (
        (1_000, 10, 500_000),
        (87_400, 20, 500_000),
        (173_800, 25, 600_000),
        (260_200, 30, 600_000),
        (346_600, 3, 600_000),
    )
    for sampled_at, percent, reset_at in samples:
        history.record_usage("claude", "weekly", sampled_at, percent, reset_at)

    result = history.query_widget_summary(
        since_epoch=0,
        provider_id="claude",
        time_zone_identifier="UTC",
    )

    assert [day["cycleStartEpoch"] for day in result["days"]] == [346_600] * 5
    history.close()


def test_widget_summary_leaves_cycle_start_unknown_without_boundary_evidence(tmp_path) -> None:
    history = HistoryStore(tmp_path / "history.sqlite3")
    history.record_usage("claude", "weekly", 1_000, 10, None)
    history.record_usage("claude", "weekly", 87_400, 20, None)

    result = history.query_widget_summary(
        since_epoch=0,
        provider_id="claude",
        time_zone_identifier="UTC",
    )

    assert [day["cycleStartEpoch"] for day in result["days"]] == [None, None]
    history.close()


def test_widget_summary_uses_pre_boundary_baseline_and_omits_unknown_days(tmp_path) -> None:
    history = HistoryStore(tmp_path / "history.sqlite3")
    history.record_usage("claude", "weekly", 1_788_246_000, 20, 1_788_336_000)
    history.record_usage("claude", "weekly", 1_788_249_600, 25, 1_788_336_000)
    history.record_usage("claude", "session", 1_788_249_600, None, None)
    history.record_usage("claude", "session", 1_788_336_000, None, None)

    result = history.query_widget_summary(
        since_epoch=1_788_249_600,
        provider_id="claude",
        time_zone_identifier="UTC",
    )

    assert result == {
        "historyStartEpoch": 1_788_246_000,
        "days": [
            {
                "providerId": "claude",
                "windowKind": "weekly",
                "dayStartEpoch": 1_788_220_800,
                "consumedPercentPoints": 5,
                "latestUsedPercent": 25,
                "resetAtEpoch": 1_788_336_000,
                "cycleStartEpoch": 1_788_246_000,
            }
        ],
    }
    history.close()


def test_widget_summary_keeps_known_zero_days_private_and_provider_scoped(tmp_path) -> None:
    history = HistoryStore(tmp_path / "history.sqlite3")
    history.record_usage("claude", "weekly", 1_788_249_600, 10, 1_788_336_000)
    history.record_usage("codex", "weekly", 1_788_249_600, 90, 1_788_336_000)

    result = history.query_widget_summary(
        since_epoch=1_788_249_600,
        provider_id="claude",
        time_zone_identifier="UTC",
    )

    assert result["historyStartEpoch"] == 1_788_249_600
    assert result["days"] == [
        {
            "providerId": "claude",
            "windowKind": "weekly",
            "dayStartEpoch": 1_788_220_800,
            "consumedPercentPoints": 0,
            "latestUsedPercent": 10,
            "resetAtEpoch": 1_788_336_000,
            "cycleStartEpoch": 1_788_249_600,
        }
    ]
    assert not {"name", "identity", "prompt", "rawValues"} & set(result["days"][0])
    with pytest.raises(HistoryError, match="provider ID"):
        history.query_widget_summary(
            since_epoch=1_788_249_600,
            provider_id="Claude!",
            time_zone_identifier="UTC",
        )
    with pytest.raises(HistoryError, match="time zone identifier"):
        history.query_widget_summary(
            since_epoch=1_788_249_600,
            provider_id="claude",
            time_zone_identifier="Not/AZone",
        )
    history.close()


def test_history_downsamples_and_prunes_without_identity(tmp_path) -> None:
    history = HistoryStore(tmp_path / "history.sqlite3")
    history.record_usage("claude", "session", 1_000, 41, 5_000)
    history.record_usage("claude", "session", 1_100, 42, 5_000)
    history.record_usage("claude", "session", 1_301, 43, 5_000)

    assert history.query_usage(since_epoch=0) == [
        {
            "providerId": "claude",
            "windowKind": "session",
            "sampledAtEpoch": 1_100,
            "usedPercent": 42,
            "resetAtEpoch": 5_000,
        },
        {
            "providerId": "claude",
            "windowKind": "session",
            "sampledAtEpoch": 1_301,
            "usedPercent": 43,
            "resetAtEpoch": 5_000,
        },
    ]
    assert "account" not in history.schema_sql.lower()
    assert "prompt" not in history.schema_sql.lower()
    assert stat.S_IMODE(history.path.stat().st_mode) == 0o600

    history.prune(now_epoch=1_000 + 31 * 86_400)
    assert history.query_usage(since_epoch=0) == []
    history.close()


def test_history_records_only_normalized_snapshot_fields(tmp_path) -> None:
    history = HistoryStore(tmp_path / "history.sqlite3")
    history.record_snapshot(
        {
            "generatedAtEpoch": 1_000,
            "providers": [
                {
                    "id": "codex",
                    "name": "Codex",
                    "identity": {"email": "must-not-be-stored@example.test"},
                    "windows": [
                        {
                            "kind": "session",
                            "usedPercent": 28,
                            "resetAtEpoch": 5_000,
                        }
                    ],
                }
            ],
        }
    )

    rows = history.query_usage(since_epoch=0)
    assert rows[0]["usedPercent"] == 28
    database = history.path.read_bytes()
    assert b"must-not-be-stored" not in database
    history.close()


def test_history_query_returns_last_sample_in_each_requested_bucket(tmp_path) -> None:
    history = HistoryStore(tmp_path / "history.sqlite3")
    history.record_usage("claude", "session", 3_610, 11, 9_000)
    history.record_usage("claude", "session", 3_900, 12, 9_000)
    history.record_usage("claude", "session", 7_250, 18, 9_000)

    assert history.query_usage(since_epoch=3_600, bucket_seconds=3_600) == [
        {
            "providerId": "claude",
            "windowKind": "session",
            "sampledAtEpoch": 3_900,
            "usedPercent": 12,
            "resetAtEpoch": 9_000,
        },
        {
            "providerId": "claude",
            "windowKind": "session",
            "sampledAtEpoch": 7_250,
            "usedPercent": 18,
            "resetAtEpoch": 9_000,
        },
    ]
    history.close()


def test_history_current_cycle_starts_after_latest_observed_reset(tmp_path) -> None:
    history = HistoryStore(tmp_path / "history.sqlite3")
    for sampled_at, percent in (
        (1_000, 70),
        (1_300, 82),
        (1_600, 4),
        (1_900, 9),
    ):
        history.record_usage("claude", "session", sampled_at, percent, 5_000)

    rows = history.query_usage(since_epoch=0, current_cycle=True)

    assert [(row["sampledAtEpoch"], row["usedPercent"]) for row in rows] == [
        (1_600, 4),
        (1_900, 9),
    ]
    history.close()


def test_history_bounds_values_and_clear_removes_every_table(tmp_path) -> None:
    history = HistoryStore(tmp_path / "history.sqlite3")
    with pytest.raises(HistoryError, match="used percent"):
        history.record_usage("codex", "session", 1_000, 101, None)
    history.record_usage("codex", "session", 1_000, None, None)
    history.record_telemetry(
        1_000,
        power_source="usb",
        battery_percent=None,
        battery_voltage_mv=None,
        vbus_voltage_mv=5_050,
    )
    history.record_connection(1_000, "connected")

    history.clear()

    assert history.query_usage(since_epoch=0) == []
    assert history._connection.execute("SELECT COUNT(*) FROM device_sample").fetchone()[0] == 0
    assert history._connection.execute("SELECT COUNT(*) FROM connection_event").fetchone()[0] == 0
    history.close()
