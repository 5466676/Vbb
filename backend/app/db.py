"""Async SQLAlchemy engine and session factory (PostgreSQL, or SQLite for the home server)."""

from __future__ import annotations

from typing import Any

from sqlalchemy import event
from sqlalchemy.dialects import postgresql, sqlite
from sqlalchemy.ext.asyncio import (
    AsyncEngine,
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)
from sqlalchemy.orm import DeclarativeBase


class Base(DeclarativeBase):
    pass


def is_sqlite(url: str) -> bool:
    return url.startswith("sqlite")


def make_engine(url: str) -> AsyncEngine:
    if not is_sqlite(url):
        return create_async_engine(url, pool_pre_ping=True)
    engine = create_async_engine(url, connect_args={"timeout": 15})

    @event.listens_for(engine.sync_engine, "connect")
    def _pragmas(dbapi_conn: Any, _record: Any) -> None:
        cur = dbapi_conn.cursor()
        cur.execute("PRAGMA journal_mode=WAL")  # readers do not block the writer
        cur.execute("PRAGMA synchronous=NORMAL")
        cur.execute("PRAGMA foreign_keys=ON")
        cur.execute("PRAGMA busy_timeout=15000")
        cur.close()

    return engine


def make_sessionmaker(engine: AsyncEngine) -> async_sessionmaker[AsyncSession]:
    return async_sessionmaker(engine, expire_on_commit=False)


def upsert(session: AsyncSession, table: Any) -> Any:
    """``INSERT`` with ``on_conflict_do_*`` for the session's database (PostgreSQL or SQLite)."""
    name = session.get_bind().dialect.name
    return (sqlite if name == "sqlite" else postgresql).insert(table)
