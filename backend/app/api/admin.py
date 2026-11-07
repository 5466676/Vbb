"""Question-bank admin (brief §6): import, review, edit. Protected by ``X-Admin-Key``."""

from __future__ import annotations

import hmac
import json

from fastapi import APIRouter, Depends, File, Header, HTTPException, Query, Request, UploadFile
from pydantic import BaseModel, Field
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Question
from app.models.question import GENERAL_PACK
from app.questions.bank import ImportResult, QuestionIn, import_questions, next_version, parse_csv

router = APIRouter(prefix="/admin", tags=["admin"])
MAX_UPLOAD = 5 * 1024 * 1024


def require_admin(request: Request, x_admin_key: str = Header(default="")) -> None:
    expected = request.app.state.settings.admin_key
    if not x_admin_key or not hmac.compare_digest(x_admin_key, expected):
        raise HTTPException(status_code=401, detail="bad admin key")


async def session(request: Request):
    async with request.app.state.sessionmaker() as s:
        yield s


class ImportOptions(BaseModel):
    pack: str = Field(default=GENERAL_PACK, max_length=60)
    source: str = Field(default="", max_length=200)
    license: str = Field(default="", max_length=40)
    reviewed: bool = False


def _options(
    pack: str = Query(GENERAL_PACK, max_length=60),
    source: str = Query("", max_length=200),
    license: str = Query("", max_length=40),
    reviewed: bool = Query(False),
) -> ImportOptions:
    return ImportOptions(pack=pack, source=source, license=license, reviewed=reviewed)


@router.post(
    "/questions/import", response_model=ImportResult, dependencies=[Depends(require_admin)]
)
async def import_json(
    items: list[dict],
    opts: ImportOptions = Depends(_options),
    s: AsyncSession = Depends(session),
) -> ImportResult:
    return await import_questions(
        s, items, pack=opts.pack, source=opts.source, license_=opts.license, reviewed=opts.reviewed
    )


@router.post(
    "/questions/import-file", response_model=ImportResult, dependencies=[Depends(require_admin)]
)
async def import_file(
    file: UploadFile = File(...),
    opts: ImportOptions = Depends(_options),
    s: AsyncSession = Depends(session),
) -> ImportResult:
    raw = await file.read(MAX_UPLOAD + 1)
    if len(raw) > MAX_UPLOAD:
        raise HTTPException(status_code=413, detail="file larger than 5 MB")
    name = (file.filename or "").lower()
    try:
        text = raw.decode("utf-8-sig")
        items = parse_csv(text) if name.endswith(".csv") else json.loads(text)
    except (ValueError, KeyError) as e:
        raise HTTPException(status_code=400, detail=f"cannot read file: {e}") from e
    if not isinstance(items, list):
        raise HTTPException(status_code=400, detail="expected a JSON array of questions")
    return await import_questions(
        s, items, pack=opts.pack, source=opts.source, license_=opts.license, reviewed=opts.reviewed
    )


def _out(q: Question) -> dict:
    return {
        "id": q.id,
        "type": q.type,
        "category": q.category,
        "difficulty": q.difficulty,
        "text_ar": q.text_ar,
        "options_ar": q.options_ar,
        "correct_index": q.correct_index,
        "numeric_answer": q.numeric_answer,
        "unit_ar": q.unit_ar,
        "source": q.source,
        "license": q.license,
        "pack": q.pack,
        "reviewed": q.reviewed,
    }


@router.get("/questions", dependencies=[Depends(require_admin)])
async def list_questions(
    reviewed: bool | None = None,
    category: str | None = None,
    pack: str | None = None,
    type: str | None = None,
    limit: int = Query(50, ge=1, le=500),
    offset: int = Query(0, ge=0),
    s: AsyncSession = Depends(session),
) -> dict:
    q = select(Question).where(Question.deleted.is_(False))
    if reviewed is not None:
        q = q.where(Question.reviewed.is_(reviewed))
    if category:
        q = q.where(Question.category == category)
    if pack:
        q = q.where(Question.pack == pack)
    if type:
        q = q.where(Question.type == type)
    total = (await s.execute(select(func.count()).select_from(q.subquery()))).scalar_one()
    rows = (await s.execute(q.order_by(Question.id).limit(limit).offset(offset))).scalars().all()
    return {"total": total, "items": [_out(r) for r in rows]}


@router.get("/questions/stats", dependencies=[Depends(require_admin)])
async def stats(s: AsyncSession = Depends(session)) -> dict:
    rows = await s.execute(
        select(Question.pack, Question.category, Question.type, Question.reviewed, func.count())
        .where(Question.deleted.is_(False))
        .group_by(Question.pack, Question.category, Question.type, Question.reviewed)
    )
    out = [
        {"pack": p, "category": c, "type": t, "reviewed": r, "count": n} for p, c, t, r, n in rows
    ]
    return {"total": sum(x["count"] for x in out), "groups": out}


class QuestionPatch(BaseModel):
    category: str | None = None
    difficulty: int | None = Field(default=None, ge=1, le=3)
    text_ar: str | None = None
    options_ar: list[str] | None = None
    correct_index: int | None = None
    numeric_answer: float | None = None
    unit_ar: str | None = None
    reviewed: bool | None = None


@router.patch("/questions/{qid}", dependencies=[Depends(require_admin)])
async def update_question(
    qid: int, patch: QuestionPatch, s: AsyncSession = Depends(session)
) -> dict:
    q = await s.get(Question, qid)
    if q is None or q.deleted:
        raise HTTPException(status_code=404, detail="no such question")
    merged = _out(q) | patch.model_dump(exclude_unset=True)
    try:
        QuestionIn.model_validate(merged)  # the edited question must still be valid
    except ValueError as e:
        raise HTTPException(status_code=422, detail=str(e)) from e
    for k, v in patch.model_dump(exclude_unset=True).items():
        setattr(q, k, v)
    q.version = await next_version(s)
    await s.commit()
    await s.refresh(q)
    return _out(q)


@router.delete("/questions/{qid}", dependencies=[Depends(require_admin)], status_code=204)
async def delete_question(qid: int, s: AsyncSession = Depends(session)) -> None:
    q = await s.get(Question, qid)
    if q is None or q.deleted:
        raise HTTPException(status_code=404, detail="no such question")
    # kept as a tombstone so offline devices learn about the deletion on their next sync
    q.deleted = True
    q.version = await next_version(s)
    await s.commit()
