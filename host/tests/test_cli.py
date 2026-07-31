from agentmeter_host import __version__
from agentmeter_host.cli import main


def test_cli_prints_version(capsys) -> None:
    try:
        main(["--version"])
    except SystemExit as error:
        assert error.code == 0

    assert capsys.readouterr().out.strip() == f"AgentMeter {__version__}"


def test_cli_without_command_prints_help(capsys) -> None:
    assert main([]) == 0
    assert "Desktop bridge for the AgentMeter usage display." in capsys.readouterr().out
