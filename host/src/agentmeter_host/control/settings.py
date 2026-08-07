from __future__ import annotations

import json
import os
import re
from contextlib import suppress
from dataclasses import dataclass, replace
from pathlib import Path
from typing import Any

from agentmeter_host.config import HostConfig

_SCHEMA_VERSION = 1
_PROVIDER_ID_PATTERN = re.compile(r"[a-z0-9_-]{1,23}")
_PATCH_FIELDS = frozenset(
    {
        "alwaysOn",
        "fullView",
        "rotationSeconds",
        "brightnessPercent",
        "dimAfterSeconds",
        "screenOffAfterSeconds",
        "alertThresholds",
        "soundEnabled",
        "hiddenProviderIds",
        "providerOrder",
    }
)


def _is_valid_threshold(value: object) -> bool:
    return not isinstance(value, bool) and isinstance(value, int) and 1 <= value <= 100


def _is_valid_provider_id(value: str) -> bool:
    return _PROVIDER_ID_PATTERN.fullmatch(value) is not None


class ControlSettingsError(ValueError):
    """The private host control-state file is invalid or unavailable."""


@dataclass(frozen=True, slots=True)
class PendingSettingsPatch:
    base_revision: int
    values: dict[str, Any]

    def __post_init__(self) -> None:
        if (
            isinstance(self.base_revision, bool)
            or not isinstance(self.base_revision, int)
            or not 0 <= self.base_revision <= 0xFFFFFFFF
        ):
            raise ControlSettingsError("pending patch base revision is invalid")
        if (
            not isinstance(self.values, dict)
            or not self.values
            or not set(self.values).issubset(_PATCH_FIELDS)
        ):
            raise ControlSettingsError("pending patch contains invalid settings")
        self._validate_values()
        try:
            encoded = json.dumps(self.values, separators=(",", ":"), allow_nan=False)
        except (TypeError, ValueError) as error:
            raise ControlSettingsError("pending patch must be JSON serializable") from error
        if len(encoded.encode()) > 2_048:
            raise ControlSettingsError("pending patch exceeds 2048 bytes")

    def _validate_values(self) -> None:
        for key in ("alwaysOn", "fullView", "soundEnabled"):
            if key in self.values and not isinstance(self.values[key], bool):
                raise ControlSettingsError(f"{key} must be a boolean")
        limits = {
            "rotationSeconds": (3, 60),
            "brightnessPercent": (1, 100),
            "dimAfterSeconds": (30, 3_600),
            "screenOffAfterSeconds": (60, 86_400),
        }
        for key, (minimum, maximum) in limits.items():
            value = self.values.get(key)
            if key in self.values and (
                isinstance(value, bool)
                or not isinstance(value, int)
                or not minimum <= value <= maximum
            ):
                raise ControlSettingsError(f"{key} is outside its supported range")
        if "alertThresholds" in self.values:
            thresholds = self.values["alertThresholds"]
            if (
                not isinstance(thresholds, list)
                or not 1 <= len(thresholds) <= 3
                or not all(_is_valid_threshold(value) for value in thresholds)
                or thresholds != sorted(set(thresholds))
            ):
                raise ControlSettingsError("alertThresholds is invalid")
        for key in ("hiddenProviderIds", "providerOrder"):
            if key not in self.values:
                continue
            provider_ids = self.values[key]
            if (
                not isinstance(provider_ids, list)
                or len(provider_ids) > 8
                or not all(isinstance(value, str) for value in provider_ids)
                or len(set(provider_ids)) != len(provider_ids)
                or not all(_is_valid_provider_id(value) for value in provider_ids)
            ):
                raise ControlSettingsError(f"{key} is invalid")

    def to_document(self) -> dict[str, object]:
        return {"baseRevision": self.base_revision, "values": self.values}


@dataclass(frozen=True, slots=True)
class MutableHostSettings:
    provider_ids: tuple[str, ...]
    poll_interval_seconds: int
    selected_device_id: str | None = None
    selected_device_name: str | None = None
    auto_reconnect: bool = True
    device_sync_enabled: bool = True
    pending_device_patch: PendingSettingsPatch | None = None

    def __post_init__(self) -> None:
        if not 1 <= len(self.provider_ids) <= 8 or len(set(self.provider_ids)) != len(
            self.provider_ids
        ):
            raise ControlSettingsError("provider IDs must contain 1-8 unique values")
        if any(_PROVIDER_ID_PATTERN.fullmatch(value) is None for value in self.provider_ids):
            raise ControlSettingsError("provider ID is invalid")
        if (
            isinstance(self.poll_interval_seconds, bool)
            or not isinstance(self.poll_interval_seconds, int)
            or self.poll_interval_seconds < 30
        ):
            raise ControlSettingsError("poll interval must be at least 30 seconds")
        for value, label in (
            (self.selected_device_id, "selected device ID"),
            (self.selected_device_name, "selected device name"),
        ):
            if value is not None and (not isinstance(value, str) or not 1 <= len(value) <= 128):
                raise ControlSettingsError(f"{label} is invalid")
        if not isinstance(self.auto_reconnect, bool):
            raise ControlSettingsError("auto reconnect must be a boolean")
        if not isinstance(self.device_sync_enabled, bool):
            raise ControlSettingsError("device sync must be a boolean")

    @classmethod
    def from_host_config(cls, config: HostConfig) -> MutableHostSettings:
        return cls(
            provider_ids=config.provider_ids,
            poll_interval_seconds=config.poll_interval_seconds,
        )

    def to_document(self) -> dict[str, object]:
        return {
            "schemaVersion": _SCHEMA_VERSION,
            "providerIds": list(self.provider_ids),
            "pollIntervalSeconds": self.poll_interval_seconds,
            "selectedDeviceId": self.selected_device_id,
            "selectedDeviceName": self.selected_device_name,
            "autoReconnect": self.auto_reconnect,
            "deviceSyncEnabled": self.device_sync_enabled,
            "pendingDevicePatch": (
                None
                if self.pending_device_patch is None
                else self.pending_device_patch.to_document()
            ),
        }


class ControlSettingsStore:
    def __init__(self, path: Path) -> None:
        self.path = path

    def load(self, base: HostConfig) -> MutableHostSettings:
        if not self.path.exists():
            return MutableHostSettings.from_host_config(base)
        try:
            document = json.loads(self.path.read_text(encoding="utf-8"))
            return self._decode(document)
        except ControlSettingsError:
            raise
        except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
            raise ControlSettingsError(f"could not load control settings {self.path}") from error

    def save(self, settings: MutableHostSettings) -> None:
        document = settings.to_document()
        encoded = (json.dumps(document, indent=2, sort_keys=True) + "\n").encode()
        self.path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        os.chmod(self.path.parent, 0o700)
        temporary = self.path.with_name(f".{self.path.name}.tmp")
        descriptor: int | None = None
        try:
            descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
            with os.fdopen(descriptor, "wb") as output:
                descriptor = None
                output.write(encoded)
                output.flush()
                os.fsync(output.fileno())
            os.chmod(temporary, 0o600)
            os.replace(temporary, self.path)
            os.chmod(self.path, 0o600)
            directory = os.open(self.path.parent, os.O_RDONLY)
            try:
                os.fsync(directory)
            finally:
                os.close(directory)
        except OSError as error:
            raise ControlSettingsError(f"could not save control settings {self.path}") from error
        finally:
            if descriptor is not None:
                os.close(descriptor)
            with suppress(FileNotFoundError):
                temporary.unlink()

    def save_pending_patch(
        self,
        settings: MutableHostSettings,
        pending: PendingSettingsPatch,
    ) -> MutableHostSettings:
        updated = replace(settings, pending_device_patch=pending)
        self.save(updated)
        return updated

    def clear_pending_patch(self, settings: MutableHostSettings) -> MutableHostSettings:
        updated = replace(settings, pending_device_patch=None)
        self.save(updated)
        return updated

    @staticmethod
    def _decode(document: object) -> MutableHostSettings:
        if not isinstance(document, dict):
            raise ControlSettingsError("control settings must be an object")
        required = {
            "schemaVersion",
            "providerIds",
            "pollIntervalSeconds",
            "selectedDeviceId",
            "selectedDeviceName",
            "autoReconnect",
            "pendingDevicePatch",
        }
        # deviceSyncEnabled arrived after the first release; earlier control
        # files omit it and default to synchronizing.
        expected = required | {"deviceSyncEnabled"}
        if (
            not required <= set(document) <= expected
            or document.get("schemaVersion") != _SCHEMA_VERSION
        ):
            raise ControlSettingsError("control settings schema is invalid")
        provider_ids = document["providerIds"]
        if not isinstance(provider_ids, list) or not all(
            isinstance(value, str) for value in provider_ids
        ):
            raise ControlSettingsError("provider IDs must be an array of strings")
        pending_document = document["pendingDevicePatch"]
        pending = None
        if pending_document is not None:
            if not isinstance(pending_document, dict) or set(pending_document) != {
                "baseRevision",
                "values",
            }:
                raise ControlSettingsError("pending patch is invalid")
            values = pending_document["values"]
            if not isinstance(values, dict):
                raise ControlSettingsError("pending patch values must be an object")
            pending = PendingSettingsPatch(
                base_revision=pending_document["baseRevision"],
                values=values,
            )
        return MutableHostSettings(
            provider_ids=tuple(provider_ids),
            poll_interval_seconds=document["pollIntervalSeconds"],
            selected_device_id=document["selectedDeviceId"],
            selected_device_name=document["selectedDeviceName"],
            auto_reconnect=document["autoReconnect"],
            device_sync_enabled=document.get("deviceSyncEnabled", True),
            pending_device_patch=pending,
        )
