"""Question bank (brief §6) and the anti-repeat log."""

from __future__ import annotations

from datetime import datetime
from enum import StrEnum

from sqlalchemy import (
    Boolean,
    CheckConstraint,
    DateTime,
    Float,
    ForeignKey,
    Integer,
    SmallInteger,
    String,
    Text,
    func,
)
from sqlalchemy.dialects.postgresql import ARRAY
from sqlalchemy.orm import Mapped, mapped_column

from app.db import Base


class QuestionType(StrEnum):
    MCQ = "mcq"
    NUMERIC = "numeric"


CATEGORIES = ["دين", "تاريخ", "جغرافيا", "علوم", "رياضيات", "لغة عربية", "رياضة", "ثقافة عامة"]
GENERAL_PACK = "general"


class Question(Base):
    __tablename__ = "questions"
    __table_args__ = (
        CheckConstraint("difficulty BETWEEN 1 AND 3", name="difficulty_range"),
        CheckConstraint(
            "(type = 'mcq' AND correct_index BETWEEN 0 AND 3 AND cardinality(options_ar) = 4)"
            " OR (type = 'numeric' AND numeric_answer IS NOT NULL)",
            name="shape_by_type",
        ),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    type: Mapped[str] = mapped_column(String(8), index=True)
    category: Mapped[str] = mapped_column(String(40), index=True)
    difficulty: Mapped[int] = mapped_column(SmallInteger, default=2)
    text_ar: Mapped[str] = mapped_column(Text, unique=True)
    options_ar: Mapped[list[str] | None] = mapped_column(ARRAY(Text), nullable=True)
    correct_index: Mapped[int | None] = mapped_column(SmallInteger, nullable=True)
    numeric_answer: Mapped[float | None] = mapped_column(Float, nullable=True)
    unit_ar: Mapped[str] = mapped_column(String(40), default="")
    source: Mapped[str] = mapped_column(String(200), default="")
    license: Mapped[str] = mapped_column(String(40), default="")
    # curriculum packs (e.g. "sy-g9-science") live next to the general bank
    pack: Mapped[str] = mapped_column(String(60), default=GENERAL_PACK, index=True)
    reviewed: Mapped[bool] = mapped_column(Boolean, default=False, index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


class SeenQuestion(Base):
    """Which player saw which question when (for 'not seen recently')."""

    __tablename__ = "seen_questions"

    player_id: Mapped[str] = mapped_column(
        String(32), ForeignKey("players.id", ondelete="CASCADE"), primary_key=True
    )
    question_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("questions.id", ondelete="CASCADE"), primary_key=True
    )
    seen_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), index=True
    )
