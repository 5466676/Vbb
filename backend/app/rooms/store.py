"""Room records and Redis keys.

One room = one JSON document at ``room:{code}``. Only the worker holding the room's lease
(``room:{code}:owner``) writes it; everyone else talks to the room through its inbox.
"""

from __future__ import annotations

import secrets
from enum import StrEnum
from typing import Literal

from pydantic import BaseModel, Field, field_validator
from redis.asyncio import Redis

from app.bots.simple import Difficulty
from app.engine.armies import Army
from app.engine.models import MatchState, Mode
from app.maps import MapKind
from app.models.question import CATEGORIES, GENERAL_PACK, SOLO_PACK

CODE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"  # no 0/O/1/I/L
CODE_LEN = 6


def k_room(code: str) -> str:
    return f"room:{code}"


def k_inbox(code: str) -> str:
    return f"room:{code}:inbox"


def k_owner(code: str) -> str:
    return f"room:{code}:owner"


def ch_room_in(code: str) -> str:
    return f"room:{code}:in"


def ch_room_out(code: str) -> str:
    return f"room:{code}:out"


def k_player_room(pid: str) -> str:
    return f"player:{pid}:room"


def ch_player(pid: str) -> str:
    return f"player:{pid}"


def k_queue(mode: Mode, size: int) -> str:
    return f"qm:{mode.value}:{size}"


class RoomStatus(StrEnum):
    LOBBY = "lobby"
    PLAYING = "playing"
    ENDED = "ended"


class RoomSettings(BaseModel):
    mode: Mode = Mode.FFA
    max_players: int = Field(default=8, ge=2, le=8)
    battle_rounds: int | None = Field(default=None, ge=1, le=30)
    bots_allowed: bool = True
    categories: list[str] = Field(default_factory=list)  # empty = all categories
    length: Literal["open", "rounds"] = "open"  # open: ends by domination; rounds: fixed rounds
    packs: list[str] = Field(default_factory=lambda: [GENERAL_PACK], min_length=1, max_length=5)

    @field_validator("categories")
    @classmethod
    def known_categories(cls, v: list[str]) -> list[str]:
        unknown = [c for c in v if c not in CATEGORIES]
        if unknown:
            raise ValueError(f"unknown categories: {', '.join(unknown)}")
        return list(dict.fromkeys(v))

    @field_validator("packs")
    @classmethod
    def pack_names(cls, v: list[str]) -> list[str]:
        if any(not (1 <= len(x) <= 40) for x in v):
            raise ValueError("pack names are 1-40 characters")
        if SOLO_PACK in v:
            raise ValueError("the solo pack is offline only (its answers are on the devices)")
        return list(dict.fromkeys(v))


class Seat(BaseModel):
    player_id: str | None = None  # None for bots
    name: str
    army: Army = Army.ISLAMIC
    ready: bool = False
    bot: Difficulty | None = None
    connected: bool = True
    left: bool = False  # left during a match: a bot keeps playing
    away: bool = False  # missed a move: the autopilot plays (no power-ups) until they act again


class Timer(BaseModel):
    at_ms: int
    data: dict = Field(default_factory=dict)


class RoomData(BaseModel):
    code: str
    host: str | None
    status: RoomStatus = RoomStatus.LOBBY
    settings: RoomSettings = Field(default_factory=RoomSettings)
    seats: list[Seat] = Field(default_factory=list)
    votes: dict[str, MapKind] = Field(default_factory=dict)
    quick: bool = False  # created by quick match: starts by itself
    autostart_at_ms: int | None = None
    map_kind: MapKind | None = None
    match: MatchState | None = None
    match_uid: str | None = None  # unique per match (results are saved under it)
    perms: dict[int, list[int]] = Field(
        default_factory=dict
    )  # seat -> display order of MCQ options
    question_sent_ms: int | None = None
    used_questions: list[str] = Field(default_factory=list)
    offered_categories: list[str] = Field(default_factory=list)  # the attacker's choices now
    duel_categories: dict[int, str] = Field(default_factory=dict)  # attacker -> picked category
    timers: dict[str, Timer] = Field(default_factory=dict)

    def seat_of(self, pid: str) -> int | None:
        for i, s in enumerate(self.seats):
            if s.player_id == pid:
                return i
        return None

    def humans(self) -> list[str]:
        return [s.player_id for s in self.seats if s.player_id and not s.left]


async def new_code(redis: Redis) -> str:
    for _ in range(50):
        code = "".join(secrets.choice(CODE_ALPHABET) for _ in range(CODE_LEN))
        if not await redis.exists(k_room(code)):
            return code
    raise RuntimeError("could not find a free room code")


async def load_room(redis: Redis, code: str) -> RoomData | None:
    raw = await redis.get(k_room(code))
    return RoomData.model_validate_json(raw) if raw else None


async def save_room(redis: Redis, room: RoomData, ttl_s: int = 6 * 3600) -> None:
    await redis.set(k_room(room.code), room.model_dump_json(), ex=ttl_s)
