from pathlib import Path

import pytest

ROOT = Path(__file__).parents[2]


def test_load_config_reads_host_data_source_settings() -> None:
    from agentmeter_host.config import load_config

    config = load_config(ROOT / "config.example.toml")

    assert config.poll_interval_seconds == 60
    assert config.provider_ids == ("codex", "claude", "gemini", "cursor")
    assert config.display.brightness_percent == 55
    assert config.display.dim_after_seconds == 300
    assert config.display.screen_off_after_seconds == 1800
    assert config.display.alert_thresholds == (75, 90)
    assert config.display.sound_enabled is False
    assert config.transport.preferred == "ble"
    assert config.transport.device_name_prefix == "AgentMeter"
    assert config.transport.serial_port is None


def test_host_config_accepts_up_to_eight_provider_ids() -> None:
    from agentmeter_host.config import HostConfig
    from agentmeter_host.normalization import DisplayPreferences

    provider_ids = tuple(f"provider-{index}" for index in range(8))

    config = HostConfig(
        poll_interval_seconds=60,
        provider_ids=provider_ids,
        display=DisplayPreferences(55, (75, 90), False),
    )

    assert config.provider_ids == provider_ids


def test_load_config_reports_invalid_provider_list(tmp_path) -> None:
    from agentmeter_host.config import ConfigError, load_config

    config_path = tmp_path / "config.toml"
    config_path.write_text(
        """
[general]
poll_interval_seconds = 60
providers = ["codex", "codex"]

[display]
brightness_percent = 55
alert_thresholds = [75, 90]
sound_enabled = false
"""
    )

    with pytest.raises(ConfigError, match="providers must contain between 1 and 8 unique IDs"):
        load_config(config_path)


def test_load_config_rejects_provider_id_that_device_cannot_represent(tmp_path) -> None:
    from agentmeter_host.config import ConfigError, load_config

    config_path = tmp_path / "config.toml"
    config_path.write_text(
        """
[general]
poll_interval_seconds = 60
providers = ["Codex with spaces"]

[display]
brightness_percent = 55
alert_thresholds = [75, 90]
sound_enabled = false
"""
    )

    with pytest.raises(ConfigError, match="lowercase letters, numbers, underscores, or hyphens"):
        load_config(config_path)


def test_load_config_rejects_too_frequent_polling(tmp_path) -> None:
    from agentmeter_host.config import ConfigError, load_config

    config_path = tmp_path / "config.toml"
    config_path.write_text(
        """
[general]
poll_interval_seconds = 10
providers = ["codex"]

[display]
brightness_percent = 55
alert_thresholds = [75, 90]
sound_enabled = false
"""
    )

    with pytest.raises(ConfigError, match="poll_interval_seconds must be at least 30"):
        load_config(config_path)


def test_load_config_reports_missing_file(tmp_path) -> None:
    from agentmeter_host.config import ConfigError, load_config

    config_path = tmp_path / "missing.toml"

    with pytest.raises(ConfigError, match=f"could not load configuration {config_path}"):
        load_config(config_path)
