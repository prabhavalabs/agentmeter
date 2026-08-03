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
    assert observed_providers == ["codex", "claude", "gemini", "cursor"]


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


def test_send_command_runs_one_live_bridge_tick(monkeypatch) -> None:
    import agentmeter_host.cli as cli

    calls = []

    async def fake_run_bridge(config, *, once, on_error):
        calls.append((config.provider_ids, once, on_error is not None))

    monkeypatch.setattr(cli, "run_bridge", fake_run_bridge, raising=False)

    assert main(["send", "--config", str(ROOT / "config.example.toml")]) == 0
    assert calls == [(("codex", "claude", "gemini", "cursor"), True, True)]


def test_run_command_starts_continuous_bridge(monkeypatch) -> None:
    import agentmeter_host.cli as cli

    calls = []

    async def fake_run_application(config, *, ipc_path, stop_event):
        calls.append((config.provider_ids, ipc_path, stop_event.is_set()))

    monkeypatch.setattr(cli, "run_desktop_application", fake_run_application, raising=False)

    ipc_path = Path("/tmp/agentmeter-test.sock")
    assert (
        main(
            [
                "run",
                "--config",
                str(ROOT / "config.example.toml"),
                "--ipc-path",
                str(ipc_path),
            ]
        )
        == 0
    )
    assert calls == [(("codex", "claude", "gemini", "cursor"), ipc_path, False)]


def test_ipc_path_command_prints_runtime_socket(monkeypatch, tmp_path, capsys) -> None:
    import agentmeter_host.cli as cli

    expected = tmp_path / "bridge.sock"
    monkeypatch.setattr(cli, "default_ipc_path", lambda: expected)

    assert main(["ipc-path"]) == 0
    assert capsys.readouterr().out.strip() == str(expected)


def test_service_install_uses_requested_source(monkeypatch, tmp_path, capsys) -> None:
    import agentmeter_host.cli as cli

    calls = []
    paths = type(
        "Paths",
        (),
        {
            "launch_agent": tmp_path / "agentmeter.plist",
            "config": tmp_path / "config.toml",
            "stderr_log": tmp_path / "error.log",
        },
    )()
    monkeypatch.setattr(
        cli,
        "install_service",
        lambda source: calls.append(source) or paths,
        raising=False,
    )

    assert main(["service", "install", "--source", str(tmp_path)]) == 0
    assert calls == [tmp_path]
    output = capsys.readouterr().out
    assert "Background bridge installed and started" in output
    assert str(paths.launch_agent) in output


def test_service_status_reports_loaded_launch_agent(monkeypatch, tmp_path, capsys) -> None:
    import agentmeter_host.cli as cli

    monkeypatch.setattr(cli, "service_is_loaded", lambda: True, raising=False)
    monkeypatch.setattr(
        cli,
        "ServicePaths",
        type(
            "ServicePaths",
            (),
            {
                "for_home": staticmethod(
                    lambda _home: type(
                        "Paths",
                        (),
                        {
                            "stderr_log": tmp_path / "bridge-error.log",
                            "ipc_socket": tmp_path / "bridge.sock",
                        },
                    )()
                )
            },
        ),
        raising=False,
    )
    monkeypatch.setattr(cli, "service_ipc_is_reachable", lambda _path: True)

    assert main(["service", "status"]) == 0
    output = capsys.readouterr().out
    assert "AgentMeter background bridge: running" in output
    assert "Desktop connection: ready" in output
