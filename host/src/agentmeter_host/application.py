from __future__ import annotations

import asyncio
from collections.abc import Callable
from pathlib import Path
from typing import Any, Protocol

from agentmeter_host.config import (
    HostConfig,
    default_control_settings_path,
    default_history_path,
)
from agentmeter_host.control.controller import BridgeController
from agentmeter_host.control.events import EventBroker
from agentmeter_host.control.history import HistoryStore
from agentmeter_host.control.settings import ControlSettingsStore
from agentmeter_host.ipc.server import IpcServer, default_ipc_path
from agentmeter_host.transport.ble import BleakBackend, BleTransport


class ApplicationController(Protocol):
    restart_event: asyncio.Event

    async def run(self, stop_event: asyncio.Event) -> None: ...

    async def close(self) -> None: ...


class ApplicationServer(Protocol):
    async def start(self) -> None: ...

    async def close(self) -> None: ...


class BridgeApplication:
    def __init__(
        self,
        *,
        controller: ApplicationController,
        ipc_server: ApplicationServer,
    ) -> None:
        self._controller = controller
        self._ipc_server = ipc_server

    async def run(self, stop_event: asyncio.Event) -> None:
        active_stop = asyncio.Event()
        controller_task: asyncio.Task[None] | None = None
        wait_tasks: list[asyncio.Task[bool]] = []
        try:
            await self._ipc_server.start()
            controller_task = asyncio.create_task(self._controller.run(active_stop))
            wait_tasks = [
                asyncio.create_task(stop_event.wait()),
                asyncio.create_task(self._controller.restart_event.wait()),
            ]
            done, _pending = await asyncio.wait(
                [controller_task, *wait_tasks],
                return_when=asyncio.FIRST_COMPLETED,
            )
            if controller_task in done:
                await controller_task
            active_stop.set()
            if controller_task not in done:
                await controller_task
        finally:
            active_stop.set()
            for task in wait_tasks:
                task.cancel()
            if wait_tasks:
                await asyncio.gather(*wait_tasks, return_exceptions=True)
            if controller_task is not None and not controller_task.done():
                controller_task.cancel()
                await asyncio.gather(controller_task, return_exceptions=True)
            try:
                await self._ipc_server.close()
            finally:
                await self._controller.close()


def build_application(
    config: HostConfig,
    *,
    ipc_path: Path | None = None,
    settings_path: Path | None = None,
    history_path: Path | None = None,
    backend_factory: Callable[..., Any] = BleakBackend,
) -> BridgeApplication:
    backend = backend_factory(name_prefix=config.transport.device_name_prefix)
    transport = BleTransport(backend)
    events = EventBroker()
    settings_store = ControlSettingsStore(settings_path or default_control_settings_path())
    history = HistoryStore(history_path or default_history_path())
    controller = BridgeController(
        config,
        transport,
        settings_store,
        history,
        events,
    )
    server = IpcServer(ipc_path or default_ipc_path(), api=controller)
    return BridgeApplication(controller=controller, ipc_server=server)


async def run_desktop_application(
    config: HostConfig,
    *,
    ipc_path: Path | None = None,
    stop_event: asyncio.Event | None = None,
    application_factory: Callable[..., BridgeApplication] = build_application,
) -> None:
    application = application_factory(config, ipc_path=ipc_path)
    await application.run(stop_event or asyncio.Event())
