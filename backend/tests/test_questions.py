"""Question bank: seed, validation, import, selection with anti-repeat (phase 5)."""

import json
from datetime import UTC, datetime, timedelta

import pytest
from sqlalchemy import func, select, update

from app.db import make_engine, make_sessionmaker
from app.engine.models import QuestionKind
from app.models import Player, Question, SeenQuestion
from app.models.question import CATEGORIES
from app.questions.bank import SEED_FILES, DbProvider, NoQuestions, import_questions, parse_csv


@pytest.fixture
async def sm(db_url):
    engine = make_engine(db_url)
    yield make_sessionmaker(engine)
    await engine.dispose()


async def add_players(sm, *ids):
    async with sm() as s:
        for pid in ids:
            s.add(Player(id=pid, device_id=f"dev-{pid}", name=pid))
        await s.commit()


def seed_rows() -> list[dict]:
    return [q for f in SEED_FILES for q in json.loads(f.read_text(encoding="utf-8"))]


def test_seed_file_is_balanced_and_valid():
    rows = seed_rows()
    assert len(rows) >= 450
    assert {r["category"] for r in rows} == set(CATEGORIES)
    for cat in CATEGORIES:
        assert sum(r["category"] == cat for r in rows) >= 15
    assert sum(r["type"] == "numeric" for r in rows) >= 60
    correct = [r["correct_index"] for r in rows if r["type"] == "mcq"]
    assert set(correct) == {0, 1, 2, 3}, "the correct answer is not always in the same place"
    assert len({r["text_ar"] for r in rows}) == len(rows)


async def test_seed_is_loaded_unreviewed_and_reimport_is_idempotent(sm):
    async with sm() as s:
        total = (await s.execute(select(func.count()).select_from(Question))).scalar_one()
        reviewed = (
            await s.execute(select(func.count()).where(Question.reviewed.is_(True)))
        ).scalar_one()
        res = await import_questions(s, seed_rows())
    assert total == len(seed_rows())
    assert reviewed == 0
    assert res.inserted == 0 and res.duplicates == total


async def test_import_validates_every_row(sm):
    items = [
        {
            "type": "mcq",
            "category": "علوم",
            "text_ar": "سؤال صحيح؟",
            "options_ar": ["أ", "ب", "ج", "د"],
            "correct_index": 2,
        },
        {
            "type": "mcq",
            "category": "علوم",
            "text_ar": "ثلاثة خيارات؟",
            "options_ar": ["أ", "ب", "ج"],
            "correct_index": 0,
        },
        {
            "type": "mcq",
            "category": "فلك",
            "text_ar": "فئة مجهولة؟",
            "options_ar": ["أ", "ب", "ج", "د"],
            "correct_index": 0,
        },
        {"type": "numeric", "category": "تاريخ", "text_ar": "بدون جواب؟"},
        {
            "type": "numeric",
            "category": "تاريخ",
            "text_ar": "سؤال رقمي؟",
            "numeric_answer": 12,
            "difficulty": 3,
        },
    ]
    async with sm() as s:
        res = await import_questions(s, items, pack="test", source="unit", license_="CC0")
        row = (
            await s.execute(select(Question).where(Question.text_ar == "سؤال رقمي؟"))
        ).scalar_one()
    assert res.inserted == 2
    assert [e["row"] for e in res.errors] == [1, 2, 3]
    assert row.pack == "test" and row.license == "CC0" and row.source == "unit" and not row.reviewed


def test_csv_parsing():
    text = (
        "type,category,difficulty,text_ar,option_1,option_2,option_3,option_4,correct_index,numeric_answer,unit_ar,source\n"
        "mcq,جغرافيا,1,ما عاصمة مصر؟,القاهرة,الجيزة,أسوان,الأقصر,0,,,\n"
        "numeric,علوم,2,كم ساقاً للعنكبوت؟,,,,,,8,أرجل,كتاب\n"
    )
    rows = parse_csv(text)
    assert (
        rows[0]["options_ar"] == ["القاهرة", "الجيزة", "أسوان", "الأقصر"]
        and rows[0]["correct_index"] == 0
    )
    assert (
        rows[1]["numeric_answer"] == 8.0
        and rows[1]["unit_ar"] == "أرجل"
        and "options_ar" not in rows[1]
    )


async def test_selection_avoids_questions_the_players_saw(sm):
    await add_players(sm, "a", "b")
    p = DbProvider(sm, categories=["رياضيات"])
    q1 = await p.next(QuestionKind.NUMERIC, ["a"], [])
    async with sm() as s:
        seen = (
            (await s.execute(select(SeenQuestion.question_id).where(SeenQuestion.player_id == "a")))
            .scalars()
            .all()
        )
        n = (
            await s.execute(
                select(func.count()).where(
                    Question.category == "رياضيات",
                    Question.type == "numeric",
                    Question.pack == "general",
                )
            )
        ).scalar_one()
    assert seen == [int(q1.id[1:])] and n >= 5
    # player a (with b) never gets q1 again while other questions remain
    for _ in range(n - 1):
        q = await p.next(QuestionKind.NUMERIC, ["a", "b"], [])
        assert q.id != q1.id
    # now everything was seen: the one seen longest ago (q1) comes back
    again = await p.next(QuestionKind.NUMERIC, ["a", "b"], [])
    assert again.id == q1.id


async def test_old_views_do_not_count(sm):
    await add_players(sm, "a")
    p = DbProvider(sm, categories=["رياضيات"], seen_window_days=30)
    first = await p.next(QuestionKind.NUMERIC, ["a"], [])
    async with sm() as s:
        await s.execute(update(SeenQuestion).values(seen_at=datetime.now(UTC) - timedelta(days=40)))
        await s.commit()
    picks = {(await p.next(QuestionKind.NUMERIC, ["a"], [])).id for _ in range(30)}
    assert first.id in picks or len(picks) > 1  # q1 is allowed again (random order)


async def test_used_in_match_is_never_repeated_and_difficulty_rotates(sm):
    p = DbProvider(sm)
    used: list[str] = []
    diffs = []
    async with sm() as s:
        for _ in range(9):
            q = await p.next(QuestionKind.MCQ, [], used)
            assert q.id not in used
            used.append(q.id)
            diffs.append((await s.get(Question, int(q.id[1:]))).difficulty)
    assert sorted(diffs[:3]) == [1, 2, 3]
    assert {d: diffs.count(d) for d in (1, 2, 3)} == {1: 3, 2: 3, 3: 3}


async def test_filters_categories_packs_and_review(sm):
    p = DbProvider(sm, categories=["رياضة"])
    async with sm() as s:
        for _ in range(5):
            q = await p.next(QuestionKind.MCQ, [], [])
            assert (await s.get(Question, int(q.id[1:]))).category == "رياضة"
    with pytest.raises(NoQuestions):
        await DbProvider(sm, packs=["sy-g9-science"]).next(QuestionKind.MCQ, [], [])
    with pytest.raises(NoQuestions):
        await DbProvider(sm, only_reviewed=True).next(QuestionKind.MCQ, [], [])
    async with sm() as s:
        await s.execute(update(Question).where(Question.id == 5).values(reviewed=True))
        await s.commit()
        target = await s.get(Question, 5)
    kind = QuestionKind(target.type)
    q = await DbProvider(sm, only_reviewed=True).next(kind, [], [])
    assert q.id == "q5"


async def test_engine_question_has_no_db_fields_and_answer_is_consistent(sm):
    q = await DbProvider(sm).next(QuestionKind.MCQ, [], [])
    assert q.id.startswith("q") and len(q.options) == 4 and q.correct_index in range(4)
    async with sm() as s:
        row = await s.get(Question, int(q.id[1:]))
    assert row.options_ar[row.correct_index] == q.options[q.correct_index]


def test_room_settings_validate_categories_and_packs():
    from pydantic import ValidationError

    from app.rooms.store import RoomSettings

    s = RoomSettings(categories=["علوم", "علوم", "تاريخ"], packs=["general", "sy-g9-science"])
    assert s.categories == ["علوم", "تاريخ"]
    with pytest.raises(ValidationError):
        RoomSettings(categories=["فلك"])
    with pytest.raises(ValidationError):
        RoomSettings(packs=[])
