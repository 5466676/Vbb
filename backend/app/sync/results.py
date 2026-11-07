"""Save finished online matches for the leaderboard."""

from __future__ import annotations

from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from app.db import upsert
from app.engine import core
from app.models import MatchResult
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
