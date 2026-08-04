import asyncio

import pytest
from agentmeter_host.application import BridgeApplication, run_desktop_application


class RecordingController:
    def __init__(self) -> None:
        self.restart_event = asyncio.Event()
        self.started = asyncio.Event()
        self.run_count = 0
        self.close_count = 0

    async def run(self, stop_event) -> None:
        self.run_count += 1
        self.started.set()
        await stop_event.wait()

    async def close(self) -> None:
        self.close_count += 1


class RecordingIpcServer:
    def __init__(self, *, start_failure=None) -> None:
        self.start_failure = start_failure
        self.start_count = 0
        self.close_count = 0

    async def start(self) -> None:
        self.start_count += 1
        if self.start_failure is not None:
            raise self.start_failure

    async def close(self) -> None:
        self.close_count += 1


@pytest.mark.asyncio
async def test_application_starts_one_controller_and_one_ipc_server() -> None:
    controller = RecordingController()
    server = RecordingIpcServer()
    application = BridgeApplication(controller=controller, ipc_server=server)
    stop = asyncio.Event()
    task = asyncio.create_task(application.run(stop))
    await controller.started.wait()
    stop.set()
    await task

    assert controller.run_count == 1
    assert server.start_count == 1
    assert server.close_count == 1
    assert controller.close_count == 1


@pytest.mark.asyncio
async def test_application_restart_request_stops_controller_cleanly() -> None:
    controller = RecordingController()
    server = RecordingIpcServer()
    application = BridgeApplication(controller=controller, ipc_server=server)
    task = asyncio.create_task(application.run(asyncio.Event()))
    await controller.started.wait()

    controller.restart_event.set()
    await task

    assert controller.close_count == 1
    assert server.close_count == 1


@pytest.mark.asyncio
async def test_application_cleans_controller_after_ipc_startup_failure() -> None:
    controller = RecordingController()
    server = RecordingIpcServer(start_failure=RuntimeError("socket unavailable"))
    application = BridgeApplication(controller=controller, ipc_server=server)

    with pytest.raises(RuntimeError, match="socket unavailable"):
        await application.run(asyncio.Event())

    assert controller.run_count == 0
    assert server.close_count == 1
    assert controller.close_count == 1


@pytest.mark.asyncio
async def test_community_bridge_stops_when_its_parent_application_exits() -> None:
    class RecordingApplication:
        def __init__(self) -> None:
            self.started = asyncio.Event()
            self.stopped = False

        async def run(self, stop_event: asyncio.Event) -> None:
            self.started.set()
            await stop_event.wait()
            self.stopped = True

    application = RecordingApplication()
    parent_pids = iter((2468, 1))

    await run_desktop_application(
        object(),
        parent_pid=2468,
        parent_pid_provider=lambda: next(parent_pids, 1),
        parent_check_interval_seconds=0,
        application_factory=lambda *_args, **_kwargs: application,
    )

    assert application.started.is_set()
    assert application.stopped is True
