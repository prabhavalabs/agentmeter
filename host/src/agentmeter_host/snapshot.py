from __future__ import annotations

from collections.abc import Callable
from typing import Any

from agentmeter_host.codexbar import CodexBarServer
from agentmeter_host.config import HostConfig
from agentmeter_host.normalization import normalize_dashboard_snapshot


async def collect_device_snapshot(
    config: HostConfig,
    *,
    server_factory: Callable[..., Any] = CodexBarServer,
) -> dict[str, Any]:
    server = server_factory(refresh_interval_seconds=config.poll_interval_seconds)
    async with server as client:
        dashboard = await client.fetch_snapshot()
    return normalize_dashboard_snapshot(
        dashboard,
        provider_ids=config.provider_ids,
        message_id=0,
        display=config.display,
    )
