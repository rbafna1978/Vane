import logging
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

import httpx
from arq.connections import RedisSettings, create_pool
from fastapi import FastAPI
from redis.asyncio import Redis

from vane import errors
from vane.config import settings
from vane.db import dispose
from vane.routes import health, weather


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    # One AsyncClient for the process. Creating one per request throws away connection pooling
    # and TLS session reuse, which is most of the latency on an upstream call.
    app.state.http = httpx.AsyncClient(timeout=settings().http_timeout_s)
    # Explicit socket timeouts: without them a hung Redis holds the request open until the
    # client gives up, which converts a cache problem into an outage. Two seconds is far above
    # a healthy local round trip and far below anyone's patience.
    app.state.redis = Redis.from_url(
        settings().redis_url,
        decode_responses=True,
        socket_timeout=2.0,
        socket_connect_timeout=2.0,
    )
    app.state.arq = await create_pool(RedisSettings.from_dsn(settings().redis_url))
    try:
        yield
    finally:
        await app.state.arq.aclose()
        await app.state.http.aclose()
        await app.state.redis.aclose()
        await dispose()


def create_app() -> FastAPI:
    logging.basicConfig(level=settings().log_level)
    app = FastAPI(title="Vane", version="0.1.0", lifespan=lifespan)
    errors.install(app)
    app.include_router(health.router)
    app.include_router(weather.router)
    return app


app = create_app()
