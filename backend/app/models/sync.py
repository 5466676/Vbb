"""Offline sync log, counters and online match results."""

from __future__ import annotations

from datetime import datetime

from sqlalchemy import (
    BigInteger,
    Boolean,
    DateTime,
    Float,
    ForeignKey,
    Index,
    Integer,
    SmallInteger,
    String,
    UniqueConstraint,
    func,
)
from sqlalchemy.orm import Mapped, mapped_column

from app.db import Base


class Counter(Base):
    """Named monotonic counters (e.g. ``questions`` = the question bank version)."""

    __tablename__ = "counters"

    name: Mapped[str] = mapped_column(String(32), primary_key=True)
    value: Mapped[int] = mapped_column(BigInteger, default=0)


class Action(Base):
    """One player action sent by a device (``POST /sync``). The id is the device's UUID,
    so a repeated sync never counts twice. ``correct``/``points`` are computed by the server."""

    __tablename__ = "actions"
    __table_args__ = (Index("ix_actions_player_ts", "player_id", "client_ts"),)

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    player_id: Mapped[str] = mapped_column(
        String(32), ForeignKey("players.id", ondelete="CASCADE"), index=True
    )
    type: Mapped[str] = mapped_column(String(16))
    session_id: Mapped[str | None] = mapped_column(String(36), index=True, nullable=True)
    question_id: Mapped[int | None] = mapped_column(Integer, nullable=True)
    choice: Mapped[int | None] = mapped_column(SmallInteger, nullable=True)
    value: Mapped[float | None] = mapped_column(Float, nullable=True)
    elapsed_ms: Mapped[int | None] = mapped_column(Integer, nullable=True)
    client_ts: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    received_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    status: Mapped[str] = mapped_column(String(10))  # ok | rejected
    reason: Mapped[str] = mapped_column(String(40), default="")
    correct: Mapped[bool | None] = mapped_column(Boolean, nullable=True)
    points: Mapped[int] = mapped_column(Integer, default=0)


class MatchResult(Base):
    """One human's result in a finished online match (the leaderboard source)."""

    __tablename__ = "match_results"
    __table_args__ = (UniqueConstraint("match_uid", "player_id", name="uq_match_player"),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    match_uid: Mapped[str] = mapped_column(String(32), index=True)
    player_id: Mapped[str] = mapped_column(
        String(32), ForeignKey("players.id", ondelete="CASCADE"), index=True
    )
    mode: Mapped[str] = mapped_column(String(8))
    humans: Mapped[int] = mapped_column(SmallInteger)
    players: Mapped[int] = mapped_column(SmallInteger)
    rank: Mapped[int] = mapped_column(SmallInteger)
    score: Mapped[int] = mapped_column(Integer)
    correct: Mapped[int] = mapped_column(Integer)
    won: Mapped[bool] = mapped_column(Boolean)
    ended_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), index=True
    )
