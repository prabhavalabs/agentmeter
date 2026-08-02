from __future__ import annotations

import os
import plistlib
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any

LABEL = "com.prabhavalabs.agentmeter"


class ServiceError(RuntimeError):
    """The macOS background bridge could not be managed."""


@dataclass(frozen=True)
class ServicePaths:
    application_dir: Path
    executable: Path
    launch_agent: Path
    config: Path
    stdout_log: Path
    stderr_log: Path

    @classmethod
    def for_home(cls, home: Path) -> ServicePaths:
        application_dir = home / "Library/Application Support/AgentMeter"
        logs = application_dir / "logs"
        return cls(
            application_dir=application_dir,
            executable=application_dir / "venv/bin/agentmeter",
            launch_agent=home / "Library/LaunchAgents" / f"{LABEL}.plist",
            config=home / ".config/AgentMeter/config.toml",
            stdout_log=logs / "bridge.log",
            stderr_log=logs / "bridge-error.log",
        )


def launch_agent_document(paths: ServicePaths) -> dict[str, Any]:
    return {
        "Label": LABEL,
        "ProgramArguments": [
            str(paths.executable),
            "run",
            "--config",
            str(paths.config),
        ],
        "WorkingDirectory": str(paths.application_dir),
        "EnvironmentVariables": {
            "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin",
            "PYTHONUNBUFFERED": "1",
        },
        "RunAtLoad": True,
        "KeepAlive": True,
        "ThrottleInterval": 10,
        "ProcessType": "Background",
        "StandardOutPath": str(paths.stdout_log),
        "StandardErrorPath": str(paths.stderr_log),
    }


def install_service(source_root: Path, *, home: Path | None = None) -> ServicePaths:
    if sys.platform != "darwin":
        raise ServiceError("background installation is currently supported only on macOS")
    source_root = source_root.resolve()
    if (
        not (source_root / "pyproject.toml").is_file()
        or not (source_root / "config.example.toml").is_file()
    ):
        raise ServiceError("run service installation from the AgentMeter repository root")

    paths = ServicePaths.for_home((home or Path.home()).resolve())
    paths.application_dir.mkdir(parents=True, exist_ok=True)
    paths.stdout_log.parent.mkdir(parents=True, exist_ok=True)
    paths.launch_agent.parent.mkdir(parents=True, exist_ok=True)
    paths.config.parent.mkdir(parents=True, exist_ok=True)
    if not paths.config.exists():
        shutil.copyfile(source_root / "config.example.toml", paths.config)

    try:
        subprocess.run(
            [sys.executable, "-m", "venv", str(paths.application_dir / "venv")],
            check=True,
        )
        subprocess.run(
            [
                str(paths.application_dir / "venv/bin/python"),
                "-m",
                "pip",
                "install",
                "--disable-pip-version-check",
                "--upgrade",
                str(source_root),
            ],
            check=True,
        )
        temporary_plist = paths.launch_agent.with_suffix(".plist.tmp")
        with temporary_plist.open("wb") as plist_file:
            plistlib.dump(launch_agent_document(paths), plist_file, sort_keys=True)
        temporary_plist.replace(paths.launch_agent)

        domain = f"gui/{os.getuid()}"
        subprocess.run(
            ["launchctl", "bootout", f"{domain}/{LABEL}"],
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        subprocess.run(
            ["launchctl", "bootstrap", domain, str(paths.launch_agent)],
            check=True,
        )
        subprocess.run(
            ["launchctl", "kickstart", f"{domain}/{LABEL}"],
            check=True,
        )
    except (OSError, subprocess.CalledProcessError) as error:
        raise ServiceError("could not install the AgentMeter background bridge") from error
    return paths


def service_is_loaded(*, home: Path | None = None) -> bool:
    if sys.platform != "darwin":
        return False
    result = subprocess.run(
        ["launchctl", "print", f"gui/{os.getuid()}/{LABEL}"],
        check=False,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    return result.returncode == 0


def uninstall_service(*, home: Path | None = None) -> ServicePaths:
    paths = ServicePaths.for_home((home or Path.home()).resolve())
    if sys.platform != "darwin":
        raise ServiceError("background installation is currently supported only on macOS")
    domain = f"gui/{os.getuid()}"
    subprocess.run(
        ["launchctl", "bootout", f"{domain}/{LABEL}"],
        check=False,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    try:
        paths.launch_agent.unlink(missing_ok=True)
    except OSError as error:
        raise ServiceError("could not remove the AgentMeter launch agent") from error
    return paths
