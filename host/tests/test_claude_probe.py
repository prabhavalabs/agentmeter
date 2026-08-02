import json
import os
import subprocess
import sys
from pathlib import Path


def test_claude_probe_runs_real_cli_in_safe_mode(tmp_path: Path) -> None:
    invocation = tmp_path / "invocation.json"
    fake_claude = tmp_path / "claude"
    fake_claude.write_text(
        """#!/usr/bin/env python3
import json
import os
import sys

with open(os.environ["FAKE_CLAUDE_INVOCATION"], "w", encoding="utf-8") as output:
    json.dump(sys.argv[1:], output)
"""
    )
    fake_claude.chmod(0o755)
    environment = os.environ.copy()
    environment.update(
        {
            "AGENTMETER_CLAUDE_CLI_PATH": str(fake_claude),
            "FAKE_CLAUDE_INVOCATION": str(invocation),
        }
    )

    result = subprocess.run(
        [
            sys.executable,
            "-m",
            "agentmeter_host.claude_probe",
            "auth",
            "status",
            "--json",
        ],
        check=False,
        env=environment,
        capture_output=True,
        text=True,
    )

    assert result.returncode == 0, result.stderr
    assert json.loads(invocation.read_text()) == ["--safe-mode", "auth", "status", "--json"]
