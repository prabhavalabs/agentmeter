from __future__ import annotations

from dataclasses import dataclass, field
from enum import StrEnum
from typing import Any


class ConnectionPhase(StrEnum):
    STOPPED = "stopped"
    BLUETOOTH_UNAVAILABLE = "bluetoothUnavailable"
    SEARCHING = "searching"
    CONNECTING = "connecting"
    AUTHENTICATING = "authenticating"
    SYNCHRONIZING = "synchronizing"
    CONNECTED = "connected"
    DEGRADED = "degraded"
    RETRYING = "retrying"


@dataclass(frozen=True, slots=True)
class PeripheralSummary:
    identifier: str
    name: str
    rssi: int | None = None
    last_seen_epoch: int | None = None

    def to_document(self) -> dict[str, object]:
        return {
            "identifier": self.identifier,
            "name": self.name,
            "rssi": self.rssi,
            "lastSeenEpoch": self.last_seen_epoch,
        }


@dataclass(frozen=True, slots=True)
class ConnectionState:
    phase: ConnectionPhase = ConnectionPhase.STOPPED
    selected_device_id: str | None = None
    selected_device_name: str | None = None
    rssi: int | None = None
    management_available: bool | None = None
    next_retry_epoch: int | None = None
    error_code: str | None = None

    def to_document(self) -> dict[str, object]:
        return {
            "phase": self.phase.value,
            "selectedDeviceId": self.selected_device_id,
            "selectedDeviceName": self.selected_device_name,
            "rssi": self.rssi,
            "managementAvailable": self.management_available,
            "nextRetryEpoch": self.next_retry_epoch,
            "errorCode": self.error_code,
        }


@dataclass(frozen=True, slots=True)
class DeviceInformation:
    model: str
    name: str
    firmware_version: str
    hardware_revision: str
    snapshot_schema_version: int = 1
    management_schema_version: int = 1
    supports_settings: bool = True
    supports_identify: bool = True
    supports_restart: bool = True
    supports_forget: bool = True
    supports_brightness: bool = True
    supports_battery: bool = False
    supports_vbus_voltage: bool = False
    supports_input_current: bool = False

    def to_document(self) -> dict[str, object]:
        return {
            "model": self.model,
            "name": self.name,
            "firmwareVersion": self.firmware_version,
            "hardwareRevision": self.hardware_revision,
            "snapshotSchemaVersion": self.snapshot_schema_version,
            "managementSchemaVersion": self.management_schema_version,
            "capabilities": {
                "settings": self.supports_settings,
                "identify": self.supports_identify,
                "restart": self.supports_restart,
                "forget": self.supports_forget,
                "brightness": self.supports_brightness,
                "battery": self.supports_battery,
                "vbusVoltage": self.supports_vbus_voltage,
                "inputCurrent": self.supports_input_current,
            },
        }


@dataclass(frozen=True, slots=True)
class DeviceTelemetry:
    power_source: str | None = None
    usb_present: bool | None = None
    battery_present: bool | None = None
    charging: bool | None = None
    battery_percent: int | None = None
    battery_voltage_mv: int | None = None
    vbus_voltage_mv: int | None = None
    input_current_ma: int | None = None
    uptime_seconds: int | None = None
    free_heap_bytes: int | None = None
    minimum_free_heap_bytes: int | None = None
    display_on: bool | None = None
    display_dimmed: bool | None = None
    brightness_percent: int | None = None
    board_temperature_c: float | None = None

    def to_document(self) -> dict[str, object]:
        return {
            "powerSource": self.power_source,
            "usbPresent": self.usb_present,
            "batteryPresent": self.battery_present,
            "charging": self.charging,
            "batteryPercent": self.battery_percent,
            "batteryVoltageMv": self.battery_voltage_mv,
            "vbusVoltageMv": self.vbus_voltage_mv,
            "inputCurrentMa": self.input_current_ma,
            "uptimeSeconds": self.uptime_seconds,
            "freeHeapBytes": self.free_heap_bytes,
            "minimumFreeHeapBytes": self.minimum_free_heap_bytes,
            "displayOn": self.display_on,
            "displayDimmed": self.display_dimmed,
            "brightnessPercent": self.brightness_percent,
            "boardTemperatureC": self.board_temperature_c,
        }


@dataclass(frozen=True, slots=True)
class DeviceSettings:
    revision: int
    always_on: bool
    full_view: bool
    rotation_seconds: int
    brightness_percent: int
    dim_after_seconds: int
    screen_off_after_seconds: int
    alert_thresholds: tuple[int, ...]
    sound_enabled: bool
    hidden_provider_ids: tuple[str, ...] = ()
    provider_order: tuple[str, ...] = ()

    def to_document(self) -> dict[str, object]:
        return {
            "revision": self.revision,
            "alwaysOn": self.always_on,
            "fullView": self.full_view,
            "rotationSeconds": self.rotation_seconds,
            "brightnessPercent": self.brightness_percent,
            "dimAfterSeconds": self.dim_after_seconds,
            "screenOffAfterSeconds": self.screen_off_after_seconds,
            "alertThresholds": list(self.alert_thresholds),
            "soundEnabled": self.sound_enabled,
            "hiddenProviderIds": list(self.hidden_provider_ids),
            "providerOrder": list(self.provider_order),
        }


@dataclass(frozen=True, slots=True)
class ProviderWindow:
    kind: str
    label: str
    used_percent: int | None = None
    reset_at_epoch: int | None = None

    def to_document(self) -> dict[str, object]:
        return {
            "kind": self.kind,
            "label": self.label,
            "usedPercent": self.used_percent,
            "resetAtEpoch": self.reset_at_epoch,
        }


@dataclass(frozen=True, slots=True)
class ProviderSummary:
    identifier: str
    name: str
    status: str
    windows: tuple[ProviderWindow, ...] = ()
    updated_at_epoch: int | None = None
    error_code: str | None = None

    def to_document(self) -> dict[str, object]:
        return {
            "id": self.identifier,
            "name": self.name,
            "status": self.status,
            "windows": [window.to_document() for window in self.windows],
            "updatedAtEpoch": self.updated_at_epoch,
            "errorCode": self.error_code,
        }


@dataclass(frozen=True, slots=True)
class BridgeStatus:
    version: str = "0.1.0"
    running: bool = False
    last_provider_refresh_epoch: int | None = None
    last_device_sync_epoch: int | None = None
    last_error_code: str | None = None
    provider_health: tuple[tuple[str, str], ...] = ()
    configured_provider_ids: tuple[str, ...] = ()
    poll_interval_seconds: int = 300

    def to_document(self) -> dict[str, object]:
        return {
            "version": self.version,
            "running": self.running,
            "lastProviderRefreshEpoch": self.last_provider_refresh_epoch,
            "lastDeviceSyncEpoch": self.last_device_sync_epoch,
            "lastErrorCode": self.last_error_code,
            "providerHealth": dict(self.provider_health),
            "configuredProviderIds": list(self.configured_provider_ids),
            "pollIntervalSeconds": self.poll_interval_seconds,
        }


@dataclass(frozen=True, slots=True)
class ControlState:
    revision: int = 0
    connection: ConnectionState | ConnectionPhase = field(default_factory=ConnectionState)
    peripherals: tuple[PeripheralSummary, ...] = ()
    information: DeviceInformation | None = None
    telemetry: DeviceTelemetry | None = None
    settings: DeviceSettings | None = None
    providers: tuple[ProviderSummary, ...] = ()
    bridge: BridgeStatus = field(default_factory=BridgeStatus)

    def __post_init__(self) -> None:
        if isinstance(self.connection, ConnectionPhase):
            object.__setattr__(self, "connection", ConnectionState(phase=self.connection))

    def to_document(self) -> dict[str, Any]:
        connection = self.connection
        if not isinstance(connection, ConnectionState):
            raise TypeError("connection must be a ConnectionState")
        return {
            "revision": self.revision,
            "connection": connection.to_document(),
            "peripherals": [peripheral.to_document() for peripheral in self.peripherals],
            "information": None if self.information is None else self.information.to_document(),
            "telemetry": None if self.telemetry is None else self.telemetry.to_document(),
            "settings": None if self.settings is None else self.settings.to_document(),
            "providers": [provider.to_document() for provider in self.providers],
            "bridge": self.bridge.to_document(),
        }
