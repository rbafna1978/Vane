from typing import Annotated

import httpx
from fastapi import Depends, Request
from redis.asyncio import Redis
from sqlalchemy.ext.asyncio import AsyncSession

from vane.db import get_session
from vane.sources.base import WeatherSource
from vane.sources.openmeteo import OpenMeteoSource


def get_redis(request: Request) -> Redis:
    redis: Redis = request.app.state.redis
    return redis


def get_source(request: Request) -> WeatherSource:
    # Overridden wholesale in tests by a FakeSource, which is the reason ADR-0003 keeps a
    # protocol here at all: the context engine must be testable without network.
    client: httpx.AsyncClient = request.app.state.http
    return OpenMeteoSource(client)


RedisDep = Annotated[Redis, Depends(get_redis)]
SourceDep = Annotated[WeatherSource, Depends(get_source)]
SessionDep = Annotated[AsyncSession, Depends(get_session)]
