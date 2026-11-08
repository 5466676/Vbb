"""Server side of offline sync.

A device stores every solo action locally with its own UUID and sends them with ``POST /sync``
when the server is reachable. The server:
- stores each action once (the UUID is the primary key, so a repeated sync counts nothing twice);
- recomputes correctness and points from the stored question (client numbers are ignored);
- rejects impossible timestamps, answers that are too fast, too frequent, repeated in a session
  or over the daily cap. Rejected actions are recorded too, so they are never re-processed.
"""

from __future__ import annotations

import bisect
import uuid
from datetime import UTC, date, datetime, timedelta
from typing import Any, Literal

from pydantic import BaseModel, Field, ValidationError, field_validator
from sqlalchemy import Integer, cast, distinct, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db import upsert
from app.models import Action, MatchResult, Question
from app.models.question import SOLO_PACK
from app.ranks import level_of, rank_of, total_xp

MAX_ACTIONS_PER_SYNC = 500
MAX_FUTURE = timedelta(minutes=5)  # device clocks drift a little
MAX_AGE = timedelta(days=60)
MIN_ANSWER_MS = 400  # nobody reads and answers a question faster
MAX_ANSWER_MS = 120_000
MIN_GAP_MS = 400  # between two answers of the same player
DAILY_ANSWER_CAP = 2_000
POINTS_CORRECT = 10
POINTS_CLOSE = 5  # numeric answer within 10%
QUESTIONS_PAGE = 500


def _uuid(v: str) -> str:
    return str(uuid.UUID(v))


class ActionIn(BaseModel):
    id: str = Field(description="UUID generated on the device")
    type: Literal["answer", "session_end"]
    ts: datetime = Field(description="when it happened, device clock, ISO 8601 with offset")
    session_id: str
    question_id: str | None = None  # "q123"
    choice: int | None = None  # MCQ: 0-3 in the stored option order
    value: float | None = None  # numeric answer
    elapsed_ms: int | None = None

    @field_validator("id", "session_id")
    @classmethod
    def uuid_text(cls, v: str) -> str:
        return _uuid(v)

    @field_validator("ts")
    @classmethod
    def aware(cls, v: datetime) -> datetime:
        return v.replace(tzinfo=UTC) if v.tzinfo is None else v.astimezone(UTC)


class SyncIn(BaseModel):
    # validated one by one (``parse_actions``): one bad action must not block the device's queue
    actions: list[dict[str, Any]] = Field(default_factory=list, max_length=MAX_ACTIONS_PER_SYNC)
    questions_since: int | None = Field(default=None, ge=0)


class ActionOut(BaseModel):
    id: str
    status: Literal["ok", "duplicate", "rejected"]
    reason: str = ""
    correct: bool | None = None
    points: int = 0


def parse_actions(raw: list[dict[str, Any]]) -> tuple[list[ActionIn], list[ActionOut]]:
    """Valid actions, and rejections for the ones that do not parse (not stored)."""
    good, bad = [], []
    for item in raw:
        try:
            good.append(ActionIn.model_validate(item))
        except ValidationError:
            bad.append(
                ActionOut(id=str(item.get("id", ""))[:64], status="rejected", reason="invalid")
            )
    return good, bad


def grade(q: Question, a: ActionIn) -> tuple[bool, int] | str:
    """(correct, points) or a rejection reason."""
    if q.type == "mcq":
        if a.choice is None or not 0 <= a.choice <= 3:
            return "bad_choice"
        ok = a.choice == q.correct_index
        return ok, POINTS_CORRECT if ok else 0
    if a.value is None:
        return "bad_value"
    target = q.numeric_answer or 0.0
    if a.value == target:
        return True, POINTS_CORRECT
    close = abs(a.value - target) <= abs(target) * 0.1
    return False, POINTS_CLOSE if close else 0


class _Ctx:
    """What we need to know about the player's earlier actions to validate a batch."""

    def __init__(self) -> None:
        self.times: list[float] = []  # accepted answer timestamps (epoch ms), sorted
        self.seen: set[tuple[str, int]] = set()  # (session, question) already answered
        self.per_day: dict[date, int] = {}


async def _context(s: AsyncSession, pid: str, actions: list[ActionIn]) -> _Ctx:
    ctx = _Ctx()
    answers = [a for a in actions if a.type == "answer"]
    if not answers:
        return ctx
    lo = min(a.ts for a in answers) - timedelta(days=1)
    hi = max(a.ts for a in answers) + timedelta(days=1)
    rows = await s.execute(
        select(Action.client_ts, Action.session_id, Action.question_id).where(
            Action.player_id == pid,
            Action.type == "answer",
            Action.status == "ok",
            Action.client_ts >= lo,
            Action.client_ts <= hi,
        )
    )
    for ts, sid, qid in rows:
        ts = ts.replace(tzinfo=UTC) if ts.tzinfo is None else ts
        ctx.times.append(ts.timestamp() * 1000)
        ctx.per_day[ts.date()] = ctx.per_day.get(ts.date(), 0) + 1
        if sid is not None and qid is not None:
            ctx.seen.add((sid, qid))
    sessions = {a.session_id for a in answers}
    rows = await s.execute(
        select(Action.session_id, Action.question_id).where(
            Action.player_id == pid,
            Action.status == "ok",
            Action.session_id.in_(sessions),
        )
    )
    ctx.seen.update((sid, qid) for sid, qid in rows if qid is not None)
    ctx.times.sort()
    return ctx


def _qid(raw: str | None) -> int | None:
    if raw and raw.startswith("q") and raw[1:].isdigit():
        return int(raw[1:])
    return None


def _check(a: ActionIn, now: datetime, ctx: _Ctx, q: Question | None) -> tuple[bool, int] | str:
    if a.ts > now + MAX_FUTURE:
        return "future_ts"
    if a.ts < now - MAX_AGE:
        return "too_old"
    if a.type == "session_end":
        return False, 0
    if q is None or q.pack != SOLO_PACK:
        return "unknown_question"
    if a.elapsed_ms is None or a.elapsed_ms < MIN_ANSWER_MS:
        return "too_fast"
    if a.elapsed_ms > MAX_ANSWER_MS:
        return "bad_elapsed"
    if (a.session_id, q.id) in ctx.seen:
        return "repeat_in_session"
    t = a.ts.timestamp() * 1000
    i = bisect.bisect_left(ctx.times, t)
    near = ctx.times[max(0, i - 1) : i + 1]
    if any(abs(t - x) < MIN_GAP_MS for x in near):
        return "too_frequent"
    if ctx.per_day.get(a.ts.date(), 0) >= DAILY_ANSWER_CAP:
        return "daily_cap"
    return grade(q, a)


async def apply_actions(
    s: AsyncSession, pid: str, actions: list[ActionIn], now: datetime | None = None
) -> list[ActionOut]:
    now = now or datetime.now(UTC)
    out: dict[str, ActionOut] = {}
    # duplicates (same id already stored, or twice in this request)
    ids = list(dict.fromkeys(a.id for a in actions))
    stored = dict(
        (await s.execute(select(Action.id, Action.player_id).where(Action.id.in_(ids)))).all()
    )
    fresh: list[ActionIn] = []
    for a in actions:
        if a.id in out:
            continue
        if a.id in stored:
            status = "duplicate" if stored[a.id] == pid else "rejected"
            out[a.id] = ActionOut(
                id=a.id, status=status, reason="" if status == "duplicate" else "id_conflict"
            )
            continue
        out[a.id] = ActionOut(id=a.id, status="ok")  # placeholder, keeps the request order
        fresh.append(a)
    qids = {q for a in fresh if (q := _qid(a.question_id)) is not None}
    questions = {
        q.id: q for q in (await s.execute(select(Question).where(Question.id.in_(qids)))).scalars()
    }
    ctx = await _context(s, pid, fresh)
    for a in sorted(fresh, key=lambda a: a.ts):
        qid = _qid(a.question_id)
        res = _check(a, now, ctx, questions.get(qid) if qid is not None else None)
        if isinstance(res, str):
            row = ActionOut(id=a.id, status="rejected", reason=res)
        else:
            row = ActionOut(
                id=a.id, status="ok", correct=res[0] if a.type == "answer" else None, points=res[1]
            )
        stmt = (
            upsert(s, Action)
            .values(
                id=a.id,
                player_id=pid,
                type=a.type,
                session_id=a.session_id,
                question_id=qid,
                choice=a.choice,
                value=a.value,
                elapsed_ms=a.elapsed_ms,
                client_ts=a.ts,
                status="ok" if row.status == "ok" else "rejected",
                reason=row.reason,
                correct=row.correct,
                points=row.points,
            )
            .on_conflict_do_nothing(index_elements=["id"])
        )
        if (await s.execute(stmt)).rowcount == 0:  # a parallel sync stored it first
            row = ActionOut(id=a.id, status="duplicate")
        elif row.status == "ok" and a.type == "answer":
            t = a.ts.timestamp() * 1000
            bisect.insort(ctx.times, t)
            ctx.seen.add((a.session_id, qid))
            ctx.per_day[a.ts.date()] = ctx.per_day.get(a.ts.date(), 0) + 1
        out[a.id] = row
    await s.commit()
    return list(out.values())


async def player_stats(s: AsyncSession, pid: str) -> dict:
    solo = (
        await s.execute(
            select(
                func.count(),
                func.coalesce(func.sum(cast(Action.correct, Integer)), 0),
                func.coalesce(func.sum(Action.points), 0),
                func.count(distinct(Action.session_id)),
            ).where(Action.player_id == pid, Action.type == "answer", Action.status == "ok")
        )
    ).one()
    online = (
        await s.execute(
            select(
                func.count(),
                func.coalesce(func.sum(cast(MatchResult.won, Integer)), 0),
                func.coalesce(func.sum(MatchResult.score), 0),
                func.coalesce(func.sum(MatchResult.correct), 0),
            ).where(MatchResult.player_id == pid)
        )
    ).one()
    answered, correct, points, sessions = (int(x) for x in solo)
    return {
        "solo": {
            "answered": answered,
            "correct": correct,
            "points": points,
            "sessions": sessions,
            "accuracy": round(correct / answered, 3) if answered else 0.0,
        },
        "online": {"matches": int(online[0]), "wins": int(online[1]), "score": int(online[2])},
        "xp": (xp := total_xp(int(online[0]), int(online[3]), int(online[1]))),
        "rank": rank_of(xp),
        "level": level_of(xp),
    }


def question_out(q: Question) -> dict:
    if q.deleted:
        return {"id": f"q{q.id}", "version": q.version, "deleted": True}
    return {
        "id": f"q{q.id}",
        "version": q.version,
        "deleted": False,
        "kind": q.type,
        "category": q.category,
        "difficulty": q.difficulty,
        "text": q.text_ar,
        "options": q.options_ar,
        "correct_index": q.correct_index,
        "answer": q.numeric_answer,
        "unit": q.unit_ar,
    }


async def questions_since(s: AsyncSession, since: int, limit: int = QUESTIONS_PAGE) -> dict:
    """Solo-pack questions changed after ``since`` (version order). Includes tombstones."""
    rows = (
        (
            await s.execute(
                select(Question)
                .where(Question.pack == SOLO_PACK, Question.version > since)
                .order_by(Question.version)
                .limit(limit + 1)
            )
        )
        .scalars()
        .all()
    )
    more = len(rows) > limit
    rows = rows[:limit]
    version = rows[-1].version if rows else since
    if not more:  # nothing left: jump to the bank's version (changes in other packs)
        latest = (
            await s.execute(select(func.max(Question.version)).where(Question.pack == SOLO_PACK))
        ).scalar_one_or_none()
        version = max(version, latest or 0)
    return {"version": version, "more": more, "items": [question_out(q) for q in rows]}
