"""WebSocket connections on this worker.

One connection per player (a new one replaces the old). The hub authenticates, rate-limits,
numbers outgoing frames (``seq``), measures answer times **server-side** (from the moment it
wrote the question to this socket) and routes room messages to the room owner.
"""

from __future__ import annotations

import asyncio
import contextlib
import json
import logging
import time
from dataclasses import dataclass, field
from typing import Any

from fastapi import WebSocket, WebSocketDisconnect
from pydantic import ValidationError
from redis.asyncio import Redis

from app.auth import AuthError, verify_token
from app.config import Settings
from app.engine.armies import Army
from app.engine.models import Mode
from app.rooms import protocol, store
from app.rooms.bus import Bus
from app.rooms.manager import RoomManager
from app.rooms.store import RoomData

log = logging.getLogger(__name__)


@dataclass
class Connection:
    ws: WebSocket
    pid: str
    name: str
    seq_out: int = 0
    last_seq_in: int = 0
    room: str | None = None
    question_sent: dict[str, float] = field(default_factory=dict)
    tokens: float = 0.0
    last_refill: float = field(default_factory=time.monotonic)
    send_lock: asyncio.Lock = field(default_factory=asyncio.Lock)
    player_sub: int | None = None
    closed: bool = False

    async def send(self, type_: str, payload: dict[str, Any]) -> None:
        async with self.send_lock:
            if self.closed:
                return
            self.seq_out += 1
            if type_ == "question":
                self.question_sent[payload["id"]] = time.monotonic()
            elif type_ == "full_state":
                q = (payload.get("match") or {}).get("question")
                if q:
                    self.question_sent[q["id"]] = time.monotonic() - q["elapsed_ms"] / 1000
            try:
                await self.ws.send_text(protocol.encode(type_, self.seq_out, payload))
            except Exception:
                self.closed = True


class Hub:
    def __init__(self, redis: Redis, bus: Bus, manager: RoomManager, settings: Settings) -> None:
        self.redis = redis
        self.bus = bus
        self.manager = manager
        self.settings = settings
        self.conns: dict[str, Connection] = {}
        self.room_subs: dict[str, int] = {}

    def local_rooms(self) -> set[str]:
        return {c.room for c in self.conns.values() if c.room}

    # ------------------------------------------------------------------ socket lifecycle

    async def serve(self, ws: WebSocket) -> None:
        auth = ws.headers.get("authorization", "")
        # header preferred (not written to access logs); query string kept for simple clients
        token = auth[7:] if auth.lower().startswith("bearer ") else ws.query_params.get("token", "")
        try:
            pid, name = verify_token(self.settings, token)
        except AuthError:
            await ws.close(code=4401, reason="bad token")
            return
        await ws.accept()
        old = self.conns.get(pid)
        if old:
            old.closed = True
            with contextlib.suppress(Exception):
                await old.ws.close(code=4001, reason="replaced by a new connection")
        conn = Connection(ws=ws, pid=pid, name=name, tokens=self.settings.rate_burst)
        self.conns[pid] = conn
        conn.player_sub = await self.bus.subscribe(
            store.ch_player(pid), lambda d, c=conn: self._on_player(c, d)
        )
        await conn.send(
            "welcome", {"player_id": pid, "name": name, "server_time_ms": int(time.time() * 1000)}
        )
        code = await self.redis.get(store.k_player_room(pid))
        if code:
            await self._attach(conn, code.decode())
            await self.manager.send(conn.room, {"kind": "connected", "pid": pid})
        try:
            while True:
                text = await ws.receive_text()
                await self._on_frame(conn, text)
        except (WebSocketDisconnect, RuntimeError):
            pass
        finally:
            await self._closed(conn)

    async def _closed(self, conn: Connection) -> None:
        conn.closed = True
        if self.conns.get(conn.pid) is conn:
            del self.conns[conn.pid]
            await self._dequeue(conn.pid)
            if conn.room:
                await self.manager.send(conn.room, {"kind": "disconnected", "pid": conn.pid})
        if conn.player_sub is not None:
            await self.bus.unsubscribe(store.ch_player(conn.pid), conn.player_sub)
        await self._release_room(conn.room)

    # ------------------------------------------------------------------ rooms

    async def _attach(self, conn: Connection, code: str) -> None:
        old = conn.room
        conn.room = code
        if code not in self.room_subs:
            self.room_subs[code] = await self.bus.subscribe(
                store.ch_room_out(code), lambda d, c=code: self._on_room(c, d)
            )
        if old and old != code:
            await self._release_room(old)

    async def _release_room(self, code: str | None) -> None:
        if code and code in self.room_subs and code not in self.local_rooms():
            await self.bus.unsubscribe(store.ch_room_out(code), self.room_subs.pop(code))

    async def _on_room(self, code: str, data: dict[str, Any]) -> None:
        to = data.get("to")
        for conn in list(self.conns.values()):
            if conn.room != code or (to is not None and conn.pid not in to):
                continue
            await conn.send(data["type"], data["payload"])
            if data["type"] == "left_room" or data.get("detach"):
                conn.room = None
                await self._release_room(code)

    async def _on_player(self, conn: Connection, data: dict[str, Any]) -> None:
        if data.get("type") == "match_found":
            await self._attach(conn, data["payload"]["code"])
            await self.manager.send(conn.room, {"kind": "connected", "pid": conn.pid})
        await conn.send(data["type"], data.get("payload", {}))

    # ------------------------------------------------------------------ frames

    def _rate_ok(self, conn: Connection) -> bool:
        now = time.monotonic()
        conn.tokens = min(
            self.settings.rate_burst,
            conn.tokens + (now - conn.last_refill) * self.settings.rate_per_s,
        )
        conn.last_refill = now
        if conn.tokens < 1:
            return False
        conn.tokens -= 1
        return True

    async def _on_frame(self, conn: Connection, text: str) -> None:
        if not self._rate_ok(conn):
            await conn.send("error", protocol.error_payload("rate_limited", "too many messages"))
            return
        try:
            env = protocol.Envelope.model_validate_json(text)
        except ValidationError:
            await conn.send("error", protocol.error_payload("bad_frame", "invalid message"))
            return
        if env.type not in protocol.CLIENT_TYPES:
            await conn.send(
                "error", protocol.error_payload("bad_type", f"unknown type {env.type}", env.seq)
            )
            return
        if env.seq and env.seq <= conn.last_seq_in:
            await conn.send(
                "error", protocol.error_payload("duplicate", "duplicate or old seq", env.seq)
            )
            return
        conn.last_seq_in = max(conn.last_seq_in, env.seq)
        p = env.payload
        if env.type == "ping":
            await conn.send("pong", {"t": p.get("t"), "server_time_ms": int(time.time() * 1000)})
        elif env.type == "create_room":
            await self._create_room(conn, p, env.seq)
        elif env.type == "join_room":
            await self._join_room(conn, str(p.get("code", "")).upper(), p.get("army"), env.seq)
        elif env.type == "quick_match":
            await self._quick_match(conn, p, env.seq)
        elif env.type == "cancel_quick_match":
            await self._dequeue(conn.pid)
            await conn.send("quick_match_cancelled", {})
        else:
            if not conn.room:
                await conn.send(
                    "error", protocol.error_payload("not_in_room", "join a room first", env.seq)
                )
                return
            item: dict[str, Any] = {
                "kind": "client",
                "pid": conn.pid,
                "type": env.type,
                "payload": p,
                "seq": env.seq,
            }
            if env.type == "answer":
                sent = conn.question_sent.get(str(p.get("question_id")))
                item["elapsed_ms"] = int((time.monotonic() - sent) * 1000) if sent else 10**9
            await self.manager.send(conn.room, item)

    async def _busy(self, conn: Connection, seq: int) -> bool:
        if conn.room and await self.redis.exists(store.k_room(conn.room)):
            await conn.send(
                "error",
                protocol.error_payload("already_in_room", "leave your current room first", seq),
            )
            return True
        return False

    async def _create_room(self, conn: Connection, p: dict[str, Any], seq: int) -> None:
        if await self._busy(conn, seq):
            return
        code = await store.new_code(self.redis)
        await store.save_room(self.redis, RoomData(code=code, host=None))
        await self._attach(conn, code)
        await self.manager.send(
            code, {"kind": "join", "pid": conn.pid, "name": conn.name, "army": p.get("army")}
        )

    async def _join_room(self, conn: Connection, code: str, army: str | None, seq: int) -> None:
        if conn.room == code:
            await self.manager.send(
                code, {"kind": "join", "pid": conn.pid, "name": conn.name, "army": army}
            )
            return
        if await self._busy(conn, seq):
            return
        if not await self.redis.exists(store.k_room(code)):
            await conn.send(
                "error", protocol.error_payload("no_room", "no room with this code", seq)
            )
            return
        await self._attach(conn, code)
        await self.manager.send(
            code, {"kind": "join", "pid": conn.pid, "name": conn.name, "army": army}
        )

    async def _quick_match(self, conn: Connection, p: dict[str, Any], seq: int) -> None:
        if await self._busy(conn, seq):
            return
        try:
            mode = Mode(p.get("mode", "ffa"))
            size = int(p.get("size", 4))
        except ValueError:
            await conn.send("error", protocol.error_payload("bad_queue", "bad mode or size", seq))
            return
        ok_sizes = (4, 6, 8) if mode is Mode.TEAMS else range(2, 9)
        if size not in ok_sizes:
            await conn.send(
                "error", protocol.error_payload("bad_queue", "bad size for this mode", seq)
            )
            return
        army = p.get("army") if p.get("army") in {a.value for a in Army} else None
        await self._dequeue(conn.pid)
        entry = {"pid": conn.pid, "name": conn.name, "army": army, "t": int(time.time() * 1000)}
        await self.redis.rpush(store.k_queue(mode, size), json.dumps(entry, ensure_ascii=False))
        await conn.send("queued", {"mode": mode.value, "size": size})

    async def _dequeue(self, pid: str) -> None:
        for mode, sizes in ((Mode.FFA, range(2, 9)), (Mode.TEAMS, (4, 6, 8))):
            for size in sizes:
                key = store.k_queue(mode, size)
                for raw in await self.redis.lrange(key, 0, -1):
                    if json.loads(raw)["pid"] == pid:
                        await self.redis.lrem(key, 0, raw)
