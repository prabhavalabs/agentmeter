import stat

import pytest
from agentmeter_host.control.history import HistoryError, HistoryStore


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
