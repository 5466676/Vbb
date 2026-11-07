"""Room ownership on this worker.

A room is run by exactly one worker: the one that holds ``room:{code}:owner`` (a lease that
the actor renews). Any worker can deliver input: push to the inbox, make sure some worker owns
the room (take it if the lease is free), then notify the owner.
"""

from __future__ import annotations

import asyncio
import contextlib
import json
import logging
from collections.abc import Callable
from typing import Any

from redis.asyncio import Redis

from app.config import Settings
from app.questions.provider import ProviderFactory, SampleProvider
from app.rooms import store
from app.rooms.actor import RoomActor
from app.rooms.bus import Bus

log = logging.getLogger(__name__)


class RoomManager:
    def __init__(
        self,
        redis: Redis,
        bus: Bus,
        settings: Settings,
        provider_factory: ProviderFactory = SampleProvider,
    ) -> None:
        self.redis = redis
        self.bus = bus
        self.settings = settings
        self.provider_factory = provider_factory
        self.actors: dict[str, RoomActor] = {}
        self._lock = asyncio.Lock()

    async def ensure_owner(self, code: str) -> None:
        if code in self.actors:
            return
        async with self._lock:
            if code in self.actors or not await self.redis.exists(store.k_room(code)):
                return
            ok = await self.redis.set(
                store.k_owner(code),
                self.settings.worker_id,
                nx=True,
                px=int(self.settings.room_lease_s * 1000),
            )
            if not ok:
                return  # another worker runs it
            actor = RoomActor(
                code,
                self.redis,
                self.bus,
                self.settings,
                self.provider_factory,
                on_stop=self._stopped,
            )
            self.actors[code] = actor
            try:
                await actor.start()
            except Exception:
                self.actors.pop(code, None)
                await self.redis.delete(store.k_owner(code))
                raise
            log.info("worker %s now runs room %s", self.settings.worker_id, code)

    def _stopped(self, code: str) -> None:
        self.actors.pop(code, None)

    async def send(self, code: str, item: dict[str, Any]) -> None:
        await self.redis.rpush(store.k_inbox(code), json.dumps(item, ensure_ascii=False))
        await self.ensure_owner(code)
        await self.bus.publish(store.ch_room_in(code), {})

    async def stop(self) -> None:
        for code, actor in list(self.actors.items()):
            await actor.stop()
            if (await self.redis.get(store.k_owner(code))) == self.settings.worker_id.encode():
                await self.redis.delete(store.k_owner(code))
        self.actors.clear()

    async def watchdog(self, codes: Callable[[], set[str]]) -> None:
        """Take over rooms whose owner died (its lease expired) while players are connected here."""
        while True:
            await asyncio.sleep(self.settings.room_lease_s / 2)
            for code in codes():
                with contextlib.suppress(Exception):
                    if code not in self.actors and not await self.redis.exists(store.k_owner(code)):
                        await self.ensure_owner(code)
                        await self.bus.publish(store.ch_room_in(code), {})
