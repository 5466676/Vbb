"""Curriculum packs (extension point, brief §6).

A pack is a named set of questions stored in the same table as the general bank, with
``questions.pack`` set (e.g. ``sy-g9-science`` for Syrian 9th grade science, ``sy-bac-history``).
Rooms choose packs through ``RoomSettings.packs``.

To connect an external bank (EduSpark), implement ``PackSource.fetch`` so it returns question
dicts in the ``QuestionIn`` shape, register it, and call ``sync_pack``. Re-syncing is safe:
questions already present (same text) are skipped.
"""

from __future__ import annotations

from typing import Any, Protocol

from sqlalchemy.ext.asyncio import AsyncSession

from app.questions.bank import ImportResult, import_questions


class PackSource(Protocol):
    name: str
    license: str

    async def list_packs(self) -> list[str]: ...

    async def fetch(self, pack_id: str) -> list[dict[str, Any]]:
        """Questions in the QuestionIn shape (type, category, difficulty, text_ar, ...)."""
        ...


class EduSparkSource:
    """Placeholder for the owner's EduSpark question bank (to be connected later).

    Expected mapping: EduSpark subject -> pack id ``sy-<grade>-<subject>``, EduSpark question
    -> QuestionIn (category from the subject, difficulty 1-3 from EduSpark's level).
    """

    name = "eduspark"
    license = "owner"

    def __init__(self, base_url: str = "", api_key: str = "") -> None:
        self.base_url = base_url
        self.api_key = api_key

    async def list_packs(self) -> list[str]:
        raise NotImplementedError("EduSpark is not connected yet")

    async def fetch(self, pack_id: str) -> list[dict[str, Any]]:
        raise NotImplementedError("EduSpark is not connected yet")


SOURCES: dict[str, PackSource] = {}


def register(source: PackSource) -> None:
    SOURCES[source.name] = source


async def sync_pack(session: AsyncSession, source: PackSource, pack_id: str) -> ImportResult:
    items = await source.fetch(pack_id)
    return await import_questions(
        session, items, pack=pack_id, source=source.name, license_=source.license, reviewed=False
    )
