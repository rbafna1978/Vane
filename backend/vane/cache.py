"""Redis cache. TTLs are matched to how often the upstream actually changes, not guessed."""

from __future__ import annotations

import contextlib
import logging

from pydantic import BaseModel
from redis.asyncio import Redis
from redis.exceptions import RedisError

log = logging.getLogger(__name__)

SNAPSHOT_TTL_S = 600  # Open-Meteo current refreshes ~15 min; 10 keeps us just ahead of it.
FORECAST_TTL_S = 3600  # Model runs are hourly at best.


async def get_model[T: BaseModel](redis: Redis, key: str, model: type[T]) -> T | None:
    """Read from cache. Every failure mode is a miss, never an error.

    Redis is an optimisation here, not a source of truth — the provider can answer every
    request without it. Letting a Redis outage raise would turn a slower app into a down app.
    """
    try:
        raw = await redis.get(key)
    except RedisError:
        log.warning("cache read failed for %s; falling through to source", key, exc_info=True)
        return None

    if raw is None:
        return None
    try:
        return model.model_validate_json(raw)
    except ValueError:
        # A stale value written by an older schema is a miss, not an outage.
        with contextlib.suppress(RedisError):
            await redis.delete(key)
        return None


async def set_model(redis: Redis, key: str, value: BaseModel, ttl_s: int) -> None:
    """Write to cache. A failed write costs an upstream call next time, nothing more."""
    try:
        await redis.set(key, value.model_dump_json(), ex=ttl_s)
    except RedisError:
        log.warning("cache write failed for %s", key, exc_info=True)
