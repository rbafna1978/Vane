import contextlib
from typing import Annotated

from arq.connections import ArqRedis as ArqPool
from fastapi import APIRouter, Query, Request, Response
from redis.asyncio import Redis
from sqlalchemy.ext.asyncio import AsyncSession

from vane import context as ctx
from vane.cache import FORECAST_TTL_S, SNAPSHOT_TTL_S, get_model, set_model
from vane.cells import Cell, InvalidCoordinate, cell_for
from vane.cells_repo import touch
from vane.deps import ArqDep, RedisDep, SessionDep, SourceDep
from vane.errors import ApiError
from vane.http import etag_response
from vane.schemas import Context, ContextResponse, Forecast, NormalBand, Snapshot
from vane.sources.base import SnapshotData, WeatherSource

router = APIRouter(prefix="/v1")

Lat = Annotated[float, Query(ge=-90, le=90)]
Lon = Annotated[float, Query(ge=-180, le=180)]


@router.get("/snapshot")
async def snapshot(
    request: Request,
    lat: Lat,
    lon: Lon,
    redis: RedisDep,
    session: SessionDep,
    source: SourceDep,
    arq: ArqDep,
) -> Response:
    """Everything the main screen needs, in one request.

    Collapsed from the brief's three calls (conditions + forecast + context) because a cold
    cellular launch paying three round trips for one screen is the difference between the app
    feeling instant and feeling like a website.
    """
    try:
        cell = cell_for(lat, lon)
    except InvalidCoordinate as exc:
        raise ApiError("invalid_coordinate", str(exc), status=400) from exc

    state = await touch(session, cell)
    if state == "cold":
        # Enqueue and return. A cold cell must not make someone wait ~4s holding a phone
        # (ADR-0004); the screen renders without its context line and gains one next open.
        await enqueue_backfill(arq, cell.id)
        state = "warming"

    data = await _snapshot_data(redis, source, cell)
    context, normal = await _context_for(session, cell.id, data, state)
    body = Snapshot(
        cell_id=cell.id,
        observed_at=data.observed_at,
        utc_offset_seconds=data.utc_offset_seconds,
        current=data.current,
        arc=data.arc,
        normal=normal,
        context=context,
        context_state=state,
        sun=data.sun,
    )
    return etag_response(request, body, SNAPSHOT_TTL_S)


@router.get("/forecast")
async def forecast(
    request: Request,
    lat: Lat,
    lon: Lon,
    redis: RedisDep,
    session: SessionDep,
    source: SourceDep,
    days: Annotated[int, Query(ge=1, le=16)] = 7,
) -> Response:
    try:
        cell = cell_for(lat, lon)
    except InvalidCoordinate as exc:
        raise ApiError("invalid_coordinate", str(exc), status=400) from exc

    key = f"src:forecast:{cell.id}:{days}"
    data = await get_model(redis, key, Forecast)
    if data is None:
        data = await source.forecast(cell, days)
        await set_model(redis, key, data, FORECAST_TTL_S)

    # Normals are attached after the cache, not inside it: the provider payload and thirty
    # years of history change on completely different clocks, and baking normals into a
    # one-hour cache entry would freeze them there.
    normals = await ctx.normals_for(session, cell.id, [day.d for day in data.daily])
    if normals:
        data = data.model_copy(
            update={
                "daily": [
                    day.model_copy(update={"normal": normals.get(day.d)})
                    for day in data.daily
                ]
            }
        )

    return etag_response(request, data, FORECAST_TTL_S)


async def _snapshot_data(redis: Redis, source: WeatherSource, cell: Cell) -> SnapshotData:
    key = f"src:snapshot:{cell.id}"
    # ponytail: no single-flight lock. When a popular cell's entry expires, every concurrent
    # request misses and calls Open-Meteo. Harmless at current traffic; add a Redis SETNX
    # lease around the fetch if the rate-limit metric starts moving.
    data = await get_model(redis, key, SnapshotData)
    if data is None:
        data = await source.snapshot(cell)
        await set_model(redis, key, data, SNAPSHOT_TTL_S)
    return data


async def _context_for(
    session: AsyncSession, cell_id: str, data: SnapshotData, state: str
) -> tuple[Context | None, NormalBand | None]:
    if state != "warm":
        return None, None
    today = data.observed_at.date()
    facts = await ctx.gather(session, cell_id, today, data.today_tmax_c)
    return ctx.choose(facts, today, rain_today=_rain_today(data)), facts.normal


def _rain_today(data: SnapshotData) -> bool:
    """Any measurable precipitation left in today's arc, from now on."""
    now = data.observed_at
    return any(p.precip_mm >= ctx.WET_DAY_MM for p in data.arc if p.t >= now)


async def enqueue_backfill(arq: ArqPool, cell_id: str) -> None:
    """Idempotent on cell_id: two devices in the same cold cell must queue one job, not two.

    arq deduplicates on _job_id, so a second enqueue while the first is pending or running is
    dropped rather than doubling a 30-year fetch.
    """
    with contextlib.suppress(Exception):
        await arq.enqueue_job("run_backfill", cell_id, _job_id=f"backfill:{cell_id}")


@router.get("/context")
async def context_only(
    request: Request,
    lat: Lat,
    lon: Lon,
    redis: RedisDep,
    session: SessionDep,
    source: SourceDep,
    arq: ArqDep,
) -> Response:
    """The context line alone — separately addressable for the morning push worker, which
    wants the sentence and nothing else."""
    try:
        cell = cell_for(lat, lon)
    except InvalidCoordinate as exc:
        raise ApiError("invalid_coordinate", str(exc), status=400) from exc

    state = await touch(session, cell)
    if state == "cold":
        await enqueue_backfill(arq, cell.id)
        state = "warming"

    data = await _snapshot_data(redis, source, cell)
    context, normal = await _context_for(session, cell.id, data, state)
    body = ContextResponse(
        cell_id=cell.id, context=context, context_state=state, normal=normal
    )
    return etag_response(request, body, SNAPSHOT_TTL_S)
