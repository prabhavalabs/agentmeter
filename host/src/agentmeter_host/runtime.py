from __future__ import annotations

import asyncio
from collections.abc import Callable
from typing import Any, Protocol

from agentmeter_host.alerts import AlertEngine
from agentmeter_host.config import HostConfig
from agentmeter_host.protocol import encode_device_snapshot
from agentmeter_host.snapshot import collect_device_snapshot
from agentmeter_host.transport.ble import BleakBackend, BleTransport
from agentmeter_host.transport.serial import SerialTransport


class SnapshotTransport(Protocol):
    async def send(self, payload: bytes, *, message_id: int) -> None: ...

    async def close(self) -> None: ...


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
        self.message_id = 0

    async def tick(self) -> None:
        message_id = self.message_id
        collected = await self._collector(self._config, message_id=message_id)
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
    collector: Callable[..., Any] = collect_device_snapshot,
    stop_event: asyncio.Event | None = None,
    wait: Callable[[float], Any] = asyncio.sleep,
    on_error: Callable[[Exception], None] | None = None,
) -> None:
    transport = transport_factory(config)
    runtime = BridgeRuntime(config, transport, collector=collector)
    try:
        if once:
            await runtime.tick()
        else:
            await runtime.run(
                stop_event or asyncio.Event(),
                wait=wait,
                on_error=on_error,
            )
    finally:
        await transport.close()
