"""Optional account restore on a new device: a username plus a short PIN.

PINs are stored as salted scrypt hashes. Wrong PINs lock the username: 5 failures lock it for
15 minutes, and every further 5 failures double the lock (up to a day), so guessing a 4-digit
PIN takes years.
"""

from __future__ import annotations

import hashlib
import hmac
import re
import secrets
import uuid
from datetime import UTC, datetime, timedelta

from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Player

USERNAME = re.compile(r"^[\w؀-ۿ]{3,20}$")
PIN = re.compile(r"^\d{4,8}$")
FAILS_PER_LOCK = 5
BASE_LOCK = timedelta(minutes=15)
MAX_LOCK = timedelta(days=1)


class AccountError(Exception):
    def __init__(self, code: str, status: int, message: str) -> None:
        super().__init__(message)
        self.code, self.status, self.message = code, status, message


def normalize_username(name: str) -> str:
    name = name.strip().lower()
    if not USERNAME.match(name):
        raise AccountError("bad_username", 422, "3-20 letters, digits or _")
    return name


def hash_pin(pin: str, salt: bytes | None = None) -> str:
    if not PIN.match(pin):
        raise AccountError("bad_pin", 422, "the PIN is 4-8 digits")
    salt = salt or secrets.token_bytes(16)
    digest = hashlib.scrypt(pin.encode(), salt=salt, n=2**14, r=8, p=1, dklen=32)
    return f"scrypt${salt.hex()}${digest.hex()}"


def check_pin(pin: str, stored: str) -> bool:
    try:
        _, salt, digest = stored.split("$")
        again = hash_pin(pin, bytes.fromhex(salt)).split("$")[2]
    except (ValueError, AccountError):
        return False
    return hmac.compare_digest(again, digest)


def lock_for(failures: int) -> timedelta | None:
    if failures < FAILS_PER_LOCK or failures % FAILS_PER_LOCK:
        return None
    doublings = min(failures // FAILS_PER_LOCK - 1, 10)  # 15 min * 2**7 > a day already
    return min(BASE_LOCK * 2**doublings, MAX_LOCK)


async def set_account(s: AsyncSession, pid: str, username: str, pin: str) -> str:
    name = normalize_username(username)
    taken = await s.execute(select(Player.id).where(Player.username == name, Player.id != pid))
    if taken.first() is not None:
        raise AccountError("username_taken", 409, "this username is taken")
    await s.execute(
        update(Player)
        .where(Player.id == pid)
        .values(username=name, pin_hash=hash_pin(pin), pin_failures=0, pin_locked_until=None)
    )
    await s.commit()
    return name


def _aware(dt: datetime | None) -> datetime | None:
    return dt.replace(tzinfo=UTC) if dt is not None and dt.tzinfo is None else dt


async def restore(s: AsyncSession, username: str, pin: str, device_id: str) -> Player:
    """Move the account to ``device_id``. Any guest player on that device is detached."""
    name = normalize_username(username)
    p = (await s.execute(select(Player).where(Player.username == name))).scalar_one_or_none()
    now = datetime.now(UTC)
    if p is None or p.pin_hash is None:
        hash_pin("0000")  # same cost as a real check
        raise AccountError("bad_login", 401, "wrong username or PIN")
    locked = _aware(p.pin_locked_until)
    if locked is not None and locked > now:
        raise AccountError("locked", 429, f"too many tries; wait until {locked.isoformat()}")
    if not check_pin(pin, p.pin_hash):
        p.pin_failures += 1
        lock = lock_for(p.pin_failures)
        if lock:
            p.pin_locked_until = now + lock
        await s.commit()
        raise AccountError("bad_login", 401, "wrong username or PIN")
    if p.device_id != device_id:
        await s.execute(
            update(Player)
            .where(Player.device_id == device_id)
            .values(device_id=f"detached:{uuid.uuid4().hex}")
        )
        p.device_id = device_id
    p.pin_failures = 0
    p.pin_locked_until = None
    await s.commit()
    return p
