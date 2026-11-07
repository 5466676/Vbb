"""Shared async Redis client for this process."""

from __future__ import annotations

from redis.asyncio import Redis

_client: Redis | None = None


def set_redis(client: Redis) -> None:
    global _client
    _client = client


def get_redis() -> Redis:
    if _client is None:
        raise RuntimeError("Redis is not initialised (app lifespan not started)")
    return _client
