from __future__ import annotations

import re
import tomllib
from dataclasses import dataclass
from pathlib import Path

from agentmeter_host.normalization import DisplayPreferences


class ConfigError(ValueError):
    """AgentMeter configuration is missing or invalid."""


@dataclass(frozen=True)
class HostConfig:
    poll_interval_seconds: int
    provider_ids: tuple[str, ...]
    display: DisplayPreferences

    def __post_init__(self) -> None:
        if not isinstance(self.poll_interval_seconds, int) or self.poll_interval_seconds < 30:
            raise ConfigError("poll_interval_seconds must be at least 30")
        if not 1 <= len(self.provider_ids) <= 4 or len(set(self.provider_ids)) != len(
            self.provider_ids
        ):
            raise ConfigError("providers must contain between 1 and 4 unique IDs")
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
        return HostConfig(
            poll_interval_seconds=general["poll_interval_seconds"],
            provider_ids=tuple(general["providers"]),
            display=DisplayPreferences(
                brightness_percent=display["brightness_percent"],
                alert_thresholds=tuple(display["alert_thresholds"]),
                sound_enabled=display["sound_enabled"],
            ),
        )
    except ConfigError:
        raise
    except (OSError, KeyError, TypeError, ValueError) as error:
        message = f"could not load configuration {path}: missing or invalid settings"
        raise ConfigError(message) from error
