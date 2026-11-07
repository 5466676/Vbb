"""Question bank: validation, import (JSON/CSV), seeding and selection for matches.

Selection (brief §6):
- never a question already used in this match;
- avoid questions any player in the room has seen in the last ``seen_window_days``;
- balance difficulty: prefer the difficulty used least so far in the match;
- if everything was seen recently, take the question these players saw longest ago.
"""

from __future__ import annotations

import csv
import io
import json
import logging
from collections.abc import Iterable
from datetime import UTC, datetime, timedelta
from pathlib import Path
from typing import Any

from pydantic import BaseModel, Field, ValidationError, field_validator, model_validator
from sqlalchemy import case, func, select, text
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from app.db import upsert
from app.engine.models import Question as EngineQuestion
from app.engine.models import QuestionKind
from app.models import Counter, Player, Question, SeenQuestion
from app.models.question import CATEGORIES, GENERAL_PACK, SOLO_PACK

log = logging.getLogger(__name__)
SEED_DIR = Path(__file__).parent / "seed"
SEED_FILE = SEED_DIR / "seed_ar.json"
SEED_SOURCE = "harb-seed"


class QuestionIn(BaseModel):
    """One question as imported (JSON object or CSV row)."""

    type: QuestionKind
    category: str
    difficulty: int = Field(default=2, ge=1, le=3)
    text_ar: str = Field(min_length=3, max_length=500)
    options_ar: list[str] | None = None
    correct_index: int | None = None
    numeric_answer: float | None = None
    unit_ar: str = Field(default="", max_length=40)
    source: str = Field(default="", max_length=200)

    @field_validator("text_ar", "category", "unit_ar", "source")
    @classmethod
    def strip(cls, v: str) -> str:
        return v.strip()

    @field_validator("category")
    @classmethod
    def known_category(cls, v: str) -> str:
        if v not in CATEGORIES:
            raise ValueError(f"unknown category {v!r}; use one of {', '.join(CATEGORIES)}")
        return v

    @model_validator(mode="after")
    def shape(self) -> QuestionIn:
        if self.type is QuestionKind.MCQ:
            opts = [o.strip() for o in (self.options_ar or [])]
            if len(opts) != 4 or any(not o for o in opts) or len(set(opts)) != 4:
                raise ValueError("an MCQ needs exactly 4 different, non-empty options")
            if self.correct_index not in (0, 1, 2, 3):
                raise ValueError("correct_index must be 0-3")
            self.options_ar = opts
            self.numeric_answer = None
        else:
            if self.numeric_answer is None:
                raise ValueError("a numeric question needs numeric_answer")
            self.options_ar = None
            self.correct_index = None
        return self


class ImportResult(BaseModel):
    inserted: int = 0
    duplicates: int = 0
    errors: list[dict[str, Any]] = Field(default_factory=list)


CSV_COLUMNS = [
    "type",
    "category",
    "difficulty",
    "text_ar",
    "option_1",
    "option_2",
    "option_3",
    "option_4",
    "correct_index",
    "numeric_answer",
    "unit_ar",
    "source",
]


def parse_csv(text_: str) -> list[dict[str, Any]]:
    """CSV with the header ``CSV_COLUMNS`` (options in four columns, correct_index 0-3)."""
    rows = []
    for raw in csv.DictReader(io.StringIO(text_.lstrip("﻿"))):
        row: dict[str, Any] = {k: (v or "").strip() for k, v in raw.items() if k}
        opts = [row.pop(f"option_{i}", "") for i in range(1, 5)]
        if row.get("type") == "mcq":
            row["options_ar"] = opts
        for key in ("difficulty", "correct_index"):
            row[key] = int(row[key]) if row.get(key) else None
        row["numeric_answer"] = float(row["numeric_answer"]) if row.get("numeric_answer") else None
        rows.append({k: v for k, v in row.items() if v is not None and v != ""})
    return rows


async def next_version(session: AsyncSession) -> int:
    """Next value of the question-bank version (one per inserted/edited/deleted question)."""
    stmt = (
        upsert(session, Counter)
        .values(name="questions", value=1)
        .on_conflict_do_update(index_elements=["name"], set_={"value": Counter.value + 1})
        .returning(Counter.value)
    )
    return (await session.execute(stmt)).scalar_one()


async def import_questions(
    session: AsyncSession,
    items: Iterable[dict[str, Any]],
    *,
    pack: str = GENERAL_PACK,
    source: str = "",
    license_: str = "",
    reviewed: bool = False,
) -> ImportResult:
    """Validate and insert. Rows whose text already exists are counted as duplicates."""
    result = ImportResult()
    valid: list[dict[str, Any]] = []
    for i, item in enumerate(items):
        try:
            q = QuestionIn.model_validate(item)
        except ValidationError as e:
            result.errors.append({"row": i, "error": "; ".join(err["msg"] for err in e.errors())})
            continue
        valid.append(
            {
                **q.model_dump(),
                "type": q.type.value,
                "source": q.source or source,
                "license": license_,
                "pack": pack,
                "reviewed": reviewed,
            }
        )
    for row in valid:
        exists = await session.execute(
            select(Question.id).where(Question.text_ar == row["text_ar"])
        )
        if exists.first() is not None:
            result.duplicates += 1
            continue
        session.add(Question(**row, version=await next_version(session)))
        await session.flush()
        result.inserted += 1
    await session.commit()
    return result


# built-in question files, imported in this order on every start (duplicates are skipped)
SEED_FILES = [SEED_FILE, SEED_DIR / "owner_bank.json"]


def seed_packs() -> dict[str, list[dict[str, Any]]]:
    """The seed split in two: every third question per category goes to the offline solo pack."""
    out: dict[str, list[dict[str, Any]]] = {GENERAL_PACK: [], SOLO_PACK: []}
    per_cat: dict[str, int] = {}
    for path in SEED_FILES:
        for item in json.loads(path.read_text(encoding="utf-8")):
            n = per_cat[item["category"]] = per_cat.get(item["category"], 0) + 1
            out[SOLO_PACK if n % 3 == 0 else GENERAL_PACK].append(item)
    return out


async def load_seed(session: AsyncSession) -> ImportResult:
    total = ImportResult()
    for pack, items in seed_packs().items():
        res = await import_questions(session, items, pack=pack, source=SEED_SOURCE)
        total.inserted += res.inserted
        total.duplicates += res.duplicates
        total.errors += res.errors
    return total


# ------------------------------------------------------------------------------------------
# Selection
# ------------------------------------------------------------------------------------------


class NoQuestions(Exception):
    pass


def to_engine(q: Question) -> EngineQuestion:
    return EngineQuestion(
        id=f"q{q.id}",
        kind=QuestionKind(q.type),
        text=q.text_ar,
        options=list(q.options_ar or []),
        correct_index=q.correct_index,
        answer=q.numeric_answer,
        unit=q.unit_ar,
    )


def _db_ids(ids: Iterable[str]) -> list[int]:
    return [int(i[1:]) for i in ids if i.startswith("q") and i[1:].isdigit()]


class DbProvider:
    """Picks questions for one room. Stateless apart from its filters."""

    def __init__(
        self,
        sessionmaker: async_sessionmaker[AsyncSession],
        categories: list[str] | None = None,
        packs: list[str] | None = None,
        only_reviewed: bool = False,
        seen_window_days: int = 30,
    ) -> None:
        self.sessionmaker = sessionmaker
        self.categories = [c for c in (categories or []) if c in CATEGORIES]
        # the solo pack is on players' devices with its answers: never use it online
        self.packs = [p for p in (packs or []) if p != SOLO_PACK] or [GENERAL_PACK]
        self.only_reviewed = only_reviewed
        self.window = timedelta(days=seen_window_days)

    def _filters(self, kind: QuestionKind, used: list[int]) -> list:
        f = [
            Question.type == kind.value,
            Question.pack.in_(self.packs),
            Question.deleted.is_(False),
        ]
        if self.categories:
            f.append(Question.category.in_(self.categories))
        if self.only_reviewed:
            f.append(Question.reviewed.is_(True))
        if used:
            f.append(Question.id.not_in(used))
        return f

    async def next(
        self, kind: QuestionKind, players: list[str], used_ids: list[str]
    ) -> EngineQuestion:
        used = _db_ids(used_ids)
        async with self.sessionmaker() as s:
            # least-used difficulty so far in this match
            counts = {1: 0, 2: 0, 3: 0}
            if used:
                rows = await s.execute(
                    select(Question.difficulty, func.count())
                    .where(Question.id.in_(used), Question.type == kind.value)
                    .group_by(Question.difficulty)
                )
                for d, n in rows:
                    counts[d] = n
            target = min(counts, key=lambda d: (counts[d], d))
            prefer = case((Question.difficulty == target, 0), else_=1)
            since = datetime.now(UTC) - self.window
            seen_recently = select(SeenQuestion.question_id).where(
                SeenQuestion.player_id.in_(players), SeenQuestion.seen_at >= since
            )
            q = (
                await s.execute(
                    select(Question)
                    .where(*self._filters(kind, used), Question.id.not_in(seen_recently))
                    .order_by(prefer, func.random())
                    .limit(1)
                )
            ).scalar_one_or_none()
            if q is None:  # everything was seen recently: the one seen longest ago
                last_seen = (
                    select(func.max(SeenQuestion.seen_at))
                    .where(
                        SeenQuestion.question_id == Question.id, SeenQuestion.player_id.in_(players)
                    )
                    .scalar_subquery()
                )
                q = (
                    await s.execute(
                        select(Question)
                        .where(*self._filters(kind, used))
                        .order_by(last_seen.asc().nullsfirst(), func.random())
                        .limit(1)
                    )
                ).scalar_one_or_none()
            if q is None:
                raise NoQuestions(f"no {kind.value} questions match the room filters")
            if players:
                known = select(Player.id, text(str(q.id)), func.now()).where(Player.id.in_(players))
                stmt = upsert(s, SeenQuestion).from_select(
                    ["player_id", "question_id", "seen_at"], known
                )
                stmt = stmt.on_conflict_do_update(
                    index_elements=["player_id", "question_id"], set_={"seen_at": func.now()}
                )
                await s.execute(stmt)
                await s.commit()
            return to_engine(q)


class FallbackProvider:
    """Use the database bank; if it has nothing for the room, fall back to the built-in sample."""

    def __init__(self, primary: DbProvider, fallback: Any) -> None:
        self.primary = primary
        self.fallback = fallback

    async def next(
        self, kind: QuestionKind, players: list[str], used_ids: list[str]
    ) -> EngineQuestion:
        try:
            return await self.primary.next(kind, players, used_ids)
        except NoQuestions:
            log.warning("question bank empty for these filters; using the built-in sample")
            return await self.fallback.next(kind, players, used_ids)
