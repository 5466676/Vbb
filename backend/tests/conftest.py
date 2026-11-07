"""Fixtures for integration tests: a real redis-server and real uvicorn servers."""

from __future__ import annotations

import asyncio
import glob
import os
import shutil
import socket
import subprocess
import sys
import tempfile
import time
import uuid
from collections.abc import AsyncIterator
from pathlib import Path

import pytest
import redis
import uvicorn

from app.config import Settings
from app.main import create_app


def free_port() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


BACKEND = Path(__file__).resolve().parents[1]


def _pg_bin() -> str | None:
    found = sorted(glob.glob("/usr/lib/postgresql/*/bin/pg_ctl"))
    if found:
        return str(Path(found[-1]).parent)
    exe = shutil.which("pg_ctl")
    return str(Path(exe).parent) if exe else None


def _as_postgres(cmd: list[str]) -> list[str]:
    """initdb/pg_ctl refuse to run as root."""
    if os.geteuid() == 0:
        return ["su", "postgres", "-c", " ".join(cmd)]
    return cmd


@pytest.fixture(scope="session")
def pg_server() -> str:
    """A throwaway PostgreSQL with a ``harb_template`` database (migrated + seeded)."""
    bindir = _pg_bin()
    if bindir is None:
        pytest.skip("PostgreSQL is not installed")
    base = tempfile.mkdtemp(prefix="harbpg.", dir="/tmp")
    os.chmod(base, 0o755)
    if os.geteuid() == 0:
        shutil.chown(base, "postgres")
    port = free_port()
    data = f"{base}/data"
    subprocess.run(
        _as_postgres([f"{bindir}/initdb", "-D", data, "-A", "trust", "-U", "harb"]),
        check=True,
        stdout=subprocess.DEVNULL,
    )
    opts = f"'-p {port} -k {base} -c listen_addresses=127.0.0.1 -c fsync=off'"
    subprocess.run(
        _as_postgres(
            [f"{bindir}/pg_ctl", "-D", data, "-o", opts, "-l", f"{base}/log", "-w", "start"]
        ),
        check=True,
        stdout=subprocess.DEVNULL,
    )
    root = f"postgresql+asyncpg://harb@127.0.0.1:{port}"
    asyncio.run(_admin(root, "CREATE DATABASE harb_template"))
    url = f"{root}/harb_template"
    subprocess.run(
        [sys.executable, "-m", "alembic", "-x", f"url={url}", "upgrade", "head"],
        cwd=BACKEND,
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    asyncio.run(_seed(url))
    yield root
    subprocess.run(
        _as_postgres([f"{bindir}/pg_ctl", "-D", data, "-m", "immediate", "stop"]),
        stdout=subprocess.DEVNULL,
    )
    shutil.rmtree(base, ignore_errors=True)


async def _admin(root: str, sql: str) -> None:
    from sqlalchemy import text
    from sqlalchemy.ext.asyncio import create_async_engine

    engine = create_async_engine(f"{root}/postgres", isolation_level="AUTOCOMMIT")
    async with engine.connect() as conn:
        await conn.execute(text(sql))
    await engine.dispose()


async def _seed(url: str) -> None:
    from app.db import make_engine, make_sessionmaker
    from app.questions.bank import load_seed

    engine = make_engine(url)
    async with make_sessionmaker(engine)() as s:
        await load_seed(s)
    await engine.dispose()


@pytest.fixture
async def db_url(pg_server: str) -> AsyncIterator[str]:
    """A fresh database copied from the template (migrated + 304 seed questions)."""
    name = f"t_{uuid.uuid4().hex[:10]}"
    await _admin(pg_server, f"CREATE DATABASE {name} TEMPLATE harb_template")
    yield f"{pg_server}/{name}"
    await _admin(pg_server, f"DROP DATABASE IF EXISTS {name} WITH (FORCE)")


@pytest.fixture(scope="session")
def redis_url() -> str:
    exe = shutil.which("redis-server")
    if exe is None:
        pytest.skip("redis-server is not installed")
    port = free_port()
    proc = subprocess.Popen(
        [exe, "--port", str(port), "--save", "", "--appendonly", "no"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    client = redis.Redis(port=port)
    for _ in range(100):
        try:
            client.ping()
            break
        except redis.ConnectionError:
            time.sleep(0.05)
    client.close()
    yield f"redis://127.0.0.1:{port}/0"
    proc.terminate()
    proc.wait(timeout=5)


class Servers:
    """Start workers sharing one Redis (``await servers()`` -> base URL) and stop them."""

    def __init__(self, redis_url: str, database_url: str) -> None:
        self.redis_url = redis_url
        self.database_url = database_url
        self.running: dict[str, tuple[uvicorn.Server, asyncio.Task]] = {}

    async def __call__(self, time_scale: float = 0.02, **overrides) -> str:
        port = free_port()
        settings = Settings(
            redis_url=self.redis_url,
            database_url=self.database_url,
            time_scale=time_scale,
            jwt_secret="test-secret-for-integration-tests-0123456789",
            **overrides,
        )
        config = uvicorn.Config(
            create_app(settings),
            host="127.0.0.1",
            port=port,
            log_level="warning",
            ws="websockets-sansio",
        )
        server = uvicorn.Server(config)
        task = asyncio.create_task(server.serve())
        while not server.started:
            await asyncio.sleep(0.02)
        url = f"http://127.0.0.1:{port}"
        self.running[url] = (server, task)
        return url

    async def stop(self, url: str) -> None:
        server, task = self.running.pop(url)
        server.should_exit = True
        await task

    async def stop_all(self) -> None:
        for url in list(self.running):
            await self.stop(url)


@pytest.fixture
async def start_server(redis_url: str, db_url: str) -> AsyncIterator[Servers]:
    client = redis.Redis.from_url(redis_url)
    client.flushdb()
    client.close()
    servers = Servers(redis_url, db_url)
    yield servers
    await servers.stop_all()


@pytest.fixture(scope="session")
def sqlite_template(tmp_path_factory) -> Path:
    """A migrated + seeded SQLite file, copied for each test."""
    path = tmp_path_factory.mktemp("sqlite") / "template.db"
    url = f"sqlite+aiosqlite:///{path}"
    subprocess.run(
        [sys.executable, "-m", "alembic", "-x", f"url={url}", "upgrade", "head"],
        cwd=BACKEND,
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    asyncio.run(_seed(url))
    return path


@pytest.fixture
def sqlite_url(sqlite_template: Path, tmp_path: Path) -> str:
    path = tmp_path / "harb.db"
    shutil.copy(sqlite_template, path)
    return f"sqlite+aiosqlite:///{path}"


@pytest.fixture(params=["sqlite", "postgres"])
def any_db_url(request) -> str:
    """Run the test on both databases."""
    return request.getfixturevalue("sqlite_url" if request.param == "sqlite" else "db_url")


@pytest.fixture
async def home_server(any_db_url: str) -> AsyncIterator[Servers]:
    """Home mode: in-process Redis (``memory://``), SQLite or PostgreSQL."""
    servers = Servers("memory://", any_db_url)
    yield servers
    await servers.stop_all()
