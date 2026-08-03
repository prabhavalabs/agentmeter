import asyncio
import json
import os

import httpx
import pytest
from helpers import dashboard_snapshot, provider_usage


@pytest.mark.asyncio
async def test_client_fetches_authenticated_dashboard_snapshot() -> None:
    from agentmeter_host.codexbar import CodexBarClient

    def handle(request: httpx.Request) -> httpx.Response:
        assert request.url == httpx.URL("http://127.0.0.1:46213/dashboard/v1/snapshot")
        assert request.headers["Authorization"] == "Bearer test-secret"
        return httpx.Response(200, json=dashboard_snapshot())

    client = CodexBarClient(
        port=46_213,
        token="test-secret",
        transport=httpx.MockTransport(handle),
    )

    assert await client.fetch_snapshot() == dashboard_snapshot()


@pytest.mark.asyncio
async def test_client_fetches_configured_provider_usage_concurrently() -> None:
    from agentmeter_host.codexbar import CodexBarClient

    requested: set[str] = set()
    both_started = asyncio.Event()

    async def handle(request: httpx.Request) -> httpx.Response:
        assert request.url.path == "/usage"
        assert request.headers["Authorization"] == "Bearer test-secret"
        provider_id = request.url.params["provider"]
        requested.add(provider_id)
        if len(requested) == 2:
            both_started.set()
        await asyncio.wait_for(both_started.wait(), timeout=1)
        return httpx.Response(200, json=[provider_usage(provider_id)])

    client = CodexBarClient(
        port=46_213,
        token="test-secret",
        transport=httpx.MockTransport(handle),
    )

    result = await client.fetch_provider_usages(("codex", "claude"))

    assert result == {
        "codex": provider_usage("codex"),
        "claude": provider_usage("claude"),
    }


@pytest.mark.asyncio
async def test_client_preserves_successful_provider_when_another_request_fails() -> None:
    from agentmeter_host.codexbar import CodexBarClient

    def handle(request: httpx.Request) -> httpx.Response:
        provider_id = request.url.params["provider"]
        if provider_id == "claude":
            return httpx.Response(504, json={"error": "deadline exceeded"})
        return httpx.Response(200, json=[provider_usage(provider_id)])

    client = CodexBarClient(
        port=46_213,
        token="test-secret",
        transport=httpx.MockTransport(handle),
    )

    assert await client.fetch_provider_usages(("codex", "claude")) == {
        "codex": provider_usage("codex"),
        "claude": None,
    }


@pytest.mark.asyncio
async def test_client_rejects_refresh_when_every_provider_request_fails() -> None:
    from agentmeter_host.codexbar import CodexBarClient, CodexBarError

    client = CodexBarClient(
        port=46_213,
        token="test-secret",
        transport=httpx.MockTransport(
            lambda _request: httpx.Response(504, json={"error": "deadline exceeded"})
        ),
    )

    with pytest.raises(CodexBarError, match="any configured provider"):
        await client.fetch_provider_usages(("codex", "claude"))


@pytest.mark.asyncio
async def test_client_timeout_outlasts_codexbar_request_deadline() -> None:
    from agentmeter_host.codexbar import CodexBarClient

    class DeadlineAwareTransport(httpx.AsyncBaseTransport):
        async def handle_async_request(self, request: httpx.Request) -> httpx.Response:
            read_timeout = request.extensions["timeout"]["read"]
            if read_timeout <= 60:
                raise httpx.ReadTimeout(
                    "client stopped before CodexBar's request deadline",
                    request=request,
                )
            return httpx.Response(200, json=dashboard_snapshot())

    client = CodexBarClient(
        port=46_213,
        token="test-secret",
        transport=DeadlineAwareTransport(),
    )

    assert await client.fetch_snapshot() == dashboard_snapshot()


@pytest.mark.asyncio
async def test_client_reports_http_failure_without_exposing_token() -> None:
    from agentmeter_host.codexbar import CodexBarClient, CodexBarError

    def handle(_request: httpx.Request) -> httpx.Response:
        return httpx.Response(401, json={"error": "unauthorized"})

    client = CodexBarClient(
        port=46_213,
        token="must-not-appear",
        transport=httpx.MockTransport(handle),
    )

    with pytest.raises(CodexBarError, match="HTTP 401") as error:
        await client.fetch_snapshot()

    assert "must-not-appear" not in str(error.value)


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "response",
    [
        httpx.Response(200, text="not-json"),
        httpx.Response(200, json=["not", "an", "object"]),
    ],
)
async def test_client_rejects_malformed_dashboard_response(response: httpx.Response) -> None:
    from agentmeter_host.codexbar import CodexBarClient, CodexBarError

    client = CodexBarClient(
        port=46_213,
        token="test-secret",
        transport=httpx.MockTransport(lambda _request: response),
    )

    with pytest.raises(CodexBarError, match="valid JSON object"):
        await client.fetch_snapshot()


@pytest.mark.asyncio
async def test_client_rejects_oversized_dashboard_response() -> None:
    from agentmeter_host.codexbar import CodexBarClient, CodexBarError

    client = CodexBarClient(
        port=46_213,
        token="test-secret",
        transport=httpx.MockTransport(
            lambda _request: httpx.Response(200, content=b"{" + b" " * 65_536 + b"}")
        ),
    )

    with pytest.raises(CodexBarError, match="larger than 65536 bytes"):
        await client.fetch_snapshot()


@pytest.mark.asyncio
async def test_client_reports_connection_failure() -> None:
    from agentmeter_host.codexbar import CodexBarClient, CodexBarError

    def fail(request: httpx.Request) -> httpx.Response:
        raise httpx.ConnectError("private low-level detail", request=request)

    client = CodexBarClient(
        port=46_213,
        token="test-secret",
        transport=httpx.MockTransport(fail),
    )

    with pytest.raises(CodexBarError, match="could not connect to the CodexBar dashboard"):
        await client.fetch_snapshot()


def test_serve_process_binds_loopback_and_passes_token_only_in_environment() -> None:
    from agentmeter_host.codexbar import build_serve_process

    arguments, environment = build_serve_process(
        command="/Applications/CodexBar.app/Contents/MacOS/codexbar",
        port=46_213,
        refresh_interval_seconds=60,
        token="environment-only-secret",
        base_environment={"PATH": "/usr/bin"},
    )

    assert arguments == (
        "/Applications/CodexBar.app/Contents/MacOS/codexbar",
        "serve",
        "--host",
        "127.0.0.1",
        "--port",
        "46213",
        "--refresh-interval",
        "60",
        "--request-timeout",
        "60",
    )
    assert "environment-only-secret" not in arguments
    assert environment == {
        "PATH": "/usr/bin",
        "CODEXBAR_DASHBOARD_TOKEN": "environment-only-secret",
    }


def test_serve_process_allows_slow_multi_provider_collection() -> None:
    from agentmeter_host.codexbar import build_serve_process

    arguments, _environment = build_serve_process(
        command="codexbar",
        port=46_213,
        refresh_interval_seconds=60,
        token="test-secret",
        base_environment={},
    )

    assert arguments[-2:] == ("--request-timeout", "60")


def test_serve_process_isolates_claude_cli_from_plugins() -> None:
    from agentmeter_host.codexbar import build_serve_process

    _arguments, environment = build_serve_process(
        command="codexbar",
        port=46_213,
        refresh_interval_seconds=60,
        token="test-secret",
        base_environment={"PATH": "/opt/homebrew/bin:/usr/bin"},
        claude_command="/opt/homebrew/bin/claude",
        claude_shim_command="/app/venv/bin/agentmeter-claude-probe",
    )

    assert environment["CLAUDE_CLI_PATH"] == "/app/venv/bin/agentmeter-claude-probe"
    assert environment["AGENTMETER_CLAUDE_CLI_PATH"] == "/opt/homebrew/bin/claude"


def test_claude_command_prefers_the_current_user_install(tmp_path, monkeypatch) -> None:
    from agentmeter_host.codexbar import _installed_claude_command

    user_command = tmp_path / ".local" / "bin" / "claude"
    user_command.parent.mkdir(parents=True)
    user_command.write_text("current user Claude")
    user_command.chmod(0o755)
    monkeypatch.setenv("HOME", str(tmp_path))
    monkeypatch.setattr(
        "agentmeter_host.codexbar.shutil.which",
        lambda name: "/opt/homebrew/bin/claude" if name == "claude" else None,
    )

    assert _installed_claude_command() == str(user_command)


@pytest.mark.asyncio
async def test_server_supervises_loopback_process_and_fetches_snapshot(
    tmp_path, monkeypatch
) -> None:
    from agentmeter_host.codexbar import CodexBarServer

    executable = tmp_path / "fake-codexbar"
    executable.write_text(
        """#!/usr/bin/env python3
import argparse
import json
import os
from http.server import BaseHTTPRequestHandler, HTTPServer

parser = argparse.ArgumentParser()
parser.add_argument("command")
parser.add_argument("--host", required=True)
parser.add_argument("--port", required=True, type=int)
parser.add_argument("--refresh-interval", required=True, type=int)
parser.add_argument("--request-timeout", required=True, type=int)
args = parser.parse_args()
snapshot = os.environ["FAKE_DASHBOARD"]
token = os.environ["CODEXBAR_DASHBOARD_TOKEN"]
with open(os.environ["FAKE_PID_FILE"], "w", encoding="utf-8") as pid_file:
    pid_file.write(str(os.getpid()))

class Handler(BaseHTTPRequestHandler):
    def send_json(self, status, body):
        encoded = body.encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)

    def do_GET(self):
        if self.path == "/health":
            self.send_json(200, '{"status":"ok"}')
        elif self.path == "/dashboard/v1/snapshot" and self.headers.get(
            "Authorization"
        ) == f"Bearer {token}":
            self.send_json(200, snapshot)
        else:
            self.send_json(401, '{"error":"unauthorized"}')

    def log_message(self, _format, *_args):
        pass

HTTPServer((args.host, args.port), Handler).serve_forever()
"""
    )
    executable.chmod(0o755)
    pid_file = tmp_path / "pid"
    monkeypatch.setenv("FAKE_DASHBOARD", json.dumps(dashboard_snapshot()))
    monkeypatch.setenv("FAKE_PID_FILE", str(pid_file))

    async with CodexBarServer(command=str(executable), startup_timeout_seconds=3) as client:
        assert await client.fetch_snapshot() == dashboard_snapshot()
        process_id = int(pid_file.read_text())
        os.kill(process_id, 0)

    with pytest.raises(ProcessLookupError):
        os.kill(process_id, 0)


@pytest.mark.asyncio
async def test_server_reports_command_that_cannot_be_started(tmp_path) -> None:
    from agentmeter_host.codexbar import CodexBarError, CodexBarServer

    missing_command = tmp_path / "missing-codexbar"

    with pytest.raises(CodexBarError, match="could not start the CodexBar command"):
        async with CodexBarServer(command=str(missing_command)):
            pass
