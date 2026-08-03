from __future__ import annotations

import asyncio
import copy
import json
from pathlib import Path
from typing import Any

from agentmeter_host import __version__
from agentmeter_host.control.events import ControlEvent, EventBroker
from agentmeter_host.ipc.protocol import IpcCommandError, IpcRequest
from agentmeter_host.ipc.server import IpcServer

SCENARIOS = (
    "connected-usb",
    "disconnected",
    "pairing",
    "provider-unavailable",
    "legacy",
    "settings-conflict",
)

_FIXTURE_ROOT = Path(__file__).parents[4] / "fixtures"


class FakeControlApi:
    def __init__(self, scenario: str) -> None:
        if scenario not in SCENARIOS:
            raise ValueError(f"unknown fake-server scenario {scenario!r}")
        self.scenario = scenario
        self.events = EventBroker()
        self.state = self._load("desktop-ipc-status-v1.json")["payload"]
        self.state["bridge"]["version"] = __version__
        self.settings_result = self._load("desktop-ipc-settings-v1.json")["payload"]
        self._apply_scenario()

    @staticmethod
    def _load(name: str) -> dict[str, Any]:
        return json.loads((_FIXTURE_ROOT / name).read_text(encoding="utf-8"))

    def _apply_scenario(self) -> None:
        connection = self.state["connection"]
        if self.scenario == "disconnected":
            connection.update(
                {
                    "phase": "stopped",
                    "rssi": None,
                    "managementAvailable": None,
                    "errorCode": None,
                }
            )
        elif self.scenario == "pairing":
            connection.update({"phase": "authenticating", "managementAvailable": None})
        elif self.scenario == "provider-unavailable":
            provider = self.state["providers"][0]
            provider.update(
                {"status": "unavailable", "windows": [], "errorCode": "providerUnavailable"}
            )
            self.state["bridge"]["providerHealth"][provider["id"]] = "unavailable"
        elif self.scenario == "legacy":
            connection["managementAvailable"] = False
            self.state["information"] = None
            self.state["telemetry"] = None
            self.state["settings"] = None
        elif self.scenario == "settings-conflict":
            self.settings_result["syncStatus"] = "waitingForDevice"

    async def handle_ipc(self, request: IpcRequest) -> dict[str, Any]:
        command = request.type
        if command == "hello":
            return {
                "bridgeVersion": __version__,
                "ipcSchemaVersion": 1,
                "capabilities": ["fakeServer"],
                "scenario": self.scenario,
            }
        if command == "status.get":
            return copy.deepcopy(self.state)
        if command == "device.scan":
            return {
                "peripherals": [
                    {
                        "identifier": "device-1",
                        "name": "AgentMeter-A1B2",
                        "rssi": -42,
                        "lastSeenEpoch": 1_785_607_200,
                    }
                ]
            }
        if command == "settings.get":
            return copy.deepcopy(self.settings_result)
        if command == "settings.patch" and self.scenario == "settings-conflict":
            raise IpcCommandError(
                "revisionConflict",
                "Device settings changed before this update was applied",
            )
        if command == "settings.patch":
            settings = self.settings_result["settings"]
            for key, value in request.payload.items():
                if key != "baseRevision" and key in settings:
                    settings[key] = value
            settings["revision"] += 1
            self.state["settings"] = copy.deepcopy(settings)
            self.settings_result["syncStatus"] = "synced"
            self._set_phase(self.state["connection"]["phase"])
            return copy.deepcopy(self.settings_result)
        if command in {"device.connect", "system.wake"}:
            self._set_phase("connected")
            return copy.deepcopy(self.state)
        if command in {"device.disconnect", "system.sleep"}:
            self._set_phase("stopped")
            return copy.deepcopy(self.state)
        if command == "device.forget":
            self._set_phase("stopped")
            self.state["connection"]["selectedDeviceId"] = None
            self.state["connection"]["selectedDeviceName"] = None
            return copy.deepcopy(self.state)
        if command == "device.refresh":
            return copy.deepcopy(self.state)
        if command in {
            "device.identify",
            "providers.refresh",
            "providers.update",
            "history.clear",
            "bridge.restart",
        }:
            return {}
        if command == "history.query":
            return {"usage": []}
        if command == "diagnostics.get":
            return {
                "bridgeVersion": __version__,
                "ipcSchemaVersion": 1,
                "phase": self.state["connection"]["phase"],
                "managementAvailable": self.state["connection"]["managementAvailable"],
                "providerHealth": self.state["bridge"]["providerHealth"],
                "recentEvents": [],
            }
        raise IpcCommandError("unsupportedCommand", "Fake server command is unsupported")

    def _set_phase(self, phase: str) -> None:
        self.state["revision"] += 1
        self.state["connection"]["phase"] = phase
        self.events.publish(ControlEvent("state.changed", copy.deepcopy(self.state)))


async def run_fake_server(
    scenario: str,
    path: Path,
    stop_event: asyncio.Event,
) -> None:
    api = FakeControlApi(scenario)
    server = IpcServer(path, api=api)
    await server.start()
    try:
        await stop_event.wait()
    finally:
        await server.close()
