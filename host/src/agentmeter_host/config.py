from __future__ import annotations

import re
import tomllib
from dataclasses import dataclass, field
from pathlib import Path

from agentmeter_host.normalization import DisplayPreferences


class ConfigError(ValueError):
    """AgentMeter configuration is missing or invalid."""


@dataclass(frozen=True)
class TransportConfig:
    preferred: str = "ble"
    device_name_prefix: str = "AgentMeter"
    serial_port: str | None = None

    def __post_init__(self) -> None:
        if self.preferred not in {"ble", "serial"}:
            raise ConfigError("transport preferred must be 'ble' or 'serial'")
        if not self.device_name_prefix or len(self.device_name_prefix) > 24:
            raise ConfigError("transport device_name must contain between 1 and 24 characters")
        if self.preferred == "serial" and not self.serial_port:
            raise ConfigError("transport serial_port is required when preferred is 'serial'")


@dataclass(frozen=True)
class HostConfig:
    poll_interval_seconds: int
    provider_ids: tuple[str, ...]
    display: DisplayPreferences
    transport: TransportConfig = field(default_factory=TransportConfig)

    def __post_init__(self) -> None:
        if not isinstance(self.poll_interval_seconds, int) or self.poll_interval_seconds < 30:
            raise ConfigError("poll_interval_seconds must be at least 30")
        if not 1 <= len(self.provider_ids) <= 8 or len(set(self.provider_ids)) != len(
            self.provider_ids
        ):
            raise ConfigError("providers must contain between 1 and 8 unique IDs")
        if any(
            re.fullmatch(r"[a-z0-9_-]{1,23}", provider_id) is None
            for provider_id in self.provider_ids
        ):
            raise ConfigError(
                "provider IDs must use 1-23 lowercase letters, numbers, underscores, or hyphens"
            )


def load_config(path: Path) -> HostConfig:
    try:
        with path.open("rb") as config_file:
            document = tomllib.load(config_file)

        general = document["general"]
        display = document["display"]
        transport = document.get("transport", {})
        return HostConfig(
            poll_interval_seconds=general["poll_interval_seconds"],
            provider_ids=tuple(general["providers"]),
            display=DisplayPreferences(
                brightness_percent=display["brightness_percent"],
                alert_thresholds=tuple(display["alert_thresholds"]),
                sound_enabled=display["sound_enabled"],
                dim_after_seconds=display.get("dim_after_seconds", 300),
                screen_off_after_seconds=display.get("screen_off_after_seconds", 1_800),
            ),
            transport=TransportConfig(
                preferred=transport.get("preferred", "ble"),
                device_name_prefix=transport.get("device_name", "AgentMeter"),
                serial_port=transport.get("serial_port"),
            ),
        )
    except ConfigError:
        raise
    except (OSError, KeyError, TypeError, ValueError) as error:
        message = f"could not load configuration {path}: missing or invalid settings"
        raise ConfigError(message) from error
