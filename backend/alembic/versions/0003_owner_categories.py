"""rename three categories to the owner's names

Revision ID: 0003
Revises: 0002
Create Date: 2026-11-07
"""

import sqlalchemy as sa
from alembic import op

revision = "0003"
down_revision = "0002"
branch_labels = None
depends_on = None

RENAMES = {"دين": "دين إسلامي", "لغة عربية": "لغة وأدب", "ثقافة عامة": "ثقافة وفن"}


def _rename(pairs: dict[str, str]) -> None:
    q = sa.table("questions", sa.column("category", sa.String))
    for old, new in pairs.items():
        op.execute(q.update().where(q.c.category == old).values(category=new))


def upgrade() -> None:
    _rename(RENAMES)


def downgrade() -> None:
    _rename({new: old for old, new in RENAMES.items()})
