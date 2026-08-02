from __future__ import annotations

from collections.abc import Callable
from typing import Any

from agentmeter_host.codexbar import CodexBarServer
from agentmeter_host.config import HostConfig
from agentmeter_host.normalization import normalize_dashboard_snapshot


class DeviceSnapshotCollector:
    """Keep one CodexBar server alive for the lifetime of a bridge run."""

    def __init__(
        self,
        config: HostConfig,
        *,
        server_factory: Callable[..., Any] = CodexBarServer,
    ) -> None:
        self._config = config
        self._server = server_factory(refresh_interval_seconds=config.poll_interval_seconds)
        self._client: Any | None = None

    async def __aenter__(self) -> DeviceSnapshotCollector:
        self._client = await self._server.__aenter__()
        return self

    async def __aexit__(self, *args: object) -> None:
        self._client = None
        await self._server.__aexit__(*args)

    async def collect(self, _config: HostConfig, *, message_id: int = 0) -> dict[str, Any]:
        if self._client is None:
            raise RuntimeError("device snapshot collector is not running")
        dashboard = await self._client.fetch_snapshot()
        return normalize_dashboard_snapshot(
            dashboard,
            provider_ids=self._config.provider_ids,
            message_id=message_id,
            display=self._config.display,
        )


async def collect_device_snapshot(
    config: HostConfig,
    *,
    message_id: int = 0,
    server_factory: Callable[..., Any] = CodexBarServer,
) -> dict[str, Any]:
    async with DeviceSnapshotCollector(config, server_factory=server_factory) as collector:
        return await collector.collect(config, message_id=message_id)
