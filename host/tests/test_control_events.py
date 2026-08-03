import asyncio

import pytest
from agentmeter_host.control.events import ControlEvent, EventBroker


@pytest.mark.asyncio
async def test_event_broker_coalesces_repeated_state_events() -> None:
    broker = EventBroker(capacity=4)
    stream = broker.subscribe()
    broker.publish(ControlEvent("telemetry.changed", {"batteryPercent": 60}))
    broker.publish(ControlEvent("telemetry.changed", {"batteryPercent": 59}))

    event = await anext(stream)
    assert event.type == "telemetry.changed"
    assert event.payload["batteryPercent"] == 59
    await stream.aclose()


@pytest.mark.asyncio
async def test_event_broker_preserves_critical_events_when_state_queue_is_full() -> None:
    broker = EventBroker(capacity=2)
    stream = broker.subscribe()
    broker.publish(ControlEvent("telemetry.changed", {"value": 1}))
    broker.publish(ControlEvent("providers.changed", {"value": 2}))
    broker.publish(ControlEvent("connection.changed", {"phase": "connected"}))

    first = await anext(stream)
    second = await anext(stream)
    assert [first.type, second.type] == ["providers.changed", "connection.changed"]
    assert second.sequence > first.sequence
    await stream.aclose()


@pytest.mark.asyncio
async def test_event_broker_removes_closed_subscribers() -> None:
    broker = EventBroker()
    stream = broker.subscribe()
    pending = asyncio.create_task(anext(stream))
    await asyncio.sleep(0)
    assert len(broker._subscriptions) == 1

    pending.cancel()
    with pytest.raises(asyncio.CancelledError):
        await pending
    await stream.aclose()

    assert not broker._subscriptions
