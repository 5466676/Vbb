"""players, questions, seen_questions

Revision ID: 0001
Revises:
Create Date: 2026-11-07
"""

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision = "0001"
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "players",
        sa.Column("id", sa.String(32), primary_key=True),
        sa.Column("device_id", sa.String(128), nullable=False),
        sa.Column("name", sa.String(24), nullable=False, server_default=""),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.Column(
            "last_seen_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
    )
    op.create_index("ix_players_device_id", "players", ["device_id"], unique=True)
    op.create_table(
        "questions",
        sa.Column("id", sa.Integer, primary_key=True, autoincrement=True),
        sa.Column("type", sa.String(8), nullable=False),
        sa.Column("category", sa.String(40), nullable=False),
        sa.Column("difficulty", sa.SmallInteger, nullable=False, server_default="2"),
        sa.Column("text_ar", sa.Text, nullable=False, unique=True),
        sa.Column("options_ar", postgresql.ARRAY(sa.Text), nullable=True),
        sa.Column("correct_index", sa.SmallInteger, nullable=True),
        sa.Column("numeric_answer", sa.Float, nullable=True),
        sa.Column("unit_ar", sa.String(40), nullable=False, server_default=""),
        sa.Column("source", sa.String(200), nullable=False, server_default=""),
        sa.Column("license", sa.String(40), nullable=False, server_default=""),
        sa.Column("pack", sa.String(60), nullable=False, server_default="general"),
        sa.Column("reviewed", sa.Boolean, nullable=False, server_default=sa.false()),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.Column(
            "updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.CheckConstraint("difficulty BETWEEN 1 AND 3", name="difficulty_range"),
        sa.CheckConstraint(
            "(type = 'mcq' AND correct_index BETWEEN 0 AND 3 AND cardinality(options_ar) = 4)"
            " OR (type = 'numeric' AND numeric_answer IS NOT NULL)",
            name="shape_by_type",
        ),
    )
    for col in ("type", "category", "pack", "reviewed"):
        op.create_index(f"ix_questions_{col}", "questions", [col])
    op.create_table(
        "seen_questions",
        sa.Column(
            "player_id",
            sa.String(32),
            sa.ForeignKey("players.id", ondelete="CASCADE"),
            primary_key=True,
        ),
        sa.Column(
            "question_id",
            sa.Integer,
            sa.ForeignKey("questions.id", ondelete="CASCADE"),
            primary_key=True,
        ),
        sa.Column(
            "seen_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
    )
    op.create_index("ix_seen_questions_seen_at", "seen_questions", ["seen_at"])


def downgrade() -> None:
    op.drop_table("seen_questions")
    op.drop_table("questions")
    op.drop_table("players")
