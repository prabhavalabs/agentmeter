from __future__ import annotations

import asyncio
from collections import deque
from collections.abc import AsyncIterator, Callable
from dataclasses import dataclass
from typing import Any


@dataclass(frozen=True, slots=True)
class ControlEvent:
    type: str
    payload: dict[str, Any]
    sequence: int = 0
    occurred_at_epoch: int | None = None


_COALESCIBLE_TYPES = frozenset(
    {
        "state.changed",
        "telemetry.changed",
        "providers.changed",
        "discovery.changed",
        "bridge.changed",
    }
)


class _Subscription:
    def __init__(self, capacity: int, on_close: Callable[[_Subscription], None]) -> None:
        self.capacity = capacity
        self.events: deque[ControlEvent] = deque()
        self.available = asyncio.Event()
        self.closed = False
        self._on_close = on_close

    def __aiter__(self) -> _Subscription:
        return self

    async def __anext__(self) -> ControlEvent:
        return await self.get()

    def put(self, event: ControlEvent) -> bool:
        if self.closed:
            return False
        if event.type in _COALESCIBLE_TYPES:
            for index in range(len(self.events) - 1, -1, -1):
                if self.events[index].type == event.type:
                    self.events[index] = event
                    self.available.set()
                    return True
        if len(self.events) >= self.capacity:
            removable = next(
                (
                    index
                    for index, queued in enumerate(self.events)
                    if queued.type in _COALESCIBLE_TYPES
                ),
                None,
            )
            if removable is None:
                if event.type in _COALESCIBLE_TYPES:
                    return True
                self.close()
                return False
            del self.events[removable]
        self.events.append(event)
        self.available.set()
        return True

    async def get(self) -> ControlEvent:
        while not self.events:
            if self.closed:
                raise StopAsyncIteration
            self.available.clear()
            await self.available.wait()
        event = self.events.popleft()
        if not self.events:
            self.available.clear()
        return event

    def close(self) -> None:
        if self.closed:
            return
        self.closed = True
        self.events.clear()
        self.available.set()
        self._on_close(self)

    async def aclose(self) -> None:
        self.close()


class EventBroker:
    """Fan out bounded control events without waking idle subscribers."""

    def __init__(self, *, capacity: int = 64) -> None:
        if capacity < 1:
            raise ValueError("capacity must be positive")
        self._capacity = capacity
        self._subscriptions: set[_Subscription] = set()
        self._sequence = 0

    def publish(self, event: ControlEvent) -> None:
        self._sequence += 1
        sequenced = ControlEvent(
            type=event.type,
            payload=event.payload,
            sequence=self._sequence,
            occurred_at_epoch=event.occurred_at_epoch,
        )
        closed = []
        for subscription in self._subscriptions:
            if not subscription.put(sequenced):
                closed.append(subscription)
        for subscription in closed:
            self._subscriptions.discard(subscription)

    def subscribe(self) -> AsyncIterator[ControlEvent]:
        subscription = _Subscription(self._capacity, self._remove)
        self._subscriptions.add(subscription)
        return subscription

    def _remove(self, subscription: _Subscription) -> None:
        self._subscriptions.discard(subscription)

    def close(self) -> None:
        for subscription in tuple(self._subscriptions):
            subscription.close()
        self._subscriptions.clear()
