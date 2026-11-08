"""The room owner: one asyncio task per room, on the worker that holds the room's lease.

It is the only writer of the room record. Inputs arrive in the room inbox (a Redis list,
woken by a pub/sub notify); outputs are published on ``room:{code}:out`` and delivered to
sockets by every worker's hub. Timers live here and feed ``Timeout`` actions to the engine.

Durations from the engine (answer limits) are in "game ms". Real waiting is
``game_ms * settings.time_scale`` so tests can run a full match in seconds.
"""

from __future__ import annotations

import asyncio
import contextlib
import json
import logging
import random
import time
import uuid
from collections.abc import Awaitable, Callable
from typing import Any

from redis.asyncio import Redis

from app.bots import simple as bots
from app.bots.simple import Difficulty
from app.config import Settings
from app.engine import core
from app.engine.armies import Army
from app.engine.models import (
    Answer,
    ChooseTarget,
    Event,
    MatchSettings,
    Mode,
    Phase,
    PickTerritories,
    PlaceBase,
    PlayerSetup,
    PowerUp,
    ProvideQuestion,
    QuestionKind,
    SetConnected,
    StartMatch,
    Timeout,
    UseAbility,
    UsePowerUp,
)
from app.maps import MapKind, load_template, map_for, template_id
from app.models.question import CATEGORIES
from app.questions.provider import ProviderFactory, QuestionProvider, SampleProvider
from app.rooms import store
from app.rooms.bus import Bus
from app.rooms.store import RoomData, RoomStatus, Seat

log = logging.getLogger(__name__)
# called once per finished match: (match_uid, room) -> saves results somewhere
ResultsSink = Callable[[str, RoomData], Awaitable[None]]

# pauses after events so the client can animate (game ms)
START_PAUSE_MS = 4500
REVEAL_PAUSE_MS = 4000
NUMERIC_REVEAL_PAUSE_MS = 6500  # the arrows fly into the target one by one
CLAIM_PAUSE_MS = 2500
DUEL_PAUSE_MS = 4500
BASE_PAUSE_MS = 1800  # a castle lands before the next player places theirs
MARCH_PAUSE_MS = 3500  # the attacker's troops march to the target before the duel question
NETWORK_SLACK_MS = 500  # extra wait before a question timeout
ENDED_TTL_MS = 5 * 60_000
BOT_NAMES = ["صلاح", "خالد", "طارق", "زنوبيا", "هارون", "بيبرس", "قطز", "سيف"]


def now_ms() -> int:
    return int(time.time() * 1000)


class RoomError(Exception):
    def __init__(self, code: str, message: str) -> None:
        super().__init__(message)
        self.code = code


class RoomActor:
    def __init__(
        self,
        code: str,
        redis: Redis,
        bus: Bus,
        settings: Settings,
        provider_factory: ProviderFactory = SampleProvider,
        on_stop: Callable[[str], None] | None = None,
        results_sink: ResultsSink | None = None,
    ) -> None:
        self.code = code
        self.redis = redis
        self.bus = bus
        self.settings = settings
        self.provider_factory = provider_factory
        self._provider: QuestionProvider | None = None
        self.on_stop = on_stop
        self.results_sink = results_sink
        self.room: RoomData | None = None
        self.queue: asyncio.Queue[tuple[str, Any]] = asyncio.Queue()
        self.handles: dict[str, asyncio.TimerHandle] = {}
        self.rnd = random.Random()
        self.task: asyncio.Task | None = None
        self._sub: int | None = None

    # ------------------------------------------------------------------ lifecycle

    async def start(self) -> None:
        self.room = await store.load_room(self.redis, self.code)
        if self.room is None:
            raise RoomError("no_room", "room not found")
        self._sub = await self.bus.subscribe(store.ch_room_in(self.code), self._notify)
        for name, timer in list(self.room.timers.items()):  # recover timers after a takeover
            self._arm(name, max(0, timer.at_ms - now_ms()) / 1000)
        self.task = asyncio.create_task(self._run())
        self.queue.put_nowait(("drain", None))

    def provider(self) -> QuestionProvider:
        assert self.room is not None
        if self._provider is None:
            self._provider = self.provider_factory(
                self.room.settings.categories, self.room.settings.packs
            )
        return self._provider

    async def stop(self) -> None:
        for h in self.handles.values():
            h.cancel()
        if self._sub is not None:
            await self.bus.unsubscribe(store.ch_room_in(self.code), self._sub)
        if self.task and self.task is not asyncio.current_task():
            self.task.cancel()
            with contextlib.suppress(asyncio.CancelledError):
                await self.task

    def _notify(self, _data: dict) -> None:
        self.queue.put_nowait(("drain", None))

    async def _run(self) -> None:
        lease_every = self.settings.room_lease_s / 3
        next_lease = 0.0
        try:
            while True:
                if time.monotonic() >= next_lease:
                    if not await self._renew_lease():
                        log.warning("lost lease for room %s", self.code)
                        return
                    next_lease = time.monotonic() + lease_every
                try:
                    kind, data = await asyncio.wait_for(self.queue.get(), timeout=lease_every)
                except TimeoutError:
                    continue
                if kind == "drain":
                    await self._drain()
                elif kind == "timer":
                    await self._fire(data)
                if self.room and self.room.status is RoomStatus.ENDED and not self.room.timers:
                    await self._cleanup()
                    return
        finally:
            if self.on_stop:
                self.on_stop(self.code)

    async def _renew_lease(self) -> bool:
        key = store.k_owner(self.code)
        ttl = int(self.settings.room_lease_s * 1000)
        owner = await self.redis.get(key)
        if owner is not None and owner.decode() != self.settings.worker_id:
            return False
        await self.redis.set(key, self.settings.worker_id, px=ttl)
        return True

    async def _drain(self) -> None:
        while True:
            raw = await self.redis.lpop(store.k_inbox(self.code))
            if raw is None:
                return
            await self._handle_input(json.loads(raw))

    async def _cleanup(self) -> None:
        assert self.room is not None
        for pid in self.room.humans():
            key = store.k_player_room(pid)
            if (await self.redis.get(key)) == self.code.encode():
                await self.redis.delete(key)
        await self.redis.delete(
            store.k_room(self.code), store.k_inbox(self.code), store.k_owner(self.code)
        )

    # ------------------------------------------------------------------ timers

    def _scaled_s(self, game_ms: float) -> float:
        return game_ms * self.settings.time_scale / 1000

    def _schedule(self, name: str, game_ms: float, **data: Any) -> None:
        assert self.room is not None
        delay = self._scaled_s(game_ms)
        self.room.timers[name] = store.Timer(at_ms=now_ms() + int(delay * 1000), data=data)
        self._arm(name, delay)

    def _arm(self, name: str, delay_s: float) -> None:
        old = self.handles.pop(name, None)
        if old:
            old.cancel()
        loop = asyncio.get_running_loop()
        self.handles[name] = loop.call_later(delay_s, self.queue.put_nowait, ("timer", name))

    def _cancel(self, name: str) -> None:
        h = self.handles.pop(name, None)
        if h:
            h.cancel()
        if self.room:
            self.room.timers.pop(name, None)

    async def _fire(self, name: str) -> None:
        assert self.room is not None
        timer = self.room.timers.pop(name, None)
        self.handles.pop(name, None)
        if timer is None:
            return
        try:
            await self._on_timer(name, timer.data)
        except core.RuleError as e:  # a bot or a late timer raced a phase change
            log.debug("timer %s ignored: %s", name, e)
        except Exception:
            log.exception("room %s timer %s failed", self.code, name)
        await self._save()

    # ------------------------------------------------------------------ output

    async def _send(self, to: list[str] | None, type_: str, payload: dict[str, Any]) -> None:
        await self.bus.publish(
            store.ch_room_out(self.code), {"to": to, "type": type_, "payload": payload}
        )

    async def _error(self, pid: str, code: str, message: str, ref: int | None = None) -> None:
        await self._send([pid], "error", {"code": code, "message": message, "ref": ref})

    async def _save(self) -> None:
        assert self.room is not None
        await store.save_room(self.redis, self.room)

    def _room_state(self) -> dict[str, Any]:
        r = self.room
        assert r is not None
        return {
            "code": r.code,
            "host": r.host,
            "status": r.status.value,
            "settings": r.settings.model_dump(mode="json"),
            "seats": [
                {
                    "seat": i,
                    "player_id": s.player_id,
                    "name": s.name,
                    "army": s.army.value,
                    "ready": s.ready,
                    "bot": s.bot.value if s.bot else None,
                    "connected": s.connected,
                    "away": s.away,
                }
                for i, s in enumerate(r.seats)
            ],
            "votes": {pid: k.value for pid, k in r.votes.items()},
            "quick": r.quick,
        }

    async def _broadcast_room(self) -> None:
        await self._send(None, "room_state", self._room_state())

    # ------------------------------------------------------------------ input

    async def _handle_input(self, item: dict[str, Any]) -> None:
        assert self.room is not None
        pid = item.get("pid", "")
        kind = item["kind"]
        try:
            if kind == "join":
                await self._join(pid, item.get("name", ""), item.get("army"))
            elif kind == "connected":
                await self._connected(pid, True)
            elif kind == "disconnected":
                await self._connected(pid, False)
            elif kind == "client":
                await self._client(pid, item["type"], item.get("payload", {}), item)
        except RoomError as e:
            if kind == "join":  # the hub attached the socket optimistically: undo it
                payload = {"code": e.code, "message": str(e), "ref": item.get("seq")}
                await self.bus.publish(
                    store.ch_room_out(self.code),
                    {"to": [pid], "type": "error", "payload": payload, "detach": True},
                )
            else:
                await self._error(pid, e.code, str(e), item.get("seq"))
        except core.RuleError as e:
            await self._error(pid, "rule", str(e), item.get("seq"))
        except Exception:  # one bad message must never take the room down
            log.exception("room %s failed on %s", self.code, item.get("type") or kind)
            await self._error(pid, "internal", "server error", item.get("seq"))
        await self._save()

    async def _client(self, pid: str, type_: str, p: dict[str, Any], item: dict[str, Any]) -> None:
        r = self.room
        assert r is not None
        seat = r.seat_of(pid)
        if seat is None:
            raise RoomError("not_in_room", "you are not in this room")
        if type_ == "resync":  # the client lost track: send everything again
            await self._send([pid], "full_state", self.full_state(pid))
            return
        if r.status is RoomStatus.LOBBY:
            await self._lobby_message(pid, seat, type_, p)
            return
        if type_ == "leave_room":
            await self._leave(pid, seat)
            return
        if r.status is not RoomStatus.PLAYING or r.match is None:
            raise RoomError("not_playing", "the match is not running")
        if r.seats[seat].left:
            raise RoomError("left", "you left this match")
        if r.seats[seat].away:  # any move (or "back") ends the autopilot
            await self._set_away(seat, False)
        if type_ == "back":
            return
        action = self._to_action(seat, type_, p, item)
        if action is not None:
            await self._apply(action)

    def _owed(self) -> list[int]:
        """Seats that still owe a move in the current phase."""
        r = self.room
        assert r is not None and r.match is not None
        m = r.match
        if m.active is not None:
            return [s for s in m.active.participants if s not in m.active.answers]
        if m.phase is Phase.BASE_PLACEMENT and m.placer is not None:
            return [m.placer]
        if m.phase is Phase.EXP_PICKS:
            return [s for s in m.pick_quota if s not in m.picks]
        if m.phase is Phase.BATTLE_TARGET:
            return [x for x in m.planners if x not in m.planned]
        return []

    async def _set_away(self, seat: int, away: bool) -> None:
        r = self.room
        assert r is not None
        r.seats[seat].away = away
        await self._send(None, "autopilot", {"seat": seat, "on": away})

    # ------------------------------------------------------------------ lobby

    async def _join(self, pid: str, name: str, army: str | None) -> None:
        r = self.room
        assert r is not None
        seat = r.seat_of(pid)
        if seat is not None:  # rejoin
            r.seats[seat].left = False
            await self._connected(pid, True)
            return
        if r.status is not RoomStatus.LOBBY:
            raise RoomError("started", "this match has already started")
        if len(r.seats) >= r.settings.max_players:
            raise RoomError("full", "the room is full")
        chosen = Army(army) if army in {a.value for a in Army} else self.rnd.choice(list(Army))
        r.seats.append(Seat(player_id=pid, name=name or "لاعب", army=chosen))
        if r.host is None:
            r.host = pid
        await self.redis.set(store.k_player_room(pid), self.code)
        await self._broadcast_room()

    async def _leave(self, pid: str, seat: int) -> None:
        r = self.room
        assert r is not None
        await self.redis.delete(store.k_player_room(pid))
        if r.status is RoomStatus.LOBBY:
            r.seats.pop(seat)
            r.votes.pop(pid, None)
            if r.host == pid:
                humans = r.humans()
                r.host = humans[0] if humans else None
            await self._send([pid], "left_room", {"code": self.code})
            if not r.humans():
                r.status = RoomStatus.ENDED
                self._schedule("cleanup", 0)
            await self._broadcast_room()
            return
        r.seats[seat].left = True  # a bot keeps the seat (no penalty for leaving)
        await self._send([pid], "left_room", {"code": self.code})
        if r.match and not r.match.players[seat].eliminated:
            await self._apply(SetConnected(seat=seat, connected=False))

    async def _lobby_message(self, pid: str, seat: int, type_: str, p: dict[str, Any]) -> None:
        r = self.room
        assert r is not None
        host = pid == r.host
        s = r.seats[seat]
        if type_ == "leave_room":
            await self._leave(pid, seat)
            return
        if type_ == "set_ready":
            s.ready = bool(p.get("ready", True))
        elif type_ == "choose_army":
            try:
                s.army = Army(p.get("army"))
            except ValueError as e:
                raise RoomError("bad_army", "unknown army") from e
        elif type_ == "vote_map":
            try:
                r.votes[pid] = MapKind(p.get("kind"))
            except ValueError as e:
                raise RoomError("bad_map", "unknown map kind") from e
        elif type_ in ("update_settings", "add_bot", "remove_bot", "start_match"):
            if not host:
                raise RoomError("not_host", "only the host can do this")
            if type_ == "update_settings":
                merged = r.settings.model_dump() | {
                    k: v for k, v in p.items() if k in store.RoomSettings.model_fields
                }
                try:
                    r.settings = store.RoomSettings.model_validate(merged)
                except ValueError as e:
                    raise RoomError("bad_settings", str(e)) from e
                if len(r.seats) > r.settings.max_players:
                    raise RoomError("bad_settings", "more players than the new maximum")
            elif type_ == "add_bot":
                if not r.settings.bots_allowed:
                    raise RoomError("no_bots", "bots are disabled in this room")
                if len(r.seats) >= r.settings.max_players:
                    raise RoomError("full", "the room is full")
                level = Difficulty(p.get("difficulty", "medium"))
                if level is Difficulty.SEAT_KEEPER:
                    raise RoomError("bad_bot", "unknown difficulty")
                r.seats.append(self._bot_seat(level))
            elif type_ == "remove_bot":
                i = int(p.get("seat", -1))
                if not (0 <= i < len(r.seats)) or r.seats[i].bot is None:
                    raise RoomError("bad_seat", "that seat is not a bot")
                r.seats.pop(i)
            else:
                await self._start_match()
                return
        else:
            raise RoomError("bad_type", f"{type_} is not allowed in the lobby")
        await self._broadcast_room()

    def _bot_seat(self, level: Difficulty) -> Seat:
        assert self.room is not None
        taken = {s.name for s in self.room.seats}
        name = next((n for n in BOT_NAMES if n not in taken), "بوت")
        return Seat(name=name, army=self.rnd.choice(list(Army)), ready=True, bot=level)

    async def _start_match(self) -> None:
        r = self.room
        assert r is not None
        n = len(r.seats)
        if n < 2:
            raise RoomError("too_few", "at least 2 players are needed")
        if r.settings.mode is Mode.TEAMS and n not in (4, 6, 8):
            raise RoomError("teams_size", "team matches need 4, 6 or 8 players")
        not_ready = [
            s.name for s in r.seats if s.player_id and s.player_id != r.host and not s.ready
        ]
        if not_ready and not r.quick:
            raise RoomError("not_ready", "waiting for: " + "، ".join(not_ready))
        # map vote: majority, ties at random (GAME_RULES §3)
        counts: dict[MapKind, int] = {}
        for kind in r.votes.values():
            counts[kind] = counts.get(kind, 0) + 1
        top = max(counts.values(), default=0)
        options = [k for k, c in counts.items() if c == top] or list(MapKind)
        r.map_kind = self.rnd.choice(sorted(options))
        team_size = n // 2 if r.settings.mode is Mode.TEAMS else 0
        setups = [
            PlayerSetup(
                seat=i,
                name=s.name,
                army=s.army,
                team=(i // team_size) if team_size else None,
                is_bot=s.bot is not None,
            )
            for i, s in enumerate(r.seats)
        ]
        r.match = core.create_match(
            self.code,
            map_for(r.map_kind, n),
            setups,
            seed=self.rnd.getrandbits(63),
            settings=MatchSettings(
                mode=r.settings.mode,
                battle_rounds=r.settings.battle_rounds,
                open_ended=r.settings.length == "open",
                choose_bases=True,
                battle_extras=True,
            ),
        )
        r.status = RoomStatus.PLAYING
        r.match_uid = uuid.uuid4().hex
        r.autostart_at_ms = None
        self._provider = None  # settings are final now
        self._cancel("autostart")
        tpl = load_template(template_id(r.map_kind, n))
        await self._send(
            None,
            "match_started",
            {
                "map_id": tpl["id"],
                "map_kind": r.map_kind.value,
                "mode": r.settings.mode.value,
                "rounds": r.match.battle_rounds,
                "base_towers": r.match.base_towers,
                "players": [
                    {
                        "seat": p.seat,
                        "name": p.name,
                        "army": p.army.value,
                        "team": p.team,
                        "bot": p.is_bot,
                    }
                    for p in r.match.players
                ],
                "bases": [],  # players place their castles (base_placed)
            },
        )
        await self._apply(StartMatch())

    # ------------------------------------------------------------------ connections

    async def _connected(self, pid: str, up: bool) -> None:
        r = self.room
        assert r is not None
        seat = r.seat_of(pid)
        if seat is None:
            return
        s = r.seats[seat]
        if s.connected == up:
            if up:
                await self._send([pid], "full_state", self.full_state(pid))
            return
        s.connected = up
        if r.status is RoomStatus.LOBBY:
            if up:
                self._cancel(f"drop:{pid}")
            else:
                self._schedule(f"drop:{pid}", self.settings.reconnect_grace_s * 1000, pid=pid)
            await self._broadcast_room()
        elif r.status is RoomStatus.PLAYING and r.match and not s.left:
            await self._apply(SetConnected(seat=seat, connected=up))
        if up:
            await self._send([pid], "full_state", self.full_state(pid))

    # ------------------------------------------------------------------ match

    def _to_action(self, seat: int, type_: str, p: dict[str, Any], item: dict[str, Any]):
        r = self.room
        assert r is not None and r.match is not None
        m = r.match
        if type_ == "answer":
            aq = m.active
            if aq is None or p.get("question_id") != aq.question.id:
                if p.get("question_id") in r.used_questions:
                    return None  # a late answer to a question that just closed: a normal race
                raise RoomError("no_question", "this question is not open")
            elapsed = int(item.get("elapsed_ms", 0) / self.settings.time_scale)
            if aq.question.kind is QuestionKind.MCQ:
                shown = p.get("choice")
                order = r.perms.get(seat, [0, 1, 2, 3])
                if not isinstance(shown, int) or not 0 <= shown < 4:
                    raise RoomError("bad_answer", "choice must be 0-3")
                return Answer(seat=seat, choice=order[shown], elapsed_ms=elapsed)
            try:
                value = float(p.get("value"))
            except (TypeError, ValueError) as e:
                raise RoomError("bad_answer", "a number is required") from e
            return Answer(seat=seat, value=value, elapsed_ms=elapsed)
        if type_ == "pick_territory":
            return PickTerritories(
                seat=seat, territories=[int(t) for t in p.get("territories", [])]
            )
        if type_ == "place_base":
            return PlaceBase(seat=seat, territory=int(p.get("territory", -1)))
        if type_ == "choose_target":
            category = p.get("category")
            if category in r.offered_categories:
                r.duel_categories[seat] = category
            return ChooseTarget(seat=seat, territory=int(p.get("territory", -1)))
        if type_ == "use_powerup":
            try:
                kind = PowerUp(p.get("powerup"))
            except ValueError as e:
                raise RoomError("bad_powerup", "unknown power-up") from e
            return UsePowerUp(seat=seat, powerup=kind, territory=p.get("territory"))
        if type_ == "use_ability":
            return UseAbility(seat=seat, territory=p.get("territory"))
        raise RoomError("bad_type", f"{type_} is not allowed during a match")

    async def _apply(self, action) -> None:
        r = self.room
        assert r is not None and r.match is not None
        r.match, events = core.apply(r.match, action)
        await self._after(events)

    async def _after(self, events: list[Event]) -> None:
        r = self.room
        assert r is not None and r.match is not None
        m = r.match
        types = {e.type for e in events}
        pause = 0
        if "match_started" in types:
            pause = max(pause, START_PAUSE_MS)
        if "question_result" in types:
            numeric = any(
                e.type == "question_result" and e.data.get("answer") is not None for e in events
            )
            pause = max(pause, NUMERIC_REVEAL_PAUSE_MS if numeric else REVEAL_PAUSE_MS)
        if "territory_claimed" in types:
            pause = max(pause, CLAIM_PAUSE_MS)
        if "base_placed" in types:
            pause = max(pause, BASE_PAUSE_MS)
        if "target_chosen" in types:
            pause = max(pause, MARCH_PAUSE_MS)
        if "battle_result" in types or "shield_blocked" in types:
            pause = max(pause, DUEL_PAUSE_MS)
        if any(e.type == "phase_changed" for e in events):
            for name in [n for n in r.timers if n.startswith(("phase:", "bot:", "provide"))]:
                self._cancel(name)
        for e in events:
            await self._emit(e, pause)
        if m.phase is Phase.RESULTS:
            r.status = RoomStatus.ENDED
            for name in list(r.timers):
                self._cancel(name)
            self._schedule("cleanup", ENDED_TTL_MS)
            await self._save_results()
            return
        if m.pending_question is not None and "provide" not in r.timers:
            self._schedule("provide", pause)
        elif m.phase is Phase.BASE_PLACEMENT and f"phase:{m.phase_id}" not in r.timers:
            self._schedule(
                f"phase:{m.phase_id}", pause + m.settings.timers.base_ms, phase_id=m.phase_id
            )
        elif m.phase is Phase.EXP_PICKS and f"phase:{m.phase_id}" not in r.timers:
            self._schedule(
                f"phase:{m.phase_id}", pause + m.settings.timers.pick_ms, phase_id=m.phase_id
            )
        elif m.phase is Phase.BATTLE_TARGET and f"phase:{m.phase_id}" not in r.timers:
            self._schedule(
                f"phase:{m.phase_id}", pause + m.settings.timers.target_ms, phase_id=m.phase_id
            )
        self._schedule_bots(pause)

    async def _save_results(self) -> None:
        """Hand the final standings to the results sink (leaderboard). Never breaks the room."""
        r = self.room
        if self.results_sink is None or r is None or r.match is None or r.match_uid is None:
            return
        try:
            await self.results_sink(r.match_uid, r)
        except Exception:
            log.exception("room %s: saving results failed", self.code)

    async def _emit(self, e: Event, pause: int) -> None:
        """Translate one engine event into client messages (per-player views where needed)."""
        r = self.room
        assert r is not None and r.match is not None
        pids = {i: s.player_id for i, s in enumerate(r.seats) if s.player_id and not s.left}
        to = None if e.to is None else [pids[i] for i in e.to if i in pids]
        if to == []:
            return
        data = dict(e.data)
        if e.type in ("phase_changed",):
            deadline = None
            if data.get("phase") == Phase.BASE_PLACEMENT.value:
                deadline = r.match.settings.timers.base_ms
            elif data.get("phase") == Phase.EXP_PICKS.value:
                deadline = r.match.settings.timers.pick_ms
            elif data.get("phase") == Phase.BATTLE_TARGET.value:
                deadline = r.match.settings.timers.target_ms
                # the attacker also picks the duel's category from three (§6.2.1)
                pool = list(r.settings.categories or CATEGORIES)
                r.offered_categories = self.rnd.sample(pool, min(3, len(pool)))
                r.duel_categories = {}
                data["categories"] = r.offered_categories
            data["opens_in_ms"] = int(pause * self.settings.time_scale)
            if deadline is not None:
                data["deadline_ms"] = int(deadline * self.settings.time_scale)
            await self._send(None, "phase_changed", data)
        elif e.type == "question":
            await self._send_question(data)
        elif e.type == "question_result":
            await self._send_result(data)
        elif e.type == "powerup_result" and data.get("powerup") == PowerUp.REMOVE_TWO.value:
            seat = e.to[0] if e.to else -1
            order = r.perms.get(seat, [0, 1, 2, 3])
            data["removed"] = sorted(order.index(c) for c in data["removed"])
            await self._send(to, "powerup_result", data)
        elif e.type in ("question_needed", "match_started"):
            return  # internal / already announced by the room with map details
        else:
            await self._send(to, e.type, data)

    async def _send_question(self, data: dict[str, Any]) -> None:
        r = self.room
        assert r is not None and r.match is not None and r.match.active is not None
        aq = r.match.active
        q = aq.question
        r.question_sent_ms = now_ms()
        r.perms = {}
        participants = set(aq.participants)
        scale = self.settings.time_scale
        for seat, s in enumerate(r.seats):
            order = list(range(4))
            if q.kind is QuestionKind.MCQ and seat in participants:
                self.rnd.shuffle(order)  # per-player option shuffle (anti-cheat)
            r.perms[seat] = order
            if not s.player_id or s.left:
                continue
            payload = {
                "id": q.id,
                "kind": q.kind.value,
                "text": q.text,
                "unit": q.unit,
                "category": q.category,
                "options": [q.options[i] for i in order] if q.kind is QuestionKind.MCQ else [],
                "participant": seat in participants,
                "participants": aq.participants,
                "time_ms": int(aq.limits_ms.get(seat, max(aq.limits_ms.values())) * scale),
                "phase_id": r.match.phase_id,
            }
            await self._send([s.player_id], "question", payload)
        longest = max(aq.limits_ms.values())
        grace = r.match.settings.timers.latency_grace_ms
        self._schedule(
            f"phase:{r.match.phase_id}",
            longest + grace + NETWORK_SLACK_MS,
            phase_id=r.match.phase_id,
        )

    async def _send_result(self, data: dict[str, Any]) -> None:
        r = self.room
        assert r is not None
        for seat, s in enumerate(r.seats):
            if not s.player_id or s.left:
                continue
            order = r.perms.get(seat, [0, 1, 2, 3])
            view = dict(data)
            if data.get("correct_index") is not None:
                view["correct_index"] = order.index(data["correct_index"])
                answers = {}
                for k, a in data.get("answers", {}).items():
                    a = dict(a)
                    if a.get("choice") is not None:
                        a["choice"] = order.index(a["choice"])
                    answers[k] = a
                view["answers"] = answers
            await self._send([s.player_id], "question_result", view)

    # ------------------------------------------------------------------ timers / bots

    async def _on_timer(self, name: str, data: dict[str, Any]) -> None:
        r = self.room
        assert r is not None
        if name == "cleanup":
            return
        if name == "autostart":
            if r.status is RoomStatus.LOBBY:
                await self._start_match()
            return
        if name.startswith("drop:"):
            pid = data["pid"]
            seat = r.seat_of(pid)
            if seat is not None and r.status is RoomStatus.LOBBY and not r.seats[seat].connected:
                await self._leave(pid, seat)
            return
        if r.match is None or r.status is not RoomStatus.PLAYING:
            return
        m = r.match
        if name == "provide":
            if m.pending_question is None:
                return
            category = (
                r.duel_categories.get(m.duel.attacker)
                if m.duel is not None and m.phase in (Phase.BATTLE_DUEL, Phase.BATTLE_TIEBREAK)
                else None
            )
            q = await self.provider().next(
                m.pending_question, r.humans(), r.used_questions, category
            )
            r.used_questions.append(q.id)
            await self._apply(ProvideQuestion(question=q))
        elif name.startswith("phase:"):
            # people who let the clock run out get the autopilot until they act again
            if m.phase_id == data["phase_id"]:
                for seat in self._owed():
                    s = r.seats[seat]
                    if s.bot is None and not s.left and s.connected and not s.away:
                        await self._set_away(seat, True)
            await self._apply(Timeout(phase_id=data["phase_id"]))
        elif name.startswith("bot:"):
            await self._bot_act(int(data["seat"]), int(data["phase_id"]))

    def _bot_level(self, seat: int) -> Difficulty | None:
        r = self.room
        assert r is not None
        s = r.seats[seat]
        if s.bot is not None:
            return s.bot
        if s.left or not s.connected or s.away:
            return Difficulty.SEAT_KEEPER
        return None

    def _schedule_bots(self, pause: int) -> None:
        r = self.room
        assert r is not None and r.match is not None
        m = r.match
        for seat in range(len(r.seats)):
            level = self._bot_level(seat)
            if level is None or m.players[seat].eliminated:
                continue
            name = f"bot:{seat}:{m.phase_id}"
            if name in r.timers:
                continue
            prof = bots.PROFILES[level]
            delay: int | None = None
            if (
                m.active is not None
                and seat in m.active.participants
                and seat not in m.active.answers
            ):
                limit = m.active.limits_ms[seat]
                delay = min(limit - 200, self.rnd.randint(prof.min_ms, prof.max_ms))
            elif m.phase is Phase.BASE_PLACEMENT and m.placer == seat:
                delay = pause + self.rnd.randint(2500, 5000)
            elif m.phase is Phase.EXP_PICKS and seat in m.pick_quota and seat not in m.picks:
                delay = pause + self.rnd.randint(2500, 6000)
            elif m.phase is Phase.BATTLE_TARGET and seat in m.planners and seat not in m.planned:
                delay = pause + self.rnd.randint(3000, 8000)
            if delay is not None:
                self._schedule(name, delay, seat=seat, phase_id=m.phase_id)

    async def _bot_act(self, seat: int, phase_id: int) -> None:
        r = self.room
        assert r is not None and r.match is not None
        m = r.match
        level = self._bot_level(seat)
        if level is None or m.phase_id != phase_id:
            return
        for extra in bots.extras(m, seat, level, self.rnd):
            with contextlib.suppress(core.RuleError):
                await self._apply(extra)
            m = r.match
            if m is None or m.phase_id != phase_id:
                return
        if m.active is not None and seat in m.active.participants and seat not in m.active.answers:
            a = bots.answer(m.active.question, seat, m.active.limits_ms[seat], level, self.rnd)
            await self._apply(a)
        elif m.phase is Phase.BASE_PLACEMENT and m.placer == seat:
            await self._apply(PlaceBase(seat=seat, territory=core.auto_base(m, seat)))
        elif m.phase is Phase.EXP_PICKS and seat in m.pick_quota and seat not in m.picks:
            await self._apply(bots.picks(m, seat, m.pick_quota[seat], self.rnd))
        elif m.phase is Phase.BATTLE_TARGET and seat in m.planners and seat not in m.planned:
            choice = bots.target(m, seat, level, self.rnd)
            if choice is not None:
                if r.offered_categories:
                    r.duel_categories[seat] = self.rnd.choice(r.offered_categories)
                await self._apply(choice)

    # ------------------------------------------------------------------ full state

    def full_state(self, pid: str) -> dict[str, Any]:
        r = self.room
        assert r is not None
        out: dict[str, Any] = {"room": self._room_state(), "match": None}
        m = r.match
        if m is None:
            return out
        seat = r.seat_of(pid)
        my_team = m.players[seat].team if seat is not None else None
        scale = self.settings.time_scale
        territories = [
            {
                "id": t.id,
                "owner": t.owner,
                "value": t.value,
                "is_base": t.is_base,
                "towers": t.towers,
                "shielded": t.shielded
                and t.owner is not None
                and m.players[t.owner].team == my_team,
            }
            for t in m.territories.values()
        ]
        players = [
            {
                "seat": p.seat,
                "name": p.name,
                "army": p.army.value,
                "team": p.team,
                "score": core.score(m, p.seat),
                "eliminated": p.eliminated,
                "connected": p.connected,
                "ability_used": p.ability_used,
                "powerups": [x.value for x in p.powerups] if p.seat == seat else len(p.powerups),
            }
            for p in m.players
        ]
        question = None
        if m.active is not None:
            aq = m.active
            q = aq.question
            order = r.perms.get(seat if seat is not None else -1, [0, 1, 2, 3])
            elapsed = now_ms() - (r.question_sent_ms or now_ms())
            question = {
                "id": q.id,
                "kind": q.kind.value,
                "text": q.text,
                "unit": q.unit,
                "category": q.category,
                "options": [q.options[i] for i in order] if q.kind is QuestionKind.MCQ else [],
                "participant": seat in aq.participants,
                "participants": aq.participants,
                "answered": seat in aq.answers,
                "time_ms": int(
                    aq.limits_ms.get(seat if seat is not None else -1, max(aq.limits_ms.values()))
                    * scale
                ),
                "elapsed_ms": elapsed,
            }
        phase_timer = r.timers.get(f"phase:{m.phase_id}")
        out["match"] = {
            "map_id": m.map_id,
            "map_kind": r.map_kind.value if r.map_kind else None,
            "phase": m.phase.value,
            "phase_id": m.phase_id,
            "deadline_in_ms": max(0, phase_timer.at_ms - now_ms()) if phase_timer else None,
            "expansion_round": m.expansion_round,
            "battle_round": m.battle_round,
            "rounds": m.battle_rounds,
            "base_towers": m.base_towers,
            "attacker": m.attacker,
            "placer": m.placer,
            "treasure": m.treasure,
            "win_share": round(core.domination_share(m), 2) if m.settings.open_ended else None,
            "round_order": m.round_order,
            "duel": m.duel.model_dump() if m.duel else None,
            "pick_quota": {str(k): v for k, v in m.pick_quota.items()},
            "your_seat": seat,
            "territories": territories,
            "players": players,
            "question": question,
            "winner_team": m.winner_team,
            "standings": core.standings(m) if m.phase is Phase.RESULTS else None,
        }
        return out
