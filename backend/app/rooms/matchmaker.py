"""Quick match: queues per mode and size. A full queue starts a room; a player who waited
``quick_match_wait_s`` gets the free seats filled with medium bots (brief §5.2)."""

from __future__ import annotations

import asyncio
import json
import logging
import random
import time

from redis.asyncio import Redis

from app.bots.simple import Difficulty
from app.config import Settings
from app.engine.armies import Army
from app.engine.models import Mode
from app.rooms import store
from app.rooms.actor import BOT_NAMES, START_PAUSE_MS
from app.rooms.bus import Bus
from app.rooms.manager import RoomManager
from app.rooms.store import RoomData, RoomSettings, Seat

log = logging.getLogger(__name__)
QUEUES = [(Mode.FFA, n) for n in range(2, 9)] + [(Mode.TEAMS, n) for n in (4, 6, 8)]


class Matchmaker:
    def __init__(self, redis: Redis, bus: Bus, manager: RoomManager, settings: Settings) -> None:
        self.redis = redis
        self.bus = bus
        self.manager = manager
        self.settings = settings
        self.rnd = random.Random()

    async def run(self) -> None:
        interval = max(0.05, min(1.0, 1.0 * self.settings.time_scale * 5))
        while True:
            try:
                for mode, size in QUEUES:
                    await self._check(mode, size)
            except Exception:
                log.exception("matchmaker pass failed")
            await asyncio.sleep(interval)

    async def _check(self, mode: Mode, size: int) -> None:
        key = store.k_queue(mode, size)
        if not await self.redis.llen(key):
            return
        if not await self.redis.set(f"lock:{key}", self.settings.worker_id, nx=True, px=2000):
            return
        try:
            entries = [json.loads(x) for x in await self.redis.lrange(key, 0, size - 1)]
            if not entries:
                return
            waited_ms = time.time() * 1000 - entries[0]["t"]
            if (
                len(entries) < size
                and waited_ms < self.settings.quick_match_wait_s * 1000 * self.settings.time_scale
            ):
                return
            await self.redis.ltrim(key, len(entries), -1)
            await self._start_room(mode, size, entries)
        finally:
            await self.redis.delete(f"lock:{key}")

    async def _start_room(self, mode: Mode, size: int, entries: list[dict]) -> None:
        code = await store.new_code(self.redis)
        seats = [
            Seat(
                player_id=e["pid"],
                name=e["name"] or "لاعب",
                army=Army(e["army"]) if e.get("army") else self.rnd.choice(list(Army)),
                ready=True,
            )
            for e in entries
        ]
        names = [n for n in BOT_NAMES if n not in {s.name for s in seats}]
        while len(seats) < size:
            seats.append(
                Seat(
                    name=names.pop(0) if names else "بوت",
                    army=self.rnd.choice(list(Army)),
                    ready=True,
                    bot=Difficulty.MEDIUM,
                )
            )
        self.rnd.shuffle(seats)
        delay_ms = int(START_PAUSE_MS * self.settings.time_scale)
        room = RoomData(
            code=code,
            host=entries[0]["pid"],
            settings=RoomSettings(mode=mode, max_players=size),
            seats=seats,
            quick=True,
            timers={"autostart": store.Timer(at_ms=int(time.time() * 1000) + delay_ms)},
        )
        await store.save_room(self.redis, room)
        for e in entries:
            await self.redis.set(store.k_player_room(e["pid"]), code)
        await self.manager.ensure_owner(code)
        for e in entries:
            await self.bus.publish(
                store.ch_player(e["pid"]), {"type": "match_found", "payload": {"code": code}}
            )
