"""arq worker (ADR-0004).

Reuses the Redis that already backs the forecast cache, so durable retry costs a library
rather than new infrastructure. A backfill that dies mid-flight — deploy, crash, upstream
blip — is retried rather than silently lost, which matters because the thing being lost is
the only reason this app is not another forecast viewer.
"""

from typing import Any

import httpx
from arq.connections import RedisSettings

from vane.backfill import run_backfill
from vane.config import settings
from vane.db import dispose


async def startup(ctx: dict[str, Any]) -> None:
    ctx["http"] = httpx.AsyncClient(timeout=settings().http_timeout_s)


async def shutdown(ctx: dict[str, Any]) -> None:
    await ctx["http"].aclose()
    await dispose()


class WorkerSettings:
    functions = [run_backfill]
    on_startup = startup
    on_shutdown = shutdown
    redis_settings = RedisSettings.from_dsn(settings().redis_url)
    # A cell backfill is one 3.5s request plus an aggregate. Three attempts covers an upstream
    # blip; more would just hammer a source that is genuinely down.
    max_tries = 3
    job_timeout = 180
    # Concurrency of 1. Measured, not guessed: four parallel archive fetches trip Open-Meteo's
    # minutely limit and the jobs burn retries on a rate limit we inflicted on ourselves. A
    # backfill takes ~2.5s and only ever runs once per cell, so serialising costs nothing that
    # anyone waits on — the requester already got their screen without a context line.
    max_jobs = 1
