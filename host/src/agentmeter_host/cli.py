from __future__ import annotations

import argparse
import asyncio
import json
import shutil
import sys
from collections.abc import Sequence
from importlib.util import find_spec
from pathlib import Path

from platformdirs import user_config_path

from agentmeter_host import __version__
from agentmeter_host.codexbar import CodexBarError
from agentmeter_host.config import ConfigError, load_config
from agentmeter_host.normalization import NormalizationError
from agentmeter_host.protocol import DeviceProtocolError, encode_device_snapshot
from agentmeter_host.runtime import run_bridge
from agentmeter_host.service import (
    ServiceError,
    ServicePaths,
    install_service,
    service_is_loaded,
    uninstall_service,
)
from agentmeter_host.snapshot import collect_device_snapshot
from agentmeter_host.transport.ble import TransportError


def default_config_path() -> Path:
    return user_config_path("AgentMeter", "Prabhava Labs") / "config.toml"


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="agentmeter",
        description="Desktop bridge for the AgentMeter usage display.",
    )
    parser.add_argument("--version", action="version", version=f"AgentMeter {__version__}")
    subparsers = parser.add_subparsers(dest="command")
    subparsers.add_parser("doctor", help="Check the local development environment")
    snapshot_parser = subparsers.add_parser(
        "snapshot", help="Collect and print one device-ready snapshot"
    )
    snapshot_parser.add_argument(
        "--config",
        type=Path,
        default=default_config_path(),
        help="Path to the AgentMeter TOML configuration",
    )
    snapshot_parser.add_argument("--pretty", action="store_true", help="Indent the JSON output")
    for command, help_text in (
        ("send", "Collect and send one live snapshot to the display"),
        ("run", "Run the AgentMeter communication bridge continuously"),
    ):
        bridge_parser = subparsers.add_parser(command, help=help_text)
        bridge_parser.add_argument(
            "--config",
            type=Path,
            default=default_config_path(),
            help="Path to the AgentMeter TOML configuration",
        )
    service_parser = subparsers.add_parser(
        "service", help="Install or manage the macOS background bridge"
    )
    service_actions = service_parser.add_subparsers(dest="service_action", required=True)
    install_parser = service_actions.add_parser(
        "install", help="Install and start the bridge at login"
    )
    install_parser.add_argument(
        "--source",
        type=Path,
        default=Path.cwd(),
        help="AgentMeter repository root",
    )
    service_actions.add_parser("status", help="Show whether the bridge is running")
    service_actions.add_parser("uninstall", help="Stop and remove the launch agent")
    return parser


def run_doctor() -> int:
    config_path = default_config_path()
    try:
        load_config(config_path)
        config_ready = True
    except ConfigError:
        config_ready = False
    checks = [
        ("Python 3.11 or later", sys.version_info >= (3, 11)),
        ("Bluetooth library", find_spec("bleak") is not None),
        ("HTTP library", find_spec("httpx") is not None),
        ("CodexBar command", shutil.which("codexbar") is not None),
        ("Configuration file", config_ready),
    ]

    print(f"AgentMeter {__version__}")
    print(f"Configuration: {config_path}")
    for label, available in checks:
        marker = "OK" if available else "MISSING"
        print(f"[{marker}] {label}")

    required_ready = all(available for _, available in checks)
    if not checks[3][1]:
        print("Install CodexBar before running `agentmeter snapshot`.")
    if not config_ready:
        if config_path.is_file():
            print(f"Fix invalid settings in {config_path}.")
        else:
            print(f"Copy config.example.toml to {config_path}.")
    return 0 if required_ready else 1


def run_snapshot(config_path: Path, *, pretty: bool) -> int:
    try:
        config = load_config(config_path)
        snapshot = asyncio.run(collect_device_snapshot(config))
        payload = encode_device_snapshot(snapshot)
    except (ConfigError, CodexBarError, NormalizationError, DeviceProtocolError) as error:
        print(f"AgentMeter: {error}", file=sys.stderr)
        return 1

    if pretty:
        print(json.dumps(snapshot, ensure_ascii=False, indent=2))
    else:
        print(payload.decode("utf-8"))
    return 0


def run_bridge_command(config_path: Path, *, once: bool) -> int:
    try:
        config = load_config(config_path)

        def report(error: Exception) -> None:
            print(f"AgentMeter: {error}", file=sys.stderr)

        asyncio.run(run_bridge(config, once=once, on_error=report))
    except (
        ConfigError,
        CodexBarError,
        NormalizationError,
        DeviceProtocolError,
        TransportError,
    ) as error:
        print(f"AgentMeter: {error}", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        return 0
    return 0


def run_service_command(action: str, *, source: Path | None = None) -> int:
    try:
        if action == "install":
            paths = install_service(source or Path.cwd())
            print("Background bridge installed and started.")
            print(f"Launch agent: {paths.launch_agent}")
            print(f"Configuration: {paths.config}")
            print(f"Error log: {paths.stderr_log}")
            return 0
        if action == "uninstall":
            paths = uninstall_service()
            print("Background bridge stopped and launch agent removed.")
            print(f"Configuration and logs were kept in {paths.application_dir}.")
            return 0
        paths = ServicePaths.for_home(Path.home())
        loaded = service_is_loaded()
        print(f"AgentMeter background bridge: {'running' if loaded else 'stopped'}")
        print(f"Error log: {paths.stderr_log}")
        return 0 if loaded else 1
    except ServiceError as error:
        print(f"AgentMeter: {error}", file=sys.stderr)
        return 1


def main(argv: Sequence[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)

    if args.command == "doctor":
        return run_doctor()
    if args.command == "snapshot":
        return run_snapshot(args.config, pretty=args.pretty)
    if args.command == "send":
        return run_bridge_command(args.config, once=True)
    if args.command == "run":
        return run_bridge_command(args.config, once=False)
    if args.command == "service":
        return run_service_command(
            args.service_action,
            source=getattr(args, "source", None),
        )

    parser.print_help()
    return 0
