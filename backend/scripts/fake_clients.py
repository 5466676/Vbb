"""Fake players that play a full match over the real WebSocket protocol.

Usage (server running, e.g. docker compose up):
    python -m scripts.fake_clients --url http://localhost:8000 --players 8

The first client creates a room, the others join by code, everyone picks an army and gets
ready, the host starts, and all clients answer, pick and attack until ``match_ended``.
The same client is used by the integration tests.
"""

from __future__ import annotations

import argparse
import asyncio
import json
import random
import time
import uuid
from typing import Any

import httpx
import websockets

from app.maps import load_template

ARMIES = ["islamic", "ayyubid", "crusader", "roman", "pharaoh", "mongol", "ottoman", "ww2"]


class FakeClient:
    def __init__(self, base_url: str, name: str, seed: int = 0, answer_rate: float = 0.9) -> None:
        self.base = base_url.rstrip("/")
        self.name = name
        self.rnd = random.Random(seed)
        self.answer_rate = answer_rate
        self.device = uuid.uuid4().hex
        self.token = ""
        self.pid = ""
        self.ws = None
        self.seq = 0
        self.inbox: asyncio.Queue[dict] = asyncio.Queue()
        self.log: list[dict] = []
        self.errors: list[dict] = []
        self.room: dict[str, Any] = {}
        self.seat: int | None = None
        self.template: dict | None = None
        self.owners: dict[int, int | None] = {}
        self.ended: dict | None = None
        self.auto = False  # react to game messages by itself
        self._reader: asyncio.Task | None = None
        self._acts: set[asyncio.Task] = set()

    # ---------------------------------------------------------------- connection

    async def login(self) -> None:
        async with httpx.AsyncClient() as http:
            r = await http.post(
                f"{self.base}/auth/guest", json={"device_id": self.device, "name": self.name}
            )
            r.raise_for_status()
            data = r.json()
        self.token, self.pid = data["token"], data["player_id"]

    async def connect(self) -> None:
        if not self.token:
            await self.login()
        ws_url = self.base.replace("http", "ws", 1) + "/ws"
        self.ws = await websockets.connect(
            ws_url, max_size=2**22, additional_headers={"Authorization": f"Bearer {self.token}"}
        )
        self._reader = asyncio.create_task(self._read())

    async def close(self) -> None:
        if self.ws is not None:
            await self.ws.close()
        if self._reader:
            self._reader.cancel()
        for t in list(self._acts):
            t.cancel()

    async def send(self, type_: str, payload: dict | None = None) -> None:
        self.seq += 1
        await self.ws.send(json.dumps({"type": type_, "seq": self.seq, "payload": payload or {}}))

    async def wait_for(self, type_: str, timeout: float = 10, pred=None) -> dict:
        end = time.monotonic() + timeout
        while True:
            for msg in self.log:
                if (
                    msg["type"] == type_
                    and not msg.get("_seen")
                    and (pred is None or pred(msg["payload"]))
                ):
                    msg["_seen"] = True
                    return msg["payload"]
            left = end - time.monotonic()
            if left <= 0:
                raise TimeoutError(
                    f"{self.name}: no {type_} (last: {[m['type'] for m in self.log[-8:]]})"
                )
            try:
                await asyncio.wait_for(self.inbox.get(), timeout=left)
            except TimeoutError:
                pass

    async def _read(self) -> None:
        try:
            async for text in self.ws:
                msg = json.loads(text)
                self.log.append(msg)
                if msg["type"] == "error":
                    self.errors.append(msg["payload"])
                try:
                    self._track(msg)
                except Exception as e:  # never let tracking kill the reader
                    self.errors.append({"code": "client_track", "message": repr(e)})
                if self.auto:
                    self._react(msg)
                self.inbox.put_nowait(msg)
        except websockets.ConnectionClosed:
            pass

    # ---------------------------------------------------------------- state tracking

    def _track(self, msg: dict) -> None:
        t, p = msg["type"], msg["payload"]
        if t == "room_state":
            self.room = p
            for s in p["seats"]:
                if s["player_id"] == self.pid:
                    self.seat = s["seat"]
        elif t == "match_started":
            self.template = load_template(p["map_id"])
            self.owners = {x["id"]: None for x in self.template["territories"]}
            for seat, base in enumerate(p["bases"][: len(p["players"])]):
                self.owners[base] = seat
        elif t in ("territory_claimed", "base_placed"):
            self.owners[p["territory"]] = p["seat"]
        elif t == "territory_captured":
            self.owners[p["territory"]] = p["attacker"]
        elif t == "player_eliminated":
            for tid in p["territories"]:
                self.owners[tid] = p["by"]
        elif t == "full_state":
            self.room = p["room"]
            m = p.get("match")
            if m:
                self.seat = m["your_seat"]
                self.template = load_template(m["map_id"])
                self.owners = {x["id"]: x["owner"] for x in m["territories"]}
        elif t == "match_ended":
            self.ended = p

    def legal_picks(self) -> list[int]:
        free = [t for t, o in self.owners.items() if o is None]
        nb = {x["id"]: x["neighbors"] for x in self.template["territories"]}
        adj = [t for t in free if any(self.owners.get(n) == self.seat for n in nb[t])]
        return adj or free

    # ---------------------------------------------------------------- automatic play

    def _later(self, coro) -> None:
        task = asyncio.create_task(coro)
        self._acts.add(task)
        task.add_done_callback(self._acts.discard)

    def _react(self, msg: dict) -> None:
        t, p = msg["type"], msg["payload"]
        if t == "question" and p["participant"]:
            self._later(self._answer(p))
        elif t == "full_state" and (q := (p.get("match") or {}).get("question")):
            if q["participant"] and not q["answered"]:
                self._later(self._answer(q))
        elif (
            t == "phase_changed" and p["phase"] == "base_placement" and p.get("placer") == self.seat
        ):
            self._later(self._place(p.get("options", []), p.get("opens_in_ms", 0)))
        elif t == "phase_changed" and p["phase"] == "expansion_picks":
            quota = p.get("quota", {}).get(str(self.seat), 0)
            if quota:
                self._later(self._pick(quota, p.get("opens_in_ms", 0)))
        elif (
            t == "phase_changed"
            and p["phase"] == "battle_target"
            and p.get("attacker") == self.seat
        ):
            self._later(self._target(p["targets"], p.get("opens_in_ms", 0)))

    async def _answer(self, q: dict) -> None:
        await asyncio.sleep(self.rnd.uniform(0.05, 0.5) * q["time_ms"] / 1000)
        if self.rnd.random() > self.answer_rate:
            return
        if q["kind"] == "mcq":
            await self.send("answer", {"question_id": q["id"], "choice": self.rnd.randrange(4)})
        else:
            await self.send("answer", {"question_id": q["id"], "value": self.rnd.randint(0, 3000)})

    async def _place(self, options: list[int], opens_in_ms: int) -> None:
        await asyncio.sleep(opens_in_ms / 1000 + 0.02)
        if options:
            await self.send("place_base", {"territory": self.rnd.choice(options)})

    async def _pick(self, quota: int, opens_in_ms: int) -> None:
        await asyncio.sleep(opens_in_ms / 1000 + 0.02)
        legal = self.legal_picks()
        await self.send(
            "pick_territory", {"territories": self.rnd.sample(legal, min(quota, len(legal)))}
        )

    async def _target(self, targets: list[int], opens_in_ms: int) -> None:
        await asyncio.sleep(opens_in_ms / 1000 + 0.02)
        await self.send("choose_target", {"territory": self.rnd.choice(targets)})


async def play_room(
    base_url: str, players: int, timeout: float = 600, mode: str = "ffa"
) -> list[FakeClient]:
    """Create a room, fill it with ``players`` fake clients, play to the end."""
    clients = [FakeClient(base_url, f"لاعب {i + 1}", seed=i) for i in range(players)]
    for c in clients:
        await c.connect()
    host, *others = clients
    await host.send("create_room", {"army": ARMIES[0]})
    state = await host.wait_for("room_state")
    code = state["code"]
    if mode != "ffa":
        await host.send("update_settings", {"mode": mode})
    for i, c in enumerate(others, start=1):
        await c.send("join_room", {"code": code, "army": ARMIES[i % len(ARMIES)]})
        await c.wait_for(
            "room_state", pred=lambda p, c=c: any(s["player_id"] == c.pid for s in p["seats"])
        )
    for i, c in enumerate(clients):
        await c.send("vote_map", {"kind": "fantasy" if i % 2 else "world"})
        await c.send("set_ready", {"ready": True})
    await host.wait_for("room_state", pred=lambda p: sum(s["ready"] for s in p["seats"]) == players)
    for c in clients:
        c.auto = True
    await host.send("start_match")
    await asyncio.gather(*(c.wait_for("match_ended", timeout=timeout) for c in clients))
    return clients


async def _main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", default="http://localhost:8000")
    ap.add_argument("--players", type=int, default=8)
    ap.add_argument("--mode", default="ffa")
    args = ap.parse_args()
    t0 = time.monotonic()
    clients = await play_room(args.url, args.players, mode=args.mode)
    end = clients[0].ended
    print(f"match finished in {time.monotonic() - t0:.0f} s; winner team {end['winner_team']}")
    for row in end["standings"]:
        print(f"  seat {row['seat']}: score {row['score']} correct {row['correct']}")
    errors = sum(len(c.errors) for c in clients)
    print(f"errors received by clients: {errors}")
    for c in clients:
        await c.close()


if __name__ == "__main__":
    asyncio.run(_main())
