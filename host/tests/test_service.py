from pathlib import Path

from agentmeter_host.service import (
    LABEL,
    ServicePaths,
    launch_agent_document,
    rotate_service_logs,
)


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
        "--ipc-path",
        str(paths.ipc_socket),
    ]
    assert document["RunAtLoad"] is True
    assert document["KeepAlive"] is True
    assert document["EnvironmentVariables"]["PATH"].startswith("/opt/homebrew/bin:")
    assert document["StandardOutPath"] == str(paths.stdout_log)
    assert document["StandardErrorPath"] == str(paths.stderr_log)


def test_log_rotation_is_fixed_and_bounded(tmp_path: Path) -> None:
    paths = ServicePaths.for_home(tmp_path)
    paths.stdout_log.parent.mkdir(parents=True)
    paths.stdout_log.write_text("x" * 20)
    paths.stdout_log.with_name("bridge.log.1").write_text("older")

    rotate_service_logs(paths, maximum_bytes=10, backups=2)

    assert paths.stdout_log.with_name("bridge.log.1").read_text() == "x" * 20
    assert paths.stdout_log.with_name("bridge.log.2").read_text() == "older"
    assert not paths.stdout_log.exists()
