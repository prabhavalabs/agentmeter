from __future__ import annotations

import sys
from collections.abc import Sequence
from pathlib import Path

from agentmeter_host.claude_probe import main as probe_main
from agentmeter_host.cli import main as cli_main


def dispatch(
    *,
    executable: str | None = None,
    arguments: Sequence[str] | None = None,
) -> int:
    executable_name = Path(executable or sys.argv[0]).name
    command_arguments = tuple(arguments if arguments is not None else sys.argv[1:])
    if executable_name == "agentmeter-claude-probe":
        return probe_main(command_arguments)
    return cli_main(command_arguments or ("run",))
