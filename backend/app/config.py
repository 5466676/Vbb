"""Runtime settings, read from environment variables (prefix ``HARB_``)."""

from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="HARB_", env_file=".env", extra="ignore")

    env: str = "dev"
    database_url: str = "postgresql+asyncpg://harb:harb@localhost:5432/harb"
    redis_url: str = "redis://localhost:6379/0"
    jwt_secret: str = "dev-only-change-me"
    admin_key: str = "dev-admin-key"


@lru_cache
def get_settings() -> Settings:
    return Settings()
