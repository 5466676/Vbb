"""Offline-first REST: POST /sync, GET /questions, GET /leaderboard, account restore."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta
from typing import Literal

from fastapi import APIRouter, Depends, Header, HTTPException, Query, Request
from pydantic import BaseModel, Field
from sqlalchemy import Integer, cast, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth import AuthError, create_token, verify_token
from app.models import MatchResult, Player
from app.sync import accounts
from app.sync.service import (
    SyncIn,
    apply_actions,
    parse_actions,
    player_stats,
    questions_since,
)

router = APIRouter(tags=["sync"])
LEADERBOARD_MIN_HUMANS = 2  # wins against bots only do not count


async def session(request: Request):
    async with request.app.state.sessionmaker() as s:
        yield s


def player_id(request: Request, authorization: str = Header(default="")) -> str:
    token = authorization.removeprefix("Bearer ").strip()
    try:
        pid, _ = verify_token(request.app.state.settings, token)
    except AuthError as e:
        raise HTTPException(status_code=401, detail="bad or expired token") from e
    return pid


@router.post("/sync")
async def sync(
    body: SyncIn, pid: str = Depends(player_id), s: AsyncSession = Depends(session)
) -> dict:
    actions, invalid = parse_actions(body.actions)
    results = invalid + await apply_actions(s, pid, actions)
    out = {
        "results": [
            r.model_dump(exclude_defaults=True) | {"id": r.id, "status": r.status} for r in results
        ],
        "stats": await player_stats(s, pid),
        "server_time": datetime.now(UTC).isoformat(),
    }
    if body.questions_since is not None:
        out["questions"] = await questions_since(s, body.questions_since)
    return out


@router.get("/questions")
async def questions(
    since: int = Query(0, ge=0),
    limit: int = Query(500, ge=1, le=1000),
    s: AsyncSession = Depends(session),
) -> dict:
    """Solo-pack questions (with answers) changed after ``since``; page until ``more`` is false."""
    return await questions_since(s, since, limit)


@router.get("/me/stats")
async def my_stats(pid: str = Depends(player_id), s: AsyncSession = Depends(session)) -> dict:
    return await player_stats(s, pid)


@router.get("/leaderboard")
async def leaderboard(
    request: Request,
    period: Literal["all", "week"] = "all",
    limit: int = Query(50, ge=1, le=200),
    authorization: str = Header(default=""),
    s: AsyncSession = Depends(session),
) -> dict:
    """Online matches only (offline answers can be faked). Matches with one human are skipped."""
    wins = func.sum(cast(MatchResult.won, Integer))
    score = func.sum(MatchResult.score)
    q = (
        select(
            MatchResult.player_id,
            Player.name,
            func.count().label("matches"),
            wins.label("wins"),
            score.label("score"),
        )
        .join(Player, Player.id == MatchResult.player_id)
        .where(MatchResult.humans >= LEADERBOARD_MIN_HUMANS)
        .group_by(MatchResult.player_id, Player.name)
        .order_by(wins.desc(), score.desc(), MatchResult.player_id)
    )
    if period == "week":
        q = q.where(MatchResult.ended_at >= datetime.now(UTC) - timedelta(days=7))
    rows = (await s.execute(q)).all()
    table = [
        {
            "rank": i + 1,
            "player": pid[:8],
            "name": name or f"ضيف {pid[:4]}",
            "matches": int(m),
            "wins": int(w or 0),
            "score": int(sc or 0),
        }
        for i, (pid, name, m, w, sc) in enumerate(rows)
    ]
    out: dict = {"period": period, "rows": table[:limit]}
    if authorization:
        try:
            me, _ = verify_token(
                request.app.state.settings, authorization.removeprefix("Bearer ").strip()
            )
        except AuthError:
            me = None
        if me is not None:
            out["me"] = next((r for r in table if r["player"] == me[:8]), None)
    return out


class AccountIn(BaseModel):
    username: str = Field(max_length=40)
    pin: str = Field(max_length=16)


class RestoreIn(AccountIn):
    device_id: str = Field(min_length=8, max_length=128)


def _raise(e: accounts.AccountError) -> HTTPException:
    return HTTPException(status_code=e.status, detail={"code": e.code, "message": e.message})


@router.post("/auth/account")
async def set_account(
    body: AccountIn, pid: str = Depends(player_id), s: AsyncSession = Depends(session)
) -> dict:
    """Give the current player a username + PIN so the account can be restored elsewhere."""
    try:
        name = await accounts.set_account(s, pid, body.username, body.pin)
    except accounts.AccountError as e:
        raise _raise(e) from e
    return {"username": name}


@router.post("/auth/restore")
async def restore(body: RestoreIn, request: Request, s: AsyncSession = Depends(session)) -> dict:
    """New device: move the account here and return a token for it."""
    try:
        p = await accounts.restore(s, body.username, body.pin, body.device_id)
    except accounts.AccountError as e:
        raise _raise(e) from e
    name = p.name or f"ضيف {p.id[:4]}"
    return {
        "token": create_token(request.app.state.settings, p.id, name),
        "player_id": p.id,
        "name": name,
    }
