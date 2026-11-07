"""Guest accounts: a JWT tied to a device id (brief §2, auth)."""

from __future__ import annotations

import time
import uuid

import jwt
from sqlalchemy import func
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import Settings
from app.models import Player

ALGORITHM = "HS256"


class AuthError(Exception):
    pass


async def guest_player_id(session: AsyncSession, device_id: str, name: str) -> tuple[str, str]:
    """Stable player for a device (created on first use). Returns (player_id, name)."""
    stmt = (
        insert(Player)
        .values(id=uuid.uuid4().hex, device_id=device_id, name=name)
        .on_conflict_do_update(
            index_elements=["device_id"],
            set_={"last_seen_at": func.now(), **({"name": name} if name else {})},
        )
        .returning(Player.id, Player.name)
    )
    pid, stored = (await session.execute(stmt)).one()
    await session.commit()
    return pid, stored


def create_token(settings: Settings, player_id: str, name: str) -> str:
    now = int(time.time())
    exp = now + settings.jwt_ttl_days * 86400
    payload = {"sub": player_id, "name": name, "iat": now, "exp": exp}
    return jwt.encode(payload, settings.jwt_secret, algorithm=ALGORITHM)


def verify_token(settings: Settings, token: str) -> tuple[str, str]:
    """Return (player_id, name) or raise AuthError."""
    try:
        data = jwt.decode(token, settings.jwt_secret, algorithms=[ALGORITHM])
    except jwt.PyJWTError as e:
        raise AuthError(str(e)) from e
    return data["sub"], data.get("name", "")
