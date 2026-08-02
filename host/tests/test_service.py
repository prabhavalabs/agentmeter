from pathlib import Path

from agentmeter_host.service import LABEL, ServicePaths, launch_agent_document


def test_service_paths_keep_runtime_and_logs_in_user_library(tmp_path: Path) -> None:
    paths = ServicePaths.for_home(tmp_path)

    assert paths.application_dir == tmp_path / "Library/Application Support/AgentMeter"
    assert paths.executable == paths.application_dir / "venv/bin/agentmeter"
    assert paths.launch_agent == tmp_path / "Library/LaunchAgents" / f"{LABEL}.plist"
    assert paths.config == tmp_path / ".config/AgentMeter/config.toml"


def test_launch_agent_runs_bridge_at_login_with_homebrew_on_path(tmp_path: Path) -> None:
    paths = ServicePaths.for_home(tmp_path)

    document = launch_agent_document(paths)

    assert document["Label"] == LABEL
    assert document["ProgramArguments"] == [
        str(paths.executable),
        "run",
        "--config",
        str(paths.config),
    ]
    assert document["RunAtLoad"] is True
    assert document["KeepAlive"] is True
    assert document["EnvironmentVariables"]["PATH"].startswith("/opt/homebrew/bin:")
    assert document["StandardOutPath"] == str(paths.stdout_log)
    assert document["StandardErrorPath"] == str(paths.stderr_log)
