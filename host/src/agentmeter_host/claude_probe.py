from __future__ import annotations

import os
import sys
from collections.abc import Sequence
from pathlib import Path

_REAL_CLAUDE_ENVIRONMENT_KEY = "AGENTMETER_CLAUDE_CLI_PATH"


def main(argv: Sequence[str] | None = None) -> int:
    command = os.environ.get(_REAL_CLAUDE_ENVIRONMENT_KEY)
    if command is None:
        print("AgentMeter: Claude CLI path is unavailable", file=sys.stderr)
        return 2

    executable = Path(command)
    if (
        not executable.is_absolute()
        or not executable.is_file()
        or not os.access(executable, os.X_OK)
    ):
        print("AgentMeter: Claude CLI path is not executable", file=sys.stderr)
        return 2

    arguments = [str(executable), "--safe-mode", *(argv if argv is not None else sys.argv[1:])]
    try:
        os.execv(executable, arguments)
    except OSError:
        print("AgentMeter: could not start the Claude CLI", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
