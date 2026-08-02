from agentmeter_host.alerts import AlertEngine


def snapshot(*usages: tuple[str, str, int], generated_at: int = 1_700_000_000) -> dict:
    providers: dict[str, list[dict]] = {}
    for provider_id, window_kind, used_percent in usages:
        providers.setdefault(provider_id, []).append(
            {
                "kind": window_kind,
                "label": window_kind.title(),
                "usedPercent": used_percent,
                "resetAtEpoch": generated_at + 3600,
            }
        )
    return {
        "generatedAtEpoch": generated_at,
        "providers": [
            {
                "id": provider_id,
                "name": provider_id.title(),
                "status": "ok",
                "windows": windows,
            }
            for provider_id, windows in providers.items()
        ],
        "event": None,
    }


def test_emits_highest_crossed_threshold_with_stable_private_id() -> None:
    engine = AlertEngine((75, 90))

    result = engine.apply(snapshot(("claude", "weekly", 91)))

    assert result["event"] == {
        "id": "threshold:claude:weekly:90",
        "kind": "threshold",
        "level": "critical",
        "expiresAtEpoch": 1_700_000_090,
    }


def test_deduplicates_until_usage_falls_below_threshold() -> None:
    engine = AlertEngine((75, 90))

    assert engine.apply(snapshot(("codex", "weekly", 80)))["event"] is not None
    assert engine.apply(snapshot(("codex", "weekly", 82)))["event"] is None
    assert engine.apply(snapshot(("codex", "weekly", 20)))["event"] is None
    assert engine.apply(snapshot(("codex", "weekly", 76)))["event"] is not None


def test_queues_simultaneous_alerts_by_severity() -> None:
    engine = AlertEngine((75, 90))

    first = engine.apply(
        snapshot(
            ("codex", "weekly", 80),
            ("claude", "weekly", 95),
        )
    )
    second = engine.apply(
        snapshot(
            ("codex", "weekly", 80),
            ("claude", "weekly", 95),
            generated_at=1_700_000_060,
        )
    )

    assert first["event"]["id"] == "threshold:claude:weekly:90"
    assert first["event"]["level"] == "critical"
    assert second["event"]["id"] == "threshold:codex:weekly:75"
    assert second["event"]["expiresAtEpoch"] == 1_700_000_150


def test_ignores_unknown_usage_and_unhealthy_providers() -> None:
    engine = AlertEngine((75, 90))
    input_snapshot = snapshot(("codex", "weekly", 95))
    input_snapshot["providers"][0]["status"] = "error"
    input_snapshot["providers"][0]["windows"][0]["usedPercent"] = None

    assert engine.apply(input_snapshot)["event"] is None
