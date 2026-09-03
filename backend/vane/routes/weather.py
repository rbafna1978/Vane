from typing import Annotated

from fastapi import APIRouter, Query, Request, Response

from vane.cache import FORECAST_TTL_S, SNAPSHOT_TTL_S, get_model, set_model
from vane.cells import InvalidCoordinate, cell_for
from vane.cells_repo import touch
from vane.deps import RedisDep, SessionDep, SourceDep
from vane.errors import ApiError
from vane.http import etag_response
from vane.schemas import Forecast, Snapshot
from vane.sources.base import SnapshotData

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

    key = f"src:snapshot:{cell.id}"
    # ponytail: no single-flight lock. When a popular cell's entry expires, every concurrent
    # request misses and calls Open-Meteo. Harmless at current traffic; add a Redis SETNX
    # lease around the fetch if the rate-limit metric starts moving.
    data = await get_model(redis, key, SnapshotData)
    if data is None:
        data = await source.snapshot(cell)
        await set_model(redis, key, data, SNAPSHOT_TTL_S)

    # Phase 1 has no normals and no backfill worker, so every cell is honestly cold. Phase 2
    # turns this into warming/warm and fills `context` and `normal`.
    body = Snapshot(
        cell_id=cell.id,
        observed_at=data.observed_at,
        current=data.current,
        arc=data.arc,
        normal=[],
        context=None,
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

    return etag_response(request, data, FORECAST_TTL_S)
