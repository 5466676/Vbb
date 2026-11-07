"""FastAPI application entry point."""

from __future__ import annotations

import asyncio
import contextlib
from collections.abc import AsyncIterator
from pathlib import Path

from fastapi import FastAPI, WebSocket
from redis.asyncio import Redis

from app import __version__
from app.api.admin import router as admin_router
from app.api.auth import router as auth_router
from app.api.health import router as health_router
from app.api.sync import router as sync_router
from app.config import Settings, get_settings
from app.db import make_engine, make_sessionmaker
from app.questions.bank import DbProvider, FallbackProvider
from app.questions.provider import ProviderFactory, SampleProvider
from app.redis import set_redis
from app.rooms.bus import Bus
from app.rooms.hub import Hub
from app.rooms.manager import RoomManager
from app.rooms.matchmaker import Matchmaker
from app.sync.results import db_results_sink


def make_redis(url: str) -> Redis:
    """``memory://`` runs an in-process Redis (home server: one process, nothing to install)."""
    if url.startswith("memory://"):
        import fakeredis

        return fakeredis.FakeAsyncRedis(server=fakeredis.FakeServer())
    return Redis.from_url(url)


def db_provider_factory(sessionmaker, settings: Settings) -> ProviderFactory:
    def make(categories: list[str], packs: list[str]) -> FallbackProvider:
        primary = DbProvider(
            sessionmaker,
            categories,
            packs,
            only_reviewed=settings.only_reviewed_questions,
            seen_window_days=settings.seen_window_days,
        )
        return FallbackProvider(primary, SampleProvider())

    return make


def create_app(
    settings: Settings | None = None,
    provider_factory: ProviderFactory | None = None,
) -> FastAPI:
    settings = settings or get_settings()

    @contextlib.asynccontextmanager
    async def lifespan(app: FastAPI) -> AsyncIterator[None]:
        redis = make_redis(settings.redis_url)
        set_redis(redis)
        engine = make_engine(settings.database_url)
        sessionmaker = make_sessionmaker(engine)
        app.state.sessionmaker = sessionmaker
        factory = provider_factory or db_provider_factory(sessionmaker, settings)
        bus = Bus(redis)
        await bus.start()
        manager = RoomManager(redis, bus, settings, factory, db_results_sink(sessionmaker))
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
            await engine.dispose()

    app = FastAPI(title="حرب العقول", version=__version__, lifespan=lifespan)
    app.state.settings = settings
    app.include_router(health_router)
    app.include_router(auth_router)
    app.include_router(admin_router)
    app.include_router(sync_router)

    if settings.web_dir and Path(settings.web_dir).is_dir():
        from fastapi.staticfiles import StaticFiles

        app.mount("/play", StaticFiles(directory=settings.web_dir, html=True), name="web")

    @app.websocket("/ws")
    async def ws_endpoint(ws: WebSocket) -> None:
        await app.state.hub.serve(ws)

    return app


app = create_app()
