"""Guest accounts: a JWT tied to a device id (brief §2, auth).

The device -> player id mapping lives in Redis for now; phase 5 moves accounts to PostgreSQL.
"""

from __future__ import annotations

import time
import uuid

import jwt
from redis.asyncio import Redis

from app.config import Settings

ALGORITHM = "HS256"


class AuthError(Exception):
    pass


async def guest_player_id(redis: Redis, device_id: str) -> str:
    """Stable player id for a device (created on first use)."""
    key = f"device:{device_id}"
    new = uuid.uuid4().hex
    await redis.set(key, new, nx=True)
    return (await redis.get(key)).decode()


def create_token(settings: Settings, player_id: str, name: str) -> str:
    now = int(time.time())
    payload = {
        "sub": player_id,
        "name": name,
        "iat": now,
        "exp": now + settings.jwt_ttl_days * 86400,
    }
    return jwt.encode(payload, settings.jwt_secret, algorithm=ALGORITHM)


def verify_token(settings: Settings, token: str) -> tuple[str, str]:
    """Return (player_id, name) or raise AuthError."""
    try:
        data = jwt.decode(token, settings.jwt_secret, algorithms=[ALGORITHM])
    except jwt.PyJWTError as e:
        raise AuthError(str(e)) from e
    return data["sub"], data.get("name", "")
