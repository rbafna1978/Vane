from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    database_url: str = "postgresql+asyncpg://vane:vane@localhost:5432/vane"
    redis_url: str = "redis://localhost:6379/0"
    log_level: str = "INFO"
    open_meteo_base: str = "https://api.open-meteo.com/v1"
    http_timeout_s: float = 10.0


@lru_cache
def settings() -> Settings:
    return Settings()
