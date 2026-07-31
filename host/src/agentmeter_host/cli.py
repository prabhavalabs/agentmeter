from __future__ import annotations

import argparse
import shutil
import sys
from collections.abc import Sequence
from importlib.util import find_spec

from platformdirs import user_config_path

from agentmeter_host import __version__


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="agentmeter",
        description="Desktop bridge for the AgentMeter usage display.",
    )
    parser.add_argument("--version", action="version", version=f"AgentMeter {__version__}")
    subparsers = parser.add_subparsers(dest="command")
    subparsers.add_parser("doctor", help="Check the local development environment")
    return parser


def run_doctor() -> int:
    config_path = user_config_path("AgentMeter", "Prabhava Labs") / "config.toml"
    checks = [
        ("Python 3.11 or later", sys.version_info >= (3, 11)),
        ("Bluetooth library", find_spec("bleak") is not None),
        ("HTTP library", find_spec("httpx") is not None),
        ("CodexBar command", shutil.which("codexbar") is not None),
    ]

    print(f"AgentMeter {__version__}")
    print(f"Configuration: {config_path}")
    for label, available in checks:
        marker = "OK" if available else "MISSING"
        print(f"[{marker}] {label}")

    required_ready = all(available for _, available in checks[:3])
    if not checks[-1][1]:
        print("CodexBar is optional until the data-source phase is implemented.")
    return 0 if required_ready else 1


def main(argv: Sequence[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)

    if args.command == "doctor":
        return run_doctor()

    parser.print_help()
    return 0
