from __future__ import annotations

import asyncio
import os
import secrets
import shutil
import socket
import sys
from collections.abc import Mapping
from pathlib import Path

import httpx

_CODEXBAR_REQUEST_TIMEOUT_SECONDS = 60
_DASHBOARD_CLIENT_TIMEOUT_SECONDS = _CODEXBAR_REQUEST_TIMEOUT_SECONDS + 5
_PROVIDER_CLIENT_TIMEOUT_SECONDS = 30
_MAX_RESPONSE_BYTES = 65_536


class CodexBarError(RuntimeError):
    """CodexBar could not provide a usable dashboard snapshot."""


def build_serve_process(
    *,
    command: str,
    port: int,
    refresh_interval_seconds: int,
    token: str,
    base_environment: Mapping[str, str],
    claude_command: str | None = None,
    claude_shim_command: str | None = None,
) -> tuple[tuple[str, ...], dict[str, str]]:
    arguments = (
        command,
        "serve",
        "--host",
        "127.0.0.1",
        "--port",
        str(port),
        "--refresh-interval",
        str(refresh_interval_seconds),
        "--request-timeout",
        str(_CODEXBAR_REQUEST_TIMEOUT_SECONDS),
    )
    environment = dict(base_environment)
    environment["CODEXBAR_DASHBOARD_TOKEN"] = token
    if claude_command is not None and claude_shim_command is not None:
        environment["AGENTMETER_CLAUDE_CLI_PATH"] = claude_command
        environment["CLAUDE_CLI_PATH"] = claude_shim_command
    return arguments, environment


def _installed_claude_shim() -> str | None:
    command = shutil.which("agentmeter-claude-probe")
    if command is not None:
        return command
    sibling = Path(sys.executable).with_name("agentmeter-claude-probe")
    if sibling.is_file() and os.access(sibling, os.X_OK):
        return str(sibling)
    return None


def _installed_claude_command() -> str | None:
    configured = os.environ.get("CLAUDE_CLI_PATH")
    if configured is not None:
        return configured
    user_command = Path.home() / ".local" / "bin" / "claude"
    if user_command.is_file() and os.access(user_command, os.X_OK):
        return str(user_command)
    return shutil.which("claude")


class CodexBarClient:
    def __init__(
        self,
        *,
        port: int,
        token: str,
        transport: httpx.AsyncBaseTransport | None = None,
    ) -> None:
        self._base_url = f"http://127.0.0.1:{port}"
        self._token = token
        self._transport = transport

    async def fetch_snapshot(self) -> dict[str, object]:
        async with httpx.AsyncClient(
            base_url=self._base_url,
            headers={"Authorization": f"Bearer {self._token}"},
            timeout=_DASHBOARD_CLIENT_TIMEOUT_SECONDS,
            transport=self._transport,
        ) as client:
            try:
                response = await client.get("/dashboard/v1/snapshot")
            except httpx.HTTPError as error:
                raise CodexBarError("could not connect to the CodexBar dashboard") from error
            if not response.is_success:
                raise CodexBarError(
                    f"CodexBar rejected the dashboard request with HTTP {response.status_code}"
                )
            if len(response.content) > _MAX_RESPONSE_BYTES:
                raise CodexBarError("CodexBar response was larger than 65536 bytes")
            try:
                payload = response.json()
            except ValueError as error:
                raise CodexBarError("CodexBar did not return a valid JSON object") from error
            if not isinstance(payload, dict):
                raise CodexBarError("CodexBar did not return a valid JSON object")
            return payload

    async def fetch_provider_usages(
        self,
        provider_ids: tuple[str, ...],
    ) -> dict[str, dict[str, object] | None]:
        async with httpx.AsyncClient(
            base_url=self._base_url,
            headers={"Authorization": f"Bearer {self._token}"},
            timeout=_PROVIDER_CLIENT_TIMEOUT_SECONDS,
            transport=self._transport,
        ) as client:
            responses = await asyncio.gather(
                *(self._fetch_provider_usage(client, provider_id) for provider_id in provider_ids)
            )
        usages = dict(zip(provider_ids, responses, strict=True))
        if not any(payload is not None for payload in usages.values()):
            raise CodexBarError("CodexBar could not refresh any configured provider")
        return usages

    async def _fetch_provider_usage(
        self,
        client: httpx.AsyncClient,
        provider_id: str,
    ) -> dict[str, object] | None:
        try:
            response = await client.get("/usage", params={"provider": provider_id})
        except httpx.HTTPError:
            return None
        if not response.is_success or len(response.content) > _MAX_RESPONSE_BYTES:
            return None
        try:
            payload = response.json()
        except ValueError:
            return None
        if not isinstance(payload, list):
            return None
        return next(
            (
                item
                for item in payload
                if isinstance(item, dict) and item.get("provider") == provider_id
            ),
            None,
        )

    async def is_healthy(self) -> bool:
        try:
            async with httpx.AsyncClient(
                base_url=self._base_url,
                timeout=1,
                transport=self._transport,
            ) as client:
                response = await client.get("/health")
        except httpx.HTTPError:
            return False
        return response.is_success


def _available_loopback_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as listener:
        listener.bind(("127.0.0.1", 0))
        return int(listener.getsockname()[1])


class CodexBarServer:
    def __init__(
        self,
        *,
        command: str | None = None,
        claude_command: str | None = None,
        claude_shim_command: str | None = None,
        refresh_interval_seconds: int = 60,
        startup_timeout_seconds: float = 10,
    ) -> None:
        self._command = command
        self._claude_command = claude_command
        self._claude_shim_command = claude_shim_command
        self._refresh_interval_seconds = refresh_interval_seconds
        self._startup_timeout_seconds = startup_timeout_seconds
        self._process: asyncio.subprocess.Process | None = None

    async def __aenter__(self) -> CodexBarClient:
        command = self._command or shutil.which("codexbar")
        if command is None:
            raise CodexBarError(
                "CodexBar command was not found; install CodexBar and ensure codexbar is on PATH"
            )

        port = _available_loopback_port()
        token = secrets.token_hex(32)
        arguments, environment = build_serve_process(
            command=command,
            port=port,
            refresh_interval_seconds=self._refresh_interval_seconds,
            token=token,
            base_environment=os.environ,
            claude_command=self._claude_command or _installed_claude_command(),
            claude_shim_command=self._claude_shim_command or _installed_claude_shim(),
        )
        client = CodexBarClient(port=port, token=token)
        try:
            self._process = await asyncio.create_subprocess_exec(
                *arguments,
                env=environment,
                stdout=asyncio.subprocess.DEVNULL,
                stderr=asyncio.subprocess.DEVNULL,
            )
        except OSError as error:
            raise CodexBarError("could not start the CodexBar command") from error

        deadline = asyncio.get_running_loop().time() + self._startup_timeout_seconds
        try:
            while asyncio.get_running_loop().time() < deadline:
                if self._process.returncode is not None:
                    return_code = self._process.returncode
                    raise CodexBarError(
                        f"CodexBar server exited during startup with code {return_code}"
                    )
                if await client.is_healthy():
                    return client
                await asyncio.sleep(0.05)
            raise CodexBarError("CodexBar server did not become ready before the startup timeout")
        except BaseException:
            await self._stop()
            raise

    async def __aexit__(
        self,
        _exception_type: type[BaseException] | None,
        _exception: BaseException | None,
        _traceback: object,
    ) -> None:
        await self._stop()

    async def _stop(self) -> None:
        process = self._process
        self._process = None
        if process is None or process.returncode is not None:
            return
        try:
            process.terminate()
        except ProcessLookupError:
            return
        try:
            await asyncio.wait_for(process.wait(), timeout=2)
        except TimeoutError:
            process.kill()
            await process.wait()
