import json
import stat
from dataclasses import replace

import pytest
from agentmeter_host.config import HostConfig
from agentmeter_host.control.settings import (
    ControlSettingsError,
    ControlSettingsStore,
    PendingSettingsPatch,
)
from agentmeter_host.normalization import DisplayPreferences


def host_config() -> HostConfig:
    return HostConfig(
        poll_interval_seconds=60,
        provider_ids=("codex", "claude"),
        display=DisplayPreferences(55, (75, 90), False),
    )


def test_control_settings_migrate_from_toml_and_write_private_json(tmp_path) -> None:
    store = ControlSettingsStore(tmp_path / "control-state-v1.json")
    settings = store.load(host_config())
    settings = replace(settings, selected_device_id="peripheral-1")

    store.save(settings)

    document = json.loads(store.path.read_text())
    assert document["schemaVersion"] == 1
    assert document["providerIds"] == ["codex", "claude"]
    assert document["selectedDeviceId"] == "peripheral-1"
    assert stat.S_IMODE(store.path.stat().st_mode) == 0o600
    assert not store.path.with_name(f".{store.path.name}.tmp").exists()


def test_corrupt_settings_are_not_silently_overwritten(tmp_path) -> None:
    path = tmp_path / "control-state-v1.json"
    path.write_text("{not json")
    original = path.read_bytes()
    store = ControlSettingsStore(path)

    with pytest.raises(ControlSettingsError, match="could not load"):
        store.load(host_config())

    assert path.read_bytes() == original


def test_pending_patch_round_trips_and_clears_only_after_confirmation(tmp_path) -> None:
    store = ControlSettingsStore(tmp_path / "control-state-v1.json")
    settings = store.load(host_config())
    pending = PendingSettingsPatch(8, {"alwaysOn": True, "brightnessPercent": 60})

    settings = store.save_pending_patch(settings, pending)
    reloaded = store.load(host_config())
    assert reloaded.pending_device_patch == pending

    settings = store.clear_pending_patch(settings)
    assert settings.pending_device_patch is None
    assert store.load(host_config()).pending_device_patch is None


def test_settings_reject_unknown_fields_without_replacing_original(tmp_path) -> None:
    path = tmp_path / "control-state-v1.json"
    store = ControlSettingsStore(path)
    store.save(store.load(host_config()))
    document = json.loads(path.read_text())
    document["secret"] = "unexpected"
    path.write_text(json.dumps(document))
    original = path.read_bytes()

    with pytest.raises(ControlSettingsError, match="schema"):
        store.load(host_config())

    assert path.read_bytes() == original
