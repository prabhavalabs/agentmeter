def test_frozen_entrypoint_dispatches_probe_from_executable_name(monkeypatch) -> None:
    from agentmeter_host import entrypoint

    calls = []
    monkeypatch.setattr(
        entrypoint,
        "probe_main",
        lambda arguments: calls.append(("probe", list(arguments))) or 0,
    )

    result = entrypoint.dispatch(
        executable="/Applications/AgentMeter.app/agentmeter-claude-probe",
        arguments=("usage",),
    )

    assert result == 0
    assert calls == [("probe", ["usage"])]


def test_frozen_entrypoint_starts_bridge_by_default(monkeypatch) -> None:
    from agentmeter_host import entrypoint

    calls = []
    monkeypatch.setattr(
        entrypoint,
        "cli_main",
        lambda arguments: calls.append(("bridge", list(arguments))) or 0,
    )

    result = entrypoint.dispatch(
        executable="/Applications/AgentMeter.app/AgentMeterBridge",
        arguments=(),
    )

    assert result == 0
    assert calls == [("bridge", ["run"])]
