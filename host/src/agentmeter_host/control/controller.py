from __future__ import annotations

import asyncio
import random
import time
from collections import deque
from collections.abc import AsyncIterator, Awaitable, Callable
from contextlib import suppress
from dataclasses import replace
from typing import Any, Protocol

from agentmeter_host import __version__
from agentmeter_host.alerts import AlertEngine
from agentmeter_host.config import HostConfig
from agentmeter_host.control.events import ControlEvent, EventBroker
from agentmeter_host.control.history import HistoryError, HistoryStore
from agentmeter_host.control.models import (
    BridgeStatus,
    ConnectionPhase,
    ConnectionState,
    ControlState,
    DeviceInformation,
    DeviceSettings,
    DeviceTelemetry,
    ProviderSummary,
    ProviderWindow,
)
from agentmeter_host.control.settings import (
    ControlSettingsError,
    ControlSettingsStore,
    PendingSettingsPatch,
)
from agentmeter_host.ipc.protocol import IpcCommandError, IpcRequest
from agentmeter_host.protocol import encode_device_snapshot
from agentmeter_host.runtime import ProviderHistory
from agentmeter_host.snapshot import DeviceSnapshotCollector
from agentmeter_host.transport.ble import ConnectedPeripheral, TransportError
from agentmeter_host.transport.management import ManagementError, ManagementProtocolError


def _required_string(document: dict[str, Any], key: str, *, maximum: int = 128) -> str:
    value = document.get(key)
    if not isinstance(value, str) or not 1 <= len(value) <= maximum:
        raise ManagementProtocolError(f"{key} is invalid")
    return value


def _required_bool(document: dict[str, Any], key: str) -> bool:
    value = document.get(key)
    if not isinstance(value, bool):
        raise ManagementProtocolError(f"{key} is invalid")
    return value


def _required_int(
    document: dict[str, Any],
    key: str,
    *,
    minimum: int = 0,
    maximum: int = 0xFFFFFFFF,
) -> int:
    value = document.get(key)
    if isinstance(value, bool) or not isinstance(value, int) or not minimum <= value <= maximum:
        raise ManagementProtocolError(f"{key} is invalid")
    return value


def _optional_bool(document: dict[str, Any], key: str) -> bool | None:
    value = document.get(key)
    if value is not None and not isinstance(value, bool):
        raise ManagementProtocolError(f"{key} is invalid")
    return value


def _optional_int(
    document: dict[str, Any],
    key: str,
    *,
    minimum: int = 0,
    maximum: int = 0xFFFFFFFF,
) -> int | None:
    value = document.get(key)
    invalid_type = isinstance(value, bool) or not isinstance(value, int)
    if value is not None and (invalid_type or not minimum <= value <= maximum):
        raise ManagementProtocolError(f"{key} is invalid")
    return value


class ManagedSnapshotTransport(Protocol):
    management_available: bool

    async def scan(self): ...

    async def connect(self, identifier: str | None = None): ...

    async def send(self, payload: bytes, *, message_id: int) -> None: ...

    async def request(self, request: dict[str, Any]) -> dict[str, Any]: ...

    def device_events(self) -> AsyncIterator[dict[str, Any]]: ...

    async def disconnect(self) -> None: ...

    async def close(self) -> None: ...


class BridgeController:
    def __init__(
        self,
        config: HostConfig,
        transport: ManagedSnapshotTransport,
        settings_store: ControlSettingsStore,
        history: HistoryStore,
        events: EventBroker,
        collector_session_factory: Callable[[HostConfig], Any] = DeviceSnapshotCollector,
        clock: Callable[[], float] = time.time,
        monotonic: Callable[[], float] = time.monotonic,
        sleep: Callable[[float], Awaitable[None]] = asyncio.sleep,
        jitter: Callable[[float], float] | None = None,
    ) -> None:
        self._base_config = config
        self._transport = transport
        self._settings_store = settings_store
        self._history = history
        self.events = events
        self._collector_session_factory = collector_session_factory
        self._clock = clock
        self._monotonic = monotonic
        self._sleep = sleep
        self._jitter = jitter or (lambda delay: random.uniform(0, delay * 0.2))
        self._host_settings = settings_store.load(config)
        self._provider_history = ProviderHistory()
        self._alerts = AlertEngine(config.display.alert_thresholds)
        self._connection_lock = asyncio.Lock()
        self._refresh_lock = asyncio.Lock()
        self._provider_refresh_task: asyncio.Task[None] | None = None
        self._provider_refresh_send_requested = False
        self._reconnect_needed = asyncio.Event()
        self._latest_snapshot: dict[str, Any] | None = None
        self._next_snapshot_id = 0
        self._next_management_id = 1
        self._manual_disconnect = False
        self._sleeping = False
        self._closed = False
        self.restart_requested = False
        self.restart_event = asyncio.Event()
        self._diagnostic_events: deque[dict[str, object]] = deque(maxlen=50)
        self.state = ControlState(
            connection=ConnectionState(
                selected_device_id=self._host_settings.selected_device_id,
                selected_device_name=self._host_settings.selected_device_name,
            ),
            bridge=BridgeStatus(
                version=__version__,
                configured_provider_ids=self._host_settings.provider_ids,
                poll_interval_seconds=self._host_settings.poll_interval_seconds,
            ),
        )

    def _active_config(self) -> HostConfig:
        return replace(
            self._base_config,
            provider_ids=self._host_settings.provider_ids,
            poll_interval_seconds=self._host_settings.poll_interval_seconds,
        )

    def _commit(self, event_type: str) -> None:
        self.state = replace(self.state, revision=self.state.revision + 1)
        now = int(self._clock())
        self._diagnostic_events.append(
            {"type": event_type, "revision": self.state.revision, "occurredAtEpoch": now}
        )
        self.events.publish(
            ControlEvent(
                event_type,
                self.state.to_document(),
                occurred_at_epoch=now,
            )
        )

    def _set_connection(
        self,
        phase: ConnectionPhase,
        *,
        error_code: str | None = None,
        next_retry_epoch: int | None = None,
        peripheral: ConnectedPeripheral | None = None,
        management_available: bool | None = None,
    ) -> None:
        previous = self.state.connection
        if not isinstance(previous, ConnectionState):
            previous = ConnectionState()
        summary = peripheral.peripheral if peripheral is not None else None
        connection = replace(
            previous,
            phase=phase,
            selected_device_id=(
                summary.identifier if summary is not None else previous.selected_device_id
            ),
            selected_device_name=(
                summary.name if summary is not None else previous.selected_device_name
            ),
            rssi=summary.rssi if summary is not None else previous.rssi,
            management_available=(
                peripheral.management_available
                if peripheral is not None
                else management_available
                if management_available is not None
                else previous.management_available
            ),
            next_retry_epoch=next_retry_epoch,
            error_code=error_code,
        )
        self.state = replace(self.state, connection=connection)
        self._history.record_connection(int(self._clock()), phase.value, error_code)
        self._commit("connection.changed")

    async def scan(self) -> list[dict[str, object]]:
        scanning_while_connected = self.state.connection.phase is ConnectionPhase.CONNECTED
        if not scanning_while_connected:
            self._set_connection(ConnectionPhase.SEARCHING)
        try:
            peripherals = tuple(await self._transport.scan())
        except TransportError as error:
            if self.state.connection.phase is ConnectionPhase.SEARCHING:
                self._set_connection(
                    ConnectionPhase.BLUETOOTH_UNAVAILABLE,
                    error_code=self._transport_error_code(error),
                )
            raise IpcCommandError(self._transport_error_code(error), str(error)) from error
        self.state = replace(self.state, peripherals=peripherals)
        self._commit("discovery.changed")
        if self.state.connection.phase is ConnectionPhase.SEARCHING:
            self._set_connection(ConnectionPhase.STOPPED)
        return [item.to_document() for item in peripherals]

    async def connect(self, identifier: str | None = None) -> None:
        async with self._connection_lock:
            self._manual_disconnect = False
            self._sleeping = False
            selected = identifier or self._host_settings.selected_device_id
            self._set_connection(ConnectionPhase.CONNECTING)
            try:
                peripheral = await self._transport.connect(selected)
                self._set_connection(
                    ConnectionPhase.AUTHENTICATING,
                    peripheral=peripheral,
                    management_available=self._transport.management_available,
                )
                self._remember_peripheral(selected, peripheral)
                self._set_connection(
                    ConnectionPhase.SYNCHRONIZING,
                    peripheral=peripheral,
                    management_available=self._transport.management_available,
                )
                if self._transport.management_available:
                    await self._synchronize_device()
                else:
                    self.state = replace(
                        self.state,
                        information=None,
                        telemetry=None,
                        settings=None,
                    )
                if self._latest_snapshot is None:
                    with suppress(IpcCommandError):
                        await self.refresh_providers(send_to_device=False)
                if self._latest_snapshot is not None:
                    await self._send_latest_snapshot()
            except (ManagementError, ManagementProtocolError, TransportError) as error:
                code = self._transport_error_code(error)
                unavailable_codes = {
                    "bluetoothPermissionDenied",
                    "bluetoothPoweredOff",
                    "bluetoothUnavailable",
                }
                phase = (
                    ConnectionPhase.BLUETOOTH_UNAVAILABLE
                    if code in unavailable_codes
                    else ConnectionPhase.RETRYING
                )
                self._set_connection(phase, error_code=code)
                raise IpcCommandError(code, str(error)) from error
            now = int(self._clock())
            self.state = replace(
                self.state,
                bridge=replace(self.state.bridge, last_device_sync_epoch=now),
            )
            self._set_connection(
                ConnectionPhase.CONNECTED,
                peripheral=peripheral,
                management_available=self._transport.management_available,
            )

    def _remember_peripheral(
        self,
        requested_identifier: str | None,
        peripheral: ConnectedPeripheral | None,
    ) -> None:
        identifier = (
            peripheral.peripheral.identifier if peripheral is not None else requested_identifier
        )
        name = (
            peripheral.peripheral.name
            if peripheral is not None
            else self._host_settings.selected_device_name
        )
        if identifier is None:
            return
        self._host_settings = replace(
            self._host_settings,
            selected_device_id=identifier,
            selected_device_name=name,
        )
        self._settings_store.save(self._host_settings)

    async def disconnect(self, *, manual: bool = True) -> None:
        if manual:
            self._manual_disconnect = True
        await self._transport.disconnect()
        self._set_connection(ConnectionPhase.STOPPED)

    async def forget(self) -> None:
        if self._is_connected() and self._transport.management_available:
            await self._device_request("device.forget")
        await self.disconnect()
        self._host_settings = replace(
            self._host_settings,
            selected_device_id=None,
            selected_device_name=None,
            pending_device_patch=None,
        )
        self._settings_store.save(self._host_settings)
        connection = self.state.connection
        if isinstance(connection, ConnectionState):
            self.state = replace(
                self.state,
                connection=replace(
                    connection,
                    selected_device_id=None,
                    selected_device_name=None,
                    rssi=None,
                    management_available=None,
                ),
                information=None,
                telemetry=None,
                settings=None,
            )
            self._commit("device.forgotten")

    async def identify(self) -> None:
        self._require_management_connection()
        await self._device_request("device.identify")

    async def refresh_device(self) -> None:
        self._require_management_connection()
        result = await self._device_request("device.get")
        self._apply_device_state(result.get("payload"))

    async def refresh_providers(self, *, send_to_device: bool = True) -> None:
        async with self._refresh_lock:
            task = self._provider_refresh_task
            if task is None or task.done():
                task = asyncio.create_task(self._refresh_provider_state())
                self._provider_refresh_task = task
                self._provider_refresh_send_requested = False
            self._provider_refresh_send_requested |= send_to_device
        try:
            await asyncio.shield(task)
        finally:
            async with self._refresh_lock:
                if self._provider_refresh_task is task and task.done():
                    should_send = self._provider_refresh_send_requested
                    self._provider_refresh_task = None
                    self._provider_refresh_send_requested = False
                else:
                    should_send = False
        if should_send and self._is_connected():
            try:
                await self._send_latest_snapshot()
            except TransportError as error:
                await self._unexpected_disconnect(self._transport_error_code(error))

    async def _refresh_provider_state(self) -> None:
        config = self._active_config()
        message_id = self._next_snapshot_id
        try:
            async with self._collector_session_factory(config) as session:
                collected = await session.collect(config, message_id=message_id)
            snapshot = self._alerts.apply(self._provider_history.apply(collected))
        except Exception as error:
            self.state = replace(
                self.state,
                bridge=replace(
                    self.state.bridge,
                    last_error_code="providerRefreshFailed",
                ),
            )
            self._commit("providers.changed")
            raise IpcCommandError(
                "providerRefreshFailed",
                "Provider usage could not be refreshed",
            ) from error
        self._next_snapshot_id = (message_id + 1) & 0xFFFF
        self._latest_snapshot = snapshot
        self._history.record_snapshot(snapshot)
        providers = self._provider_summaries(snapshot)
        provider_health = tuple((provider.identifier, provider.status) for provider in providers)
        refreshed_at = int(snapshot["generatedAtEpoch"])
        self.state = replace(
            self.state,
            providers=providers,
            bridge=replace(
                self.state.bridge,
                last_provider_refresh_epoch=refreshed_at,
                last_error_code=None,
                provider_health=provider_health,
            ),
        )
        self._commit("providers.changed")

    async def patch_settings(self, payload: dict[str, Any]) -> dict[str, object]:
        base_revision = payload.get("baseRevision")
        values = {key: value for key, value in payload.items() if key != "baseRevision"}
        try:
            pending = PendingSettingsPatch(base_revision, values)
        except ControlSettingsError as error:
            raise IpcCommandError("invalidPayload", str(error)) from error
        self._host_settings = self._settings_store.save_pending_patch(
            self._host_settings,
            pending,
        )
        if not self._is_connected() or not self._transport.management_available:
            return {"syncStatus": "waitingForDevice", "settings": self._settings_document()}
        try:
            result = await self._device_request("settings.patch", payload)
        except ManagementError as error:
            if error.status == "revisionConflict":
                self._apply_device_settings(error.result.get("payload"))
                raise IpcCommandError(
                    "revisionConflict",
                    "Device settings changed before this update was applied",
                ) from error
            raise IpcCommandError(error.status, str(error)) from error
        self._apply_device_settings(result.get("payload"))
        self._host_settings = self._settings_store.clear_pending_patch(self._host_settings)
        return {"syncStatus": "synced", "settings": self._settings_document()}

    async def _synchronize_device(self) -> None:
        device = await self._device_request("device.get")
        self._apply_device_state(device.get("payload"), publish=False)
        settings = await self._device_request("settings.get")
        self._apply_device_settings(settings.get("payload"), publish=False)
        pending = self._host_settings.pending_device_patch
        if (
            pending is not None
            and self.state.settings is not None
            and pending.base_revision == self.state.settings.revision
        ):
            patch = {"baseRevision": pending.base_revision, **pending.values}
            try:
                result = await self._device_request("settings.patch", patch)
            except ManagementError as error:
                if error.status == "revisionConflict":
                    self._apply_device_settings(error.result.get("payload"), publish=False)
                else:
                    raise
            else:
                self._apply_device_settings(result.get("payload"), publish=False)
                clear_pending = self._settings_store.clear_pending_patch
                self._host_settings = clear_pending(self._host_settings)
        self._commit("device.changed")

    async def _send_latest_snapshot(self) -> None:
        if self._latest_snapshot is None:
            return
        message_id = int(self._latest_snapshot["messageId"])
        await self._transport.send(
            encode_device_snapshot(self._latest_snapshot),
            message_id=message_id,
        )
        now = int(self._clock())
        self.state = replace(
            self.state,
            bridge=replace(self.state.bridge, last_device_sync_epoch=now),
        )

    async def _device_request(
        self,
        command: str,
        payload: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        request_id = self._next_management_id
        self._next_management_id = 1 if request_id == 65_535 else request_id + 1
        return await self._transport.request(
            {
                "schemaVersion": 1,
                "requestId": request_id,
                "type": command,
                "payload": payload or {},
            }
        )

    def _apply_device_state(self, payload: object, *, publish: bool = True) -> None:
        if not isinstance(payload, dict):
            raise ManagementProtocolError("device state payload is invalid")
        information = self._parse_information(payload.get("information"))
        telemetry = self._parse_telemetry(payload.get("telemetry"))
        settings = self._parse_settings(payload.get("settings"))
        self.state = replace(
            self.state,
            information=information,
            telemetry=telemetry,
            settings=settings,
        )
        self._record_telemetry(telemetry)
        if publish:
            self._commit("device.changed")

    def _apply_device_settings(self, payload: object, *, publish: bool = True) -> None:
        settings = self._parse_settings(payload)
        self.state = replace(self.state, settings=settings)
        if publish:
            self._commit("settings.changed")

    def _record_telemetry(self, telemetry: DeviceTelemetry) -> None:
        self._history.record_telemetry(
            int(self._clock()),
            power_source=telemetry.power_source,
            battery_percent=telemetry.battery_percent,
            battery_voltage_mv=telemetry.battery_voltage_mv,
            vbus_voltage_mv=telemetry.vbus_voltage_mv,
        )

    async def _consume_device_events(self) -> None:
        async for event in self._transport.device_events():
            event_type = event.get("type")
            if event_type == "transport.disconnected":
                await self._unexpected_disconnect("deviceDisconnected")
            elif event_type == "device.state":
                self._apply_device_state(event.get("payload"))
                pending = self._host_settings.pending_device_patch
                if pending is not None and self._settings_match_patch(pending):
                    self._host_settings = self._settings_store.clear_pending_patch(
                        self._host_settings
                    )

    def _settings_match_patch(self, pending: PendingSettingsPatch) -> bool:
        document = self._settings_document()
        return document is not None and all(
            document.get(key) == value for key, value in pending.values.items()
        )

    async def _unexpected_disconnect(self, code: str) -> None:
        if self._manual_disconnect or self._sleeping or self._closed:
            return
        self._set_connection(ConnectionPhase.RETRYING, error_code=code)
        if self._host_settings.auto_reconnect and self._host_settings.selected_device_id:
            self._reconnect_needed.set()

    async def run(self, stop_event: asyncio.Event) -> None:
        self.state = replace(self.state, bridge=replace(self.state.bridge, running=True))
        self._commit("bridge.changed")
        self._history.prune(now_epoch=int(self._clock()))
        if self._host_settings.auto_reconnect and self._host_settings.selected_device_id:
            self._reconnect_needed.set()
        tasks = (
            asyncio.create_task(self._provider_loop(stop_event)),
            asyncio.create_task(self._connection_loop(stop_event)),
            asyncio.create_task(self._consume_device_events()),
        )
        try:
            await stop_event.wait()
        finally:
            for task in tasks:
                task.cancel()
            await asyncio.gather(*tasks, return_exceptions=True)
            self.state = replace(self.state, bridge=replace(self.state.bridge, running=False))
            self._set_connection(ConnectionPhase.STOPPED)

    async def _provider_loop(self, stop_event: asyncio.Event) -> None:
        while not stop_event.is_set():
            with suppress(IpcCommandError):
                await self.refresh_providers()
            try:
                await asyncio.wait_for(
                    stop_event.wait(),
                    timeout=self._host_settings.poll_interval_seconds,
                )
            except TimeoutError:
                continue

    async def _connection_loop(self, stop_event: asyncio.Event) -> None:
        while not stop_event.is_set():
            reconnect = asyncio.create_task(self._reconnect_needed.wait())
            stopping = asyncio.create_task(stop_event.wait())
            done, pending = await asyncio.wait(
                (reconnect, stopping),
                return_when=asyncio.FIRST_COMPLETED,
            )
            for task in pending:
                task.cancel()
            await asyncio.gather(*pending, return_exceptions=True)
            if stopping in done and stop_event.is_set():
                return
            self._reconnect_needed.clear()
            delay = 1.0
            while self._should_reconnect() and not stop_event.is_set():
                try:
                    await self.connect(self._host_settings.selected_device_id)
                    break
                except IpcCommandError as error:
                    wait_seconds = min(60.0, delay + self._jitter(delay))
                    self._set_connection(
                        ConnectionPhase.RETRYING,
                        error_code=error.code,
                        next_retry_epoch=int(self._clock() + wait_seconds),
                    )
                    await self._sleep(wait_seconds)
                    delay = min(60.0, delay * 2)

    def _should_reconnect(self) -> bool:
        return bool(
            not self._manual_disconnect
            and not self._sleeping
            and self._host_settings.auto_reconnect
            and self._host_settings.selected_device_id
            and not self._is_connected()
        )

    async def sleep_system(self) -> None:
        self._sleeping = True
        self._manual_disconnect = False
        self._reconnect_needed.clear()
        await self._transport.disconnect()
        self._set_connection(ConnectionPhase.STOPPED)

    async def wake_system(self) -> None:
        self._sleeping = False
        self._manual_disconnect = False
        if self._host_settings.auto_reconnect and self._host_settings.selected_device_id:
            self._reconnect_needed.set()

    async def update_providers(self, payload: dict[str, Any]) -> None:
        if not payload or not set(payload).issubset({"providerIds", "pollIntervalSeconds"}):
            raise IpcCommandError("invalidPayload", "Provider settings are invalid")
        updates: dict[str, object] = {}
        if "providerIds" in payload:
            provider_ids = payload["providerIds"]
            if not isinstance(provider_ids, list) or not all(
                isinstance(value, str) for value in provider_ids
            ):
                raise IpcCommandError("invalidPayload", "Provider IDs are invalid")
            updates["provider_ids"] = tuple(provider_ids)
        if "pollIntervalSeconds" in payload:
            updates["poll_interval_seconds"] = payload["pollIntervalSeconds"]
        try:
            updated = replace(self._host_settings, **updates)
        except (TypeError, ValueError) as error:
            raise IpcCommandError("invalidPayload", str(error)) from error
        self._settings_store.save(updated)
        self._host_settings = updated
        self.state = replace(
            self.state,
            bridge=replace(
                self.state.bridge,
                configured_provider_ids=updated.provider_ids,
                poll_interval_seconds=updated.poll_interval_seconds,
            ),
        )
        await self.refresh_providers()

    async def handle_ipc(self, request: IpcRequest) -> dict[str, Any]:
        command = request.type
        if command == "hello":
            self._require_empty(request)
            return {
                "bridgeVersion": __version__,
                "ipcSchemaVersion": 1,
                "capabilities": ["deviceManagement", "history", "providerControl"],
            }
        if command == "status.get":
            self._require_empty(request)
            return self.state.to_document()
        if command == "device.scan":
            self._require_empty(request)
            return {"peripherals": await self.scan()}
        if command == "device.connect":
            if set(request.payload) - {"identifier"}:
                raise IpcCommandError("invalidPayload", "Device selection is invalid")
            identifier = request.payload.get("identifier")
            if identifier is not None and not isinstance(identifier, str):
                raise IpcCommandError("invalidPayload", "Device identifier is invalid")
            await self.connect(identifier)
            return self.state.to_document()
        if command == "device.disconnect":
            self._require_empty(request)
            await self.disconnect()
            return self.state.to_document()
        if command == "device.forget":
            self._require_empty(request)
            await self.forget()
            return self.state.to_document()
        if command == "device.identify":
            self._require_empty(request)
            await self.identify()
            return {}
        if command == "device.refresh":
            self._require_empty(request)
            await self.refresh_device()
            return self.state.to_document()
        if command == "settings.get":
            self._require_empty(request)
            return {
                "syncStatus": self._settings_sync_status(),
                "settings": self._settings_document(),
            }
        if command == "settings.patch":
            return await self.patch_settings(request.payload)
        if command == "providers.refresh":
            self._require_empty(request)
            await self.refresh_providers()
            return {"providers": [item.to_document() for item in self.state.providers]}
        if command == "providers.update":
            await self.update_providers(request.payload)
            return {"providers": [item.to_document() for item in self.state.providers]}
        if command == "history.query":
            allowed = {
                "sinceEpoch",
                "providerId",
                "limit",
                "bucketSeconds",
                "currentCycle",
            }
            if set(request.payload) - allowed:
                raise IpcCommandError("invalidPayload", "History query is invalid")
            try:
                usage = self._history.query_usage(
                    since_epoch=request.payload.get("sinceEpoch", 0),
                    provider_id=request.payload.get("providerId"),
                    limit=request.payload.get("limit", 2_048),
                    bucket_seconds=request.payload.get("bucketSeconds"),
                    current_cycle=request.payload.get("currentCycle", False),
                )
            except HistoryError as error:
                raise IpcCommandError("invalidPayload", str(error)) from error
            return {"usage": usage}
        if command == "history.summary":
            required = {"sinceEpoch", "providerId", "timeZoneIdentifier"}
            if set(request.payload) != required:
                raise IpcCommandError("invalidPayload", "History summary query is invalid")
            try:
                return self._history.query_widget_summary(
                    since_epoch=request.payload["sinceEpoch"],
                    provider_id=request.payload["providerId"],
                    time_zone_identifier=request.payload["timeZoneIdentifier"],
                )
            except HistoryError as error:
                raise IpcCommandError("invalidPayload", str(error)) from error
        if command == "history.clear":
            self._require_empty(request)
            self._history.clear()
            return {}
        if command == "diagnostics.get":
            self._require_empty(request)
            return self.diagnostics()
        if command == "bridge.restart":
            self._require_empty(request)
            self.restart_requested = True
            self.restart_event.set()
            return {"accepted": True}
        if command == "system.sleep":
            self._require_empty(request)
            await self.sleep_system()
            return {}
        if command == "system.wake":
            self._require_empty(request)
            await self.wake_system()
            return {}
        raise IpcCommandError("unsupportedCommand", "IPC command is not supported")

    def diagnostics(self) -> dict[str, object]:
        connection = self.state.connection
        phase = connection.phase.value if isinstance(connection, ConnectionState) else "stopped"
        management_available = (
            connection.management_available if isinstance(connection, ConnectionState) else None
        )
        return {
            "bridgeVersion": __version__,
            "ipcSchemaVersion": 1,
            "phase": phase,
            "managementAvailable": management_available,
            "providerHealth": dict(self.state.bridge.provider_health),
            "recentEvents": list(self._diagnostic_events),
        }

    async def close(self) -> None:
        if self._closed:
            return
        self._closed = True
        await self._transport.close()
        self._history.close()

    def _is_connected(self) -> bool:
        connection = self.state.connection
        return (
            isinstance(connection, ConnectionState)
            and connection.phase is ConnectionPhase.CONNECTED
        )

    def _require_management_connection(self) -> None:
        if not self._is_connected():
            raise IpcCommandError("notConnected", "Connect an AgentMeter device first")
        if not self._transport.management_available:
            raise IpcCommandError(
                "managementUnavailable",
                "The connected firmware does not support device management",
                recoverable=False,
            )

    @staticmethod
    def _require_empty(request: IpcRequest) -> None:
        if request.payload:
            raise IpcCommandError("invalidPayload", f"{request.type} payload must be empty")

    def _settings_sync_status(self) -> str:
        if self._host_settings.pending_device_patch is not None:
            return "waitingForDevice"
        if self.state.settings is None:
            return "unavailable"
        return "synced"

    def _settings_document(self) -> dict[str, object] | None:
        return None if self.state.settings is None else self.state.settings.to_document()

    def _provider_summaries(self, snapshot: dict[str, Any]) -> tuple[ProviderSummary, ...]:
        sampled_at = int(snapshot["generatedAtEpoch"])
        return tuple(
            ProviderSummary(
                identifier=provider["id"],
                name=provider["name"],
                status=provider["status"],
                windows=tuple(
                    ProviderWindow(
                        kind=window["kind"],
                        label=window["label"],
                        used_percent=window.get("usedPercent"),
                        reset_at_epoch=window.get("resetAtEpoch"),
                    )
                    for window in provider["windows"]
                ),
                updated_at_epoch=self._provider_updated_at(provider, sampled_at),
                error_code=(
                    None if provider["status"] in {"ok", "stale"} else "providerUnavailable"
                ),
            )
            for provider in snapshot["providers"]
        )

    def _provider_updated_at(self, provider: dict[str, Any], sampled_at: int) -> int:
        if provider["status"] not in {"ok", "stale"}:
            return sampled_at
        cached_at = self._provider_history.updated_at_epoch(provider["id"])
        return sampled_at if cached_at is None else cached_at

    @staticmethod
    def _parse_information(value: object) -> DeviceInformation:
        if not isinstance(value, dict) or not isinstance(value.get("capabilities"), dict):
            raise ManagementProtocolError("device information is invalid")
        capabilities = value["capabilities"]
        return DeviceInformation(
            model=_required_string(value, "model", maximum=23),
            name=_required_string(value, "name", maximum=23),
            firmware_version=_required_string(value, "firmwareVersion", maximum=15),
            hardware_revision=_required_string(value, "hardwareRevision", maximum=15),
            snapshot_schema_version=_required_int(
                value, "snapshotSchemaVersion", minimum=1, maximum=255
            ),
            management_schema_version=_required_int(
                value, "managementSchemaVersion", minimum=1, maximum=255
            ),
            supports_settings=_required_bool(capabilities, "settings"),
            supports_identify=_required_bool(capabilities, "identify"),
            supports_restart=_required_bool(capabilities, "restart"),
            supports_forget=_required_bool(capabilities, "forget"),
            supports_brightness=_required_bool(capabilities, "brightness"),
            supports_battery=_required_bool(capabilities, "battery"),
            supports_vbus_voltage=_required_bool(capabilities, "vbusVoltage"),
            supports_input_current=_required_bool(capabilities, "inputCurrent"),
        )

    @staticmethod
    def _parse_telemetry(value: object) -> DeviceTelemetry:
        if not isinstance(value, dict):
            raise ManagementProtocolError("device telemetry is invalid")
        power_source = value.get("powerSource")
        if power_source not in {"unknown", "usb", "battery"}:
            raise ManagementProtocolError("powerSource is invalid")
        temperature = value.get("boardTemperatureC")
        if temperature is not None and (
            isinstance(temperature, bool) or not isinstance(temperature, (int, float))
        ):
            raise ManagementProtocolError("boardTemperatureC is invalid")
        return DeviceTelemetry(
            power_source=power_source,
            usb_present=_required_bool(value, "usbPresent"),
            battery_present=_required_bool(value, "batteryPresent"),
            charging=_optional_bool(value, "charging"),
            battery_percent=_optional_int(value, "batteryPercent", maximum=100),
            battery_voltage_mv=_optional_int(value, "batteryVoltageMv", maximum=65_535),
            vbus_voltage_mv=_optional_int(value, "vbusVoltageMv", maximum=65_535),
            input_current_ma=_optional_int(value, "inputCurrentMa", maximum=65_535),
            uptime_seconds=_required_int(value, "uptimeSeconds"),
            free_heap_bytes=_required_int(value, "freeHeapBytes"),
            minimum_free_heap_bytes=_required_int(value, "minimumFreeHeapBytes"),
            display_on=_required_bool(value, "displayOn"),
            display_dimmed=_required_bool(value, "displayDimmed"),
            brightness_percent=_required_int(value, "brightnessPercent", maximum=100),
            board_temperature_c=None if temperature is None else float(temperature),
        )

    @staticmethod
    def _parse_settings(value: object) -> DeviceSettings:
        if not isinstance(value, dict):
            raise ManagementProtocolError("device settings are invalid")
        thresholds = value.get("alertThresholds")
        hidden = value.get("hiddenProviderIds")
        order = value.get("providerOrder")
        if (
            not isinstance(thresholds, list)
            or not 1 <= len(thresholds) <= 3
            or any(isinstance(item, bool) or not isinstance(item, int) for item in thresholds)
            or thresholds != sorted(set(thresholds))
            or any(not 1 <= item <= 100 for item in thresholds)
            or not isinstance(hidden, list)
            or not all(isinstance(item, str) for item in hidden)
            or not isinstance(order, list)
            or not all(isinstance(item, str) for item in order)
        ):
            raise ManagementProtocolError("device settings are invalid")
        percent_limits = {"minimum": 1, "maximum": 100}
        dim_limits = {"minimum": 30, "maximum": 3_600}
        rotation_seconds = _required_int(value, "rotationSeconds", minimum=3, maximum=60)
        brightness_percent = _required_int(value, "brightnessPercent", **percent_limits)
        dim_after_seconds = _required_int(value, "dimAfterSeconds", **dim_limits)
        screen_off_after_seconds = _required_int(
            value, "screenOffAfterSeconds", minimum=60, maximum=86_400
        )
        if screen_off_after_seconds < dim_after_seconds:
            raise ManagementProtocolError("device settings are invalid")
        return DeviceSettings(
            revision=_required_int(value, "revision"),
            always_on=_required_bool(value, "alwaysOn"),
            full_view=_required_bool(value, "fullView"),
            rotation_seconds=rotation_seconds,
            brightness_percent=brightness_percent,
            dim_after_seconds=dim_after_seconds,
            screen_off_after_seconds=screen_off_after_seconds,
            alert_thresholds=tuple(thresholds),
            sound_enabled=_required_bool(value, "soundEnabled"),
            hidden_provider_ids=tuple(hidden),
            provider_order=tuple(order),
        )

    @staticmethod
    def _transport_error_code(error: Exception) -> str:
        if isinstance(error, TransportError):
            return getattr(error, "code", "bluetoothError")
        if isinstance(error, ManagementProtocolError):
            return "invalidDeviceResponse"
        if isinstance(error, ManagementError):
            return error.status
        return "connectionFailed"
