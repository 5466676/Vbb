"""offline sync, question versions, accounts, online results

Revision ID: 0002
Revises: 0001
Create Date: 2026-11-07
"""

import sqlalchemy as sa
from alembic import op

revision = "0002"
down_revision = "0001"
branch_labels = None
depends_on = None


def upgrade() -> None:
    with op.batch_alter_table("players") as b:
        b.add_column(sa.Column("username", sa.String(20), nullable=True))
        b.add_column(sa.Column("pin_hash", sa.String(200), nullable=True))
        b.add_column(sa.Column("pin_failures", sa.Integer, nullable=False, server_default="0"))
        b.add_column(sa.Column("pin_locked_until", sa.DateTime(timezone=True), nullable=True))
        b.create_unique_constraint("uq_players_username", ["username"])
    with op.batch_alter_table("questions") as b:
        b.add_column(sa.Column("version", sa.Integer, nullable=False, server_default="0"))
        b.add_column(sa.Column("deleted", sa.Boolean, nullable=False, server_default=sa.false()))
        b.create_index("ix_questions_version", ["version"])
        b.create_index("ix_questions_deleted", ["deleted"])
    op.create_table(
        "counters",
        sa.Column("name", sa.String(32), primary_key=True),
        sa.Column("value", sa.BigInteger, nullable=False, server_default="0"),
    )
    # existing questions become version 1..n
    op.execute(
        "UPDATE questions SET version ="
        " (SELECT COUNT(*) FROM questions q2 WHERE q2.id <= questions.id)"
    )
    op.execute("INSERT INTO counters (name, value) SELECT 'questions', COUNT(*) FROM questions")
    op.create_table(
        "actions",
        sa.Column("id", sa.String(36), primary_key=True),
        sa.Column(
            "player_id",
            sa.String(32),
            sa.ForeignKey("players.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("type", sa.String(16), nullable=False),
        sa.Column("session_id", sa.String(36), nullable=True),
        sa.Column("question_id", sa.Integer, nullable=True),
        sa.Column("choice", sa.SmallInteger, nullable=True),
        sa.Column("value", sa.Float, nullable=True),
        sa.Column("elapsed_ms", sa.Integer, nullable=True),
        sa.Column("client_ts", sa.DateTime(timezone=True), nullable=False),
        sa.Column(
            "received_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.Column("status", sa.String(10), nullable=False),
        sa.Column("reason", sa.String(40), nullable=False, server_default=""),
        sa.Column("correct", sa.Boolean, nullable=True),
        sa.Column("points", sa.Integer, nullable=False, server_default="0"),
    )
    op.create_index("ix_actions_player_id", "actions", ["player_id"])
    op.create_index("ix_actions_session_id", "actions", ["session_id"])
    op.create_index("ix_actions_player_ts", "actions", ["player_id", "client_ts"])
    op.create_table(
        "match_results",
        sa.Column("id", sa.Integer, primary_key=True, autoincrement=True),
        sa.Column("match_uid", sa.String(32), nullable=False),
        sa.Column(
            "player_id",
            sa.String(32),
            sa.ForeignKey("players.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("mode", sa.String(8), nullable=False),
        sa.Column("humans", sa.SmallInteger, nullable=False),
        sa.Column("players", sa.SmallInteger, nullable=False),
        sa.Column("rank", sa.SmallInteger, nullable=False),
        sa.Column("score", sa.Integer, nullable=False),
        sa.Column("correct", sa.Integer, nullable=False),
        sa.Column("won", sa.Boolean, nullable=False),
        sa.Column(
            "ended_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.UniqueConstraint("match_uid", "player_id", name="uq_match_player"),
    )
    op.create_index("ix_match_results_match_uid", "match_results", ["match_uid"])
    op.create_index("ix_match_results_player_id", "match_results", ["player_id"])
    op.create_index("ix_match_results_ended_at", "match_results", ["ended_at"])


def downgrade() -> None:
    op.drop_table("match_results")
    op.drop_table("actions")
    op.drop_table("counters")
    with op.batch_alter_table("questions") as b:
        b.drop_index("ix_questions_deleted")
        b.drop_index("ix_questions_version")
        b.drop_column("deleted")
        b.drop_column("version")
    with op.batch_alter_table("players") as b:
        b.drop_constraint("uq_players_username", type_="unique")
        b.drop_column("pin_locked_until")
        b.drop_column("pin_failures")
        b.drop_column("pin_hash")
        b.drop_column("username")
