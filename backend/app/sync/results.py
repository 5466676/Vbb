"""Save finished online matches for the leaderboard, and total experience for ranks."""

from __future__ import annotations

from collections.abc import Awaitable, Callable

from sqlalchemy import Integer, cast, func, select
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from app.db import upsert
from app.engine import core
from app.models import MatchResult
from app.ranks import total_xp
from app.rooms.actor import ResultsSink
from app.rooms.store import RoomData


def db_results_sink(sessionmaker: async_sessionmaker[AsyncSession]) -> ResultsSink:
    async def save(match_uid: str, room: RoomData) -> None:
        m = room.match
        assert m is not None
        rows = core.standings(m)
        humans = [i for i, seat in enumerate(room.seats) if seat.player_id]
        async with sessionmaker() as s:
            for rank, row in enumerate(rows, 1):
                seat = room.seats[row["seat"]]
                if not seat.player_id:
                    continue  # bots are not on the leaderboard
                stmt = (
                    upsert(s, MatchResult)
                    .values(
                        match_uid=match_uid,
                        player_id=seat.player_id,
                        mode=m.settings.mode.value,
                        humans=len(humans),
                        players=len(room.seats),
                        rank=rank,
                        score=row["score"],
                        correct=row["correct"],
                        won=row["team"] == m.winner_team,
                    )
                    .on_conflict_do_nothing(index_elements=["match_uid", "player_id"])
                )
                await s.execute(stmt)
            await s.commit()

    return save


def db_xp_lookup(sessionmaker: async_sessionmaker[AsyncSession]) -> Callable[[str], Awaitable[int]]:
    """Total experience of a player, summed over their saved online matches."""

    async def lookup(player_id: str) -> int:
        async with sessionmaker() as s:
            matches, correct, wins = (
                await s.execute(
                    select(
                        func.count(),
                        func.coalesce(func.sum(MatchResult.correct), 0),
                        func.coalesce(func.sum(cast(MatchResult.won, Integer)), 0),
                    ).where(MatchResult.player_id == player_id)
                )
            ).one()
            return total_xp(int(matches), int(correct), int(wins))

    return lookup
