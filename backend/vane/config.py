from functools import lru_cache

from pydantic import field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    database_url: str = "postgresql+asyncpg://vane:vane@localhost:5432/vane"
    redis_url: str = "redis://localhost:6379/0"
    log_level: str = "INFO"
    open_meteo_base: str = "https://api.open-meteo.com/v1"
    http_timeout_s: float = 10.0

    @field_validator("database_url")
    @classmethod
    def _async_driver(cls, value: str) -> str:
        """Force the asyncpg driver onto whatever URL the host hands us.

        Railway (and Heroku, and most managed Postgres) inject `postgresql://`, which
        SQLAlchemy resolves to the synchronous psycopg driver and then fails at startup with
        an error that says nothing about the scheme. Normalising here means the deploy cannot
        fail on a prefix nobody remembers.
        """
        for prefix in ("postgresql://", "postgres://"):
            if value.startswith(prefix):
                return "postgresql+asyncpg://" + value[len(prefix) :]
        return value


@lru_cache
def settings() -> Settings:
    return Settings()
