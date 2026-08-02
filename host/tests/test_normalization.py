import copy
import json
from pathlib import Path

import pytest
from helpers import dashboard_snapshot

ROOT = Path(__file__).parents[2]


def test_normalizer_builds_whitelisted_device_snapshot() -> None:
    from agentmeter_host.normalization import DisplayPreferences, normalize_dashboard_snapshot

    snapshot = normalize_dashboard_snapshot(
        dashboard_snapshot(),
        provider_ids=("codex",),
        message_id=7,
        display=DisplayPreferences(
            brightness_percent=55,
            alert_thresholds=(75, 90),
            sound_enabled=False,
        ),
    )

    assert snapshot == {
        "schemaVersion": 1,
        "messageId": 7,
        "generatedAtEpoch": 1785607200,
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
                        "resetAtEpoch": 1785614400,
                    }
                ],
            }
        ],
        "display": {
            "brightnessPercent": 55,
            "dimAfterSeconds": 300,
            "screenOffAfterSeconds": 1800,
            "alertThresholds": [75, 90],
            "soundEnabled": False,
        },
        "event": None,
    }

    encoded = json.dumps(snapshot)
    assert "redacted@example.test" not in encoded
    assert "Pro 20x" not in encoded
    assert "oauth" not in encoded
    assert "112.4" not in encoded
    assert "18.22" not in encoded


def test_normalizer_rejects_unsupported_dashboard_schema() -> None:
    from agentmeter_host.normalization import (
        DisplayPreferences,
        NormalizationError,
        normalize_dashboard_snapshot,
    )

    dashboard = dashboard_snapshot()
    dashboard["schemaVersion"] = 2

    with pytest.raises(NormalizationError, match="dashboard schema version 2"):
        normalize_dashboard_snapshot(
            dashboard,
            provider_ids=("codex",),
            message_id=7,
            display=DisplayPreferences(55, (75, 90), False),
        )


def test_normalizer_marks_missing_configured_provider_unavailable() -> None:
    from agentmeter_host.normalization import DisplayPreferences, normalize_dashboard_snapshot

    snapshot = normalize_dashboard_snapshot(
        dashboard_snapshot(),
        provider_ids=("claude", "codex"),
        message_id=8,
        display=DisplayPreferences(55, (75, 90), False),
    )

    assert snapshot["providers"] == [
        {
            "id": "claude",
            "name": "Claude",
            "status": "unavailable",
            "windows": [],
        },
        {
            "id": "codex",
            "name": "Codex",
            "status": "ok",
            "windows": [
                {
                    "kind": "session",
                    "label": "Session",
                    "usedPercent": 28,
                    "resetAtEpoch": 1785614400,
                }
            ],
        },
    ]


def test_normalizer_maps_upstream_error_without_leaking_details() -> None:
    from agentmeter_host.normalization import DisplayPreferences, normalize_dashboard_snapshot

    dashboard = dashboard_snapshot()
    provider = dashboard["providers"][0]
    provider["error"] = {
        "code": "credentials_expired",
        "message": "Private account detail must remain on the Mac",
    }

    snapshot = normalize_dashboard_snapshot(
        dashboard,
        provider_ids=("codex",),
        message_id=9,
        display=DisplayPreferences(55, (75, 90), False),
    )

    assert snapshot["providers"][0]["status"] == "error"
    assert "Private account detail" not in json.dumps(snapshot)
    assert "credentials_expired" not in json.dumps(snapshot)


def test_normalizer_marks_old_provider_data_stale() -> None:
    from agentmeter_host.normalization import DisplayPreferences, normalize_dashboard_snapshot

    dashboard = dashboard_snapshot()
    provider = dashboard["providers"][0]
    provider["updatedAt"] = "2026-08-01T17:50:00Z"

    snapshot = normalize_dashboard_snapshot(
        dashboard,
        provider_ids=("codex",),
        message_id=10,
        display=DisplayPreferences(55, (75, 90), False),
    )

    assert snapshot["providers"][0]["status"] == "stale"


def test_normalizer_marks_disabled_provider_unavailable() -> None:
    from agentmeter_host.normalization import DisplayPreferences, normalize_dashboard_snapshot

    dashboard = dashboard_snapshot()
    dashboard["providers"][0]["enabled"] = False

    snapshot = normalize_dashboard_snapshot(
        dashboard,
        provider_ids=("codex",),
        message_id=11,
        display=DisplayPreferences(55, (75, 90), False),
    )

    assert snapshot["providers"][0]["status"] == "unavailable"


def test_normalizer_rejects_more_providers_than_device_contract_allows() -> None:
    from agentmeter_host.normalization import (
        DisplayPreferences,
        NormalizationError,
        normalize_dashboard_snapshot,
    )

    with pytest.raises(NormalizationError, match="between 1 and 4 providers"):
        normalize_dashboard_snapshot(
            dashboard_snapshot(),
            provider_ids=("codex", "claude", "gemini", "four", "five"),
            message_id=12,
            display=DisplayPreferences(55, (75, 90), False),
        )


@pytest.mark.parametrize(
    ("display", "message"),
    [
        ((0, (75, 90), False), "brightness_percent"),
        ((55, (), False), "alert_thresholds"),
        ((55, (75, 101), False), "alert_thresholds"),
        ((55, (90, 75), False), "alert_thresholds"),
        ((55, (75, 75), False), "alert_thresholds"),
    ],
)
def test_display_preferences_reject_values_outside_device_contract(
    display: tuple[int, tuple[int, ...], bool], message: str
) -> None:
    from agentmeter_host.normalization import DisplayPreferences, NormalizationError

    with pytest.raises(NormalizationError, match=message):
        DisplayPreferences(*display)


@pytest.mark.parametrize(
    ("dim_after", "screen_off_after", "message"),
    [
        (29, 1_800, "dim_after_seconds"),
        (86_401, 86_401, "dim_after_seconds"),
        (600, 599, "screen_off_after_seconds"),
        (600, 86_401, "screen_off_after_seconds"),
    ],
)
def test_display_preferences_reject_invalid_power_intervals(
    dim_after: int, screen_off_after: int, message: str
) -> None:
    from agentmeter_host.normalization import DisplayPreferences, NormalizationError

    with pytest.raises(NormalizationError, match=message):
        DisplayPreferences(
            55,
            (75, 90),
            False,
            dim_after_seconds=dim_after,
            screen_off_after_seconds=screen_off_after,
        )


@pytest.mark.parametrize("message_id", [-1, 65_536])
def test_normalizer_rejects_message_id_outside_device_contract(message_id: int) -> None:
    from agentmeter_host.normalization import (
        DisplayPreferences,
        NormalizationError,
        normalize_dashboard_snapshot,
    )

    with pytest.raises(NormalizationError, match="message_id"):
        normalize_dashboard_snapshot(
            dashboard_snapshot(),
            provider_ids=("codex",),
            message_id=message_id,
            display=DisplayPreferences(55, (75, 90), False),
        )


def test_normalizer_rejects_stale_window_outside_device_contract() -> None:
    from agentmeter_host.normalization import (
        DisplayPreferences,
        NormalizationError,
        normalize_dashboard_snapshot,
    )

    dashboard = dashboard_snapshot()
    dashboard["staleAfterSeconds"] = 5

    with pytest.raises(NormalizationError, match="staleAfterSeconds"):
        normalize_dashboard_snapshot(
            dashboard,
            provider_ids=("codex",),
            message_id=13,
            display=DisplayPreferences(55, (75, 90), False),
        )


def test_normalizer_keeps_at_most_three_windows_per_provider() -> None:
    from agentmeter_host.normalization import DisplayPreferences, normalize_dashboard_snapshot

    dashboard = dashboard_snapshot()
    first_window = dashboard["providers"][0]["windows"][0]
    dashboard["providers"][0]["windows"] = [
        {**first_window, "kind": f"window_{index}", "label": f"Window {index}"}
        for index in range(4)
    ]

    snapshot = normalize_dashboard_snapshot(
        dashboard,
        provider_ids=("codex",),
        message_id=14,
        display=DisplayPreferences(55, (75, 90), False),
    )

    assert [window["kind"] for window in snapshot["providers"][0]["windows"]] == [
        "window_0",
        "window_1",
        "window_2",
    ]


def test_normalizer_preserves_unknown_usage_as_null() -> None:
    from agentmeter_host.normalization import DisplayPreferences, normalize_dashboard_snapshot

    dashboard = dashboard_snapshot()
    dashboard["providers"][0]["windows"][0]["usedPercent"] = None

    snapshot = normalize_dashboard_snapshot(
        dashboard,
        provider_ids=("codex",),
        message_id=16,
        display=DisplayPreferences(55, (75, 90), False),
    )

    assert snapshot["providers"][0]["windows"][0]["usedPercent"] is None


def test_normalizer_bounds_provider_and_window_text_for_device() -> None:
    from agentmeter_host.normalization import DisplayPreferences, normalize_dashboard_snapshot

    dashboard = dashboard_snapshot()
    dashboard["providers"][0]["name"] = "Codex Individual Subscription"
    dashboard["providers"][0]["windows"][0]["kind"] = "Team Window (Monthly)"
    dashboard["providers"][0]["windows"][0]["label"] = "Rolling month for workspace"

    snapshot = normalize_dashboard_snapshot(
        dashboard,
        provider_ids=("codex",),
        message_id=17,
        display=DisplayPreferences(55, (75, 90), False),
    )

    provider = snapshot["providers"][0]
    assert provider["name"] == "Codex Individual Subscr"
    assert provider["windows"][0]["kind"] == "team_window_monthly"
    assert provider["windows"][0]["label"] == "Rolling month for works"


def test_normalized_snapshot_matches_device_schema() -> None:
    from agentmeter_host.normalization import DisplayPreferences, normalize_dashboard_snapshot
    from jsonschema import Draft202012Validator

    schema = json.loads((ROOT / "schemas/device-snapshot-v1.schema.json").read_text())
    snapshot = normalize_dashboard_snapshot(
        dashboard_snapshot(),
        provider_ids=("codex", "claude", "gemini"),
        message_id=18,
        display=DisplayPreferences(55, (75, 90), False),
    )

    Draft202012Validator(schema).validate(snapshot)


def test_normalizer_reports_malformed_v1_without_exposing_raw_fields() -> None:
    from agentmeter_host.normalization import (
        DisplayPreferences,
        NormalizationError,
        normalize_dashboard_snapshot,
    )

    dashboard = dashboard_snapshot()
    del dashboard["generatedAt"]
    dashboard["privateField"] = "must-not-appear"

    with pytest.raises(NormalizationError, match="dashboard schema version 1 is invalid") as error:
        normalize_dashboard_snapshot(
            dashboard,
            provider_ids=("codex",),
            message_id=19,
            display=DisplayPreferences(55, (75, 90), False),
        )

    assert "privateField" not in str(error.value)
    assert "must-not-appear" not in str(error.value)


@pytest.mark.parametrize("used_percent", [-1, 101])
def test_normalizer_rejects_usage_outside_device_contract(used_percent: int) -> None:
    from agentmeter_host.normalization import (
        DisplayPreferences,
        NormalizationError,
        normalize_dashboard_snapshot,
    )

    dashboard = dashboard_snapshot()
    dashboard["providers"][0]["windows"][0]["usedPercent"] = used_percent

    with pytest.raises(NormalizationError, match="usedPercent must be between 0 and 100"):
        normalize_dashboard_snapshot(
            dashboard,
            provider_ids=("codex",),
            message_id=20,
            display=DisplayPreferences(55, (75, 90), False),
        )


def test_normalizer_rejects_timestamp_before_device_epoch() -> None:
    from agentmeter_host.normalization import (
        DisplayPreferences,
        NormalizationError,
        normalize_dashboard_snapshot,
    )

    dashboard = dashboard_snapshot()
    dashboard["providers"][0]["windows"][0]["resetAt"] = "1960-01-01T00:00:00Z"

    with pytest.raises(NormalizationError, match="dashboard schema version 1 is invalid"):
        normalize_dashboard_snapshot(
            dashboard,
            provider_ids=("codex",),
            message_id=21,
            display=DisplayPreferences(55, (75, 90), False),
        )


def test_normalizer_requires_snapshot_generation_time() -> None:
    from agentmeter_host.normalization import (
        DisplayPreferences,
        NormalizationError,
        normalize_dashboard_snapshot,
    )

    dashboard = dashboard_snapshot()
    dashboard["generatedAt"] = None
    dashboard["providers"] = []

    with pytest.raises(NormalizationError, match="dashboard schema version 1 is invalid"):
        normalize_dashboard_snapshot(
            dashboard,
            provider_ids=("codex",),
            message_id=22,
            display=DisplayPreferences(55, (75, 90), False),
        )


def test_normalizer_selects_codex_claude_and_gemini_in_configured_order() -> None:
    from agentmeter_host.normalization import DisplayPreferences, normalize_dashboard_snapshot

    dashboard = dashboard_snapshot()
    template = dashboard["providers"][0]
    dashboard["providers"] = [
        {
            **copy.deepcopy(template),
            "id": provider_id,
            "name": provider_name,
        }
        for provider_id, provider_name in (
            ("gemini", "Gemini"),
            ("codex", "Codex"),
            ("claude", "Claude"),
        )
    ]

    snapshot = normalize_dashboard_snapshot(
        dashboard,
        provider_ids=("codex", "claude", "gemini"),
        message_id=23,
        display=DisplayPreferences(55, (75, 90), False),
    )

    assert [provider["id"] for provider in snapshot["providers"]] == [
        "codex",
        "claude",
        "gemini",
    ]
