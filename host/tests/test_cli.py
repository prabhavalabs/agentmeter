import json
from pathlib import Path

from agentmeter_host import __version__
from agentmeter_host.cli import main
from helpers import device_snapshot

ROOT = Path(__file__).parents[2]


def test_cli_prints_version(capsys) -> None:
    try:
        main(["--version"])
    except SystemExit as error:
        assert error.code == 0

    assert capsys.readouterr().out.strip() == f"AgentMeter {__version__}"


def test_cli_without_command_prints_help(capsys) -> None:
    assert main([]) == 0
    assert "Desktop bridge for the AgentMeter usage display." in capsys.readouterr().out


def test_snapshot_command_prints_device_json(monkeypatch, capsys) -> None:
    import agentmeter_host.cli as cli

    observed_providers = []

    async def fake_collect(config):
        observed_providers.extend(config.provider_ids)
        return device_snapshot()

    monkeypatch.setattr(cli, "collect_device_snapshot", fake_collect, raising=False)

    assert main(["snapshot", "--config", str(ROOT / "config.example.toml")]) == 0
    assert json.loads(capsys.readouterr().out) == device_snapshot()
    assert observed_providers == ["codex", "claude", "gemini"]


def test_doctor_requires_codexbar_for_snapshot_collection(monkeypatch, capsys) -> None:
    import agentmeter_host.cli as cli

    monkeypatch.setattr(cli, "find_spec", lambda _name: object())
    monkeypatch.setattr(cli.shutil, "which", lambda _name: None)

    assert main(["doctor"]) == 1
    output = capsys.readouterr().out
    assert "[MISSING] CodexBar command" in output
    assert "Install CodexBar before running `agentmeter snapshot`." in output


def test_doctor_reports_missing_configuration(monkeypatch, tmp_path, capsys) -> None:
    import agentmeter_host.cli as cli

    config_path = tmp_path / "missing.toml"
    monkeypatch.setattr(cli, "default_config_path", lambda: config_path)
    monkeypatch.setattr(cli, "find_spec", lambda _name: object())
    monkeypatch.setattr(cli.shutil, "which", lambda _name: "/usr/local/bin/codexbar")

    assert main(["doctor"]) == 1
    output = capsys.readouterr().out
    assert "[MISSING] Configuration file" in output
    assert f"Copy config.example.toml to {config_path}." in output
