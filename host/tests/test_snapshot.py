import pytest
from helpers import provider_usage


@pytest.mark.asyncio
async def test_collect_device_snapshot_connects_config_to_normalizer() -> None:
    from agentmeter_host.config import HostConfig
    from agentmeter_host.normalization import DisplayPreferences
    from agentmeter_host.snapshot import collect_device_snapshot

    config = HostConfig(
        poll_interval_seconds=60,
        provider_ids=("codex", "claude"),
        display=DisplayPreferences(55, (75, 90), False),
    )

    class FakeClient:
        async def fetch_provider_usages(
            self, provider_ids: tuple[str, ...]
        ) -> dict[str, dict[str, object] | None]:
            return {provider_id: provider_usage(provider_id) for provider_id in provider_ids}

    class FakeServer:
        async def __aenter__(self) -> FakeClient:
            return FakeClient()

        async def __aexit__(self, *_args) -> None:
            pass

    observed_refresh_intervals = []

    def server_factory(*, refresh_interval_seconds: int) -> FakeServer:
        observed_refresh_intervals.append(refresh_interval_seconds)
        return FakeServer()

    snapshot = await collect_device_snapshot(config, server_factory=server_factory)

    assert observed_refresh_intervals == [60]
    assert snapshot["messageId"] == 0
    assert [provider["id"] for provider in snapshot["providers"]] == ["codex", "claude"]
    assert all(len(provider["windows"]) == 2 for provider in snapshot["providers"])
    assert snapshot["display"]["brightnessPercent"] == 55
