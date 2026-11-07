"""Redis pub/sub for one worker process: many local subscribers share one connection."""

from __future__ import annotations

import asyncio
import contextlib
import json
import logging
from collections import defaultdict
from collections.abc import Awaitable, Callable
from typing import Any

from redis.asyncio import Redis

log = logging.getLogger(__name__)
Handler = Callable[[dict[str, Any]], Awaitable[None] | None]


class Bus:
    def __init__(self, redis: Redis) -> None:
        self.redis = redis
        self.pubsub = redis.pubsub()
        self.handlers: dict[str, dict[int, Handler]] = defaultdict(dict)
        self._next = 0
        self._task: asyncio.Task | None = None

    async def start(self) -> None:
        self._task = asyncio.create_task(self._reader())

    async def stop(self) -> None:
        if self._task:
            self._task.cancel()
            with contextlib.suppress(asyncio.CancelledError):
                await self._task
        await self.pubsub.aclose()

    async def subscribe(self, channel: str, handler: Handler) -> int:
        self._next += 1
        first = not self.handlers[channel]
        self.handlers[channel][self._next] = handler
        if first:
            await self.pubsub.subscribe(channel)
        return self._next

    async def unsubscribe(self, channel: str, token: int) -> None:
        subs = self.handlers.get(channel)
        if not subs or token not in subs:
            return
        del subs[token]
        if not subs:
            del self.handlers[channel]
            await self.pubsub.unsubscribe(channel)

    async def publish(self, channel: str, data: dict[str, Any]) -> None:
        await self.redis.publish(channel, json.dumps(data, ensure_ascii=False))

    async def _reader(self) -> None:
        while True:
            if not self.handlers:
                await asyncio.sleep(0.02)
                continue
            try:
                msg = await self.pubsub.get_message(ignore_subscribe_messages=True, timeout=0.5)
            except Exception:  # connection hiccup: keep the worker alive
                log.exception("pubsub read failed")
                await asyncio.sleep(0.2)
                continue
            if not msg or msg.get("type") != "message":
                continue
            channel = (
                msg["channel"].decode() if isinstance(msg["channel"], bytes) else msg["channel"]
            )
            data = json.loads(msg["data"])
            for handler in list(self.handlers.get(channel, {}).values()):
                try:
                    res = handler(data)
                    if asyncio.iscoroutine(res):
                        await res
                except Exception:
                    log.exception("bus handler failed for %s", channel)
