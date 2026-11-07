"""FastAPI application entry point."""

from __future__ import annotations

import asyncio
import contextlib
from collections.abc import AsyncIterator, Callable

from fastapi import FastAPI, WebSocket
from redis.asyncio import Redis

from app import __version__
from app.api.auth import router as auth_router
from app.api.health import router as health_router
from app.config import Settings, get_settings
from app.questions.provider import QuestionProvider, SampleProvider
from app.redis import set_redis
from app.rooms.bus import Bus
from app.rooms.hub import Hub
from app.rooms.manager import RoomManager
from app.rooms.matchmaker import Matchmaker


def create_app(
    settings: Settings | None = None,
    provider_factory: Callable[[], QuestionProvider] = SampleProvider,
) -> FastAPI:
    settings = settings or get_settings()

    @contextlib.asynccontextmanager
    async def lifespan(app: FastAPI) -> AsyncIterator[None]:
        redis = Redis.from_url(settings.redis_url)
        set_redis(redis)
        bus = Bus(redis)
        await bus.start()
        manager = RoomManager(redis, bus, settings, provider_factory)
        hub = Hub(redis, bus, manager, settings)
        app.state.hub = hub
        app.state.redis = redis
        app.state.manager = manager
        tasks = [
            asyncio.create_task(Matchmaker(redis, bus, manager, settings).run()),
            asyncio.create_task(manager.watchdog(hub.local_rooms)),
        ]
        try:
            yield
        finally:
            for t in tasks:
                t.cancel()
            await manager.stop()
            await bus.stop()
            await redis.aclose()

    app = FastAPI(title="حرب العقول", version=__version__, lifespan=lifespan)
    app.state.settings = settings
    app.include_router(health_router)
    app.include_router(auth_router)

    @app.websocket("/ws")
    async def ws_endpoint(ws: WebSocket) -> None:
        await app.state.hub.serve(ws)

    return app


app = create_app()
