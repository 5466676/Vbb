"""Runtime settings, read from environment variables (prefix ``HARB_``)."""

import uuid
from functools import lru_cache

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="HARB_", env_file=".env", extra="ignore")

    env: str = "dev"
    database_url: str = "postgresql+asyncpg://harb:harb@localhost:5432/harb"
    redis_url: str = "redis://localhost:6379/0"
    jwt_secret: str = "dev-only-secret-change-me-in-production-32b"
    jwt_ttl_days: int = 30
    admin_key: str = "dev-admin-key"

    # identity of this server process (several workers can share Redis)
    worker_id: str = Field(default_factory=lambda: uuid.uuid4().hex[:12])
    # multiply every room-side duration (timers, pauses, bot thinking). Tests use ~0.02.
    time_scale: float = 1.0
    reconnect_grace_s: float = 30.0
    quick_match_wait_s: float = 20.0
    room_lease_s: float = 6.0
    # rate limit per connection: sustained messages per second and burst
    rate_per_s: float = 15.0
    rate_burst: int = 40


@lru_cache
def get_settings() -> Settings:
    return Settings()
