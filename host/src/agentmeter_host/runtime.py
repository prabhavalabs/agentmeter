from __future__ import annotations

import asyncio
import copy
from collections.abc import Callable
from typing import Any, Protocol

from agentmeter_host.alerts import AlertEngine
from agentmeter_host.config import HostConfig
from agentmeter_host.protocol import encode_device_snapshot
from agentmeter_host.snapshot import DeviceSnapshotCollector, collect_device_snapshot
from agentmeter_host.transport.ble import BleakBackend, BleTransport
from agentmeter_host.transport.serial import SerialTransport


class SnapshotTransport(Protocol):
    async def send(self, payload: bytes, *, message_id: int) -> None: ...

    async def close(self) -> None: ...


class ProviderHistory:
    """Retain recent valid windows when a provider refresh fails transiently."""

    def __init__(self, *, retention_seconds: int = 3_600) -> None:
        self._retention_seconds = retention_seconds
        self._last_good: dict[str, tuple[int, dict[str, Any]]] = {}

    def apply(self, snapshot: dict[str, Any]) -> dict[str, Any]:
        result = copy.deepcopy(snapshot)
        generated_at = result["generatedAtEpoch"]
        providers = result["providers"]
        for index, provider in enumerate(providers):
            provider_id = provider["id"]
            if provider["status"] == "ok" and provider["windows"]:
                self._last_good[provider_id] = (generated_at, copy.deepcopy(provider))
                continue
            cached = self._last_good.get(provider_id)
            if provider["status"] not in {"error", "unavailable"} or provider["windows"]:
                continue
            if cached is None or generated_at - cached[0] > self._retention_seconds:
                self._last_good.pop(provider_id, None)
                continue
            restored = copy.deepcopy(cached[1])
            restored["status"] = "stale"
            providers[index] = restored
        return result


class BridgeRuntime:
    def __init__(
        self,
        config: HostConfig,
        transport: SnapshotTransport,
        *,
        collector: Callable[..., Any] = collect_device_snapshot,
    ) -> None:
        self._config = config
        self._transport = transport
        self._collector = collector
        self._alerts = AlertEngine(config.display.alert_thresholds)
        self._provider_history = ProviderHistory()
        self.message_id = 0

    async def tick(self) -> None:
        message_id = self.message_id
        collected = self._provider_history.apply(
            await self._collector(self._config, message_id=message_id)
        )
        snapshot = self._alerts.apply(collected)
        payload = encode_device_snapshot(snapshot)
        await self._transport.send(payload, message_id=message_id)
        self.message_id = (message_id + 1) & 0xFFFF

    async def run(
        self,
        stop_event: asyncio.Event,
        *,
        wait: Callable[[float], Any] = asyncio.sleep,
        on_error: Callable[[Exception], None] | None = None,
    ) -> None:
        while not stop_event.is_set():
            try:
                await self.tick()
            except Exception as error:
                if on_error is not None:
                    on_error(error)
            if not stop_event.is_set():
                await wait(self._config.poll_interval_seconds)


def _configured_transport(config: HostConfig) -> SnapshotTransport:
    if config.transport.preferred == "serial":
        return SerialTransport(port=config.transport.serial_port or "")
    return BleTransport(BleakBackend(name_prefix=config.transport.device_name_prefix))


async def run_bridge(
    config: HostConfig,
    *,
    once: bool,
    transport_factory: Callable[[HostConfig], SnapshotTransport] = _configured_transport,
    collector: Callable[..., Any] | None = None,
    collector_session_factory: Callable[[HostConfig], Any] = DeviceSnapshotCollector,
    stop_event: asyncio.Event | None = None,
    wait: Callable[[float], Any] = asyncio.sleep,
    on_error: Callable[[Exception], None] | None = None,
) -> None:
    transport = transport_factory(config)
    try:

        async def execute(active_collector: Callable[..., Any]) -> None:
            runtime = BridgeRuntime(config, transport, collector=active_collector)
            if once:
                await runtime.tick()
            else:
                await runtime.run(
                    stop_event or asyncio.Event(),
                    wait=wait,
                    on_error=on_error,
                )

        if collector is not None:
            await execute(collector)
        else:
            async with collector_session_factory(config) as session:
                await execute(session.collect)
    finally:
        await transport.close()
