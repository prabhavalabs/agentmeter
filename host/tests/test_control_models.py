import pytest
from agentmeter_host import __version__
from agentmeter_host.control.models import (
    BridgeStatus,
    ConnectionPhase,
    ControlState,
    DeviceSettings,
    DeviceTelemetry,
    ProviderSummary,
    ProviderWindow,
)


def test_bridge_status_defaults_to_the_package_version() -> None:
    assert BridgeStatus().version == __version__


def test_control_state_serializes_unknown_hardware_as_null() -> None:
    state = ControlState(
        connection=ConnectionPhase.CONNECTED,
        telemetry=DeviceTelemetry(
            power_source="usb",
            usb_present=True,
            battery_present=False,
        ),
    )

    document = state.to_document()

    assert document["connection"]["phase"] == "connected"
    assert document["telemetry"]["batteryPresent"] is False
    assert document["telemetry"]["batteryPercent"] is None
    assert document["telemetry"]["inputCurrentMa"] is None


@pytest.mark.parametrize("phase", list(ConnectionPhase))
def test_every_connection_phase_has_a_stable_wire_value(phase: ConnectionPhase) -> None:
    document = ControlState(connection=phase).to_document()

    assert document["connection"]["phase"] == phase.value


def test_control_state_serializes_device_and_provider_state() -> None:
    state = ControlState(
        revision=12,
        settings=DeviceSettings(
            revision=8,
            always_on=True,
            full_view=False,
            rotation_seconds=3,
            brightness_percent=55,
            dim_after_seconds=300,
            screen_off_after_seconds=1_800,
            alert_thresholds=(75, 90),
            sound_enabled=False,
            hidden_provider_ids=("gemini",),
            provider_order=("codex", "claude"),
        ),
        providers=(
            ProviderSummary(
                identifier="codex",
                name="Codex",
                status="ok",
                windows=(ProviderWindow("session", "Session", 28, 1_785_614_400),),
            ),
        ),
        bridge=BridgeStatus(
            running=True,
            provider_health=(("codex", "ok"),),
            configured_provider_ids=("codex", "claude"),
            poll_interval_seconds=120,
        ),
    )

    document = state.to_document()

    assert document["revision"] == 12
    assert document["settings"]["hiddenProviderIds"] == ["gemini"]
    assert document["providers"][0]["windows"][0]["usedPercent"] == 28
    assert document["bridge"]["providerHealth"] == {"codex": "ok"}
    assert document["bridge"]["configuredProviderIds"] == ["codex", "claude"]
    assert document["bridge"]["pollIntervalSeconds"] == 120
