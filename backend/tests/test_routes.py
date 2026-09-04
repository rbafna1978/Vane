"""HTTP contract. Uses the real Postgres from docker-compose and a FakeSource — no network."""

from sqlalchemy import select

from vane.db import sessionmaker
from vane.models import Cell as CellRow
from vane.sources.base import SourceError

OAKLAND = {"lat": 37.8044, "lon": -122.2712}


async def test_snapshot_returns_the_contract(client):
    r = await client.get("/v1/snapshot", params=OAKLAND)
    assert r.status_code == 200
    body = r.json()
    assert body["cell_id"] == "37.75,-122.25"
    assert body["current"]["temp_c"] == 21.9
    assert len(body["arc"]) == 48
    assert body["sun"]["sunrise"].startswith("2026-09-03T06:41")
    # A first request for this cell queues its backfill and returns immediately with no
    # context line, rather than making someone wait ~4s holding a phone (ADR-0004).
    assert body["context"] is None
    assert body["context_state"] == "warming"
    assert body["normal"] is None


async def test_second_request_does_not_reach_the_provider(client, source):
    await client.get("/v1/snapshot", params=OAKLAND)
    assert source.calls == 1
    await client.get("/v1/snapshot", params=OAKLAND)
    assert source.calls == 1


async def test_nearby_coordinates_share_the_cached_entry(client, source):
    await client.get("/v1/snapshot", params=OAKLAND)
    await client.get("/v1/snapshot", params={"lat": 37.70, "lon": -122.19})
    assert source.calls == 1


async def test_etag_revalidation_returns_304_with_no_body(client):
    first = await client.get("/v1/snapshot", params=OAKLAND)
    etag = first.headers["etag"]
    again = await client.get(
        "/v1/snapshot", params=OAKLAND, headers={"If-None-Match": etag}
    )
    assert again.status_code == 304
    assert again.content == b""


async def test_stale_etag_returns_a_full_body(client):
    r = await client.get("/v1/snapshot", params=OAKLAND, headers={"If-None-Match": '"stale"'})
    assert r.status_code == 200
    assert r.json()["cell_id"] == "37.75,-122.25"


async def test_requesting_a_cell_records_it_as_demand(client):
    await client.get("/v1/snapshot", params=OAKLAND)
    async with sessionmaker()() as session:
        row = (await session.execute(
            select(CellRow).where(CellRow.id == "37.75,-122.25")
        )).scalar_one()
    assert row.status == "cold"
    assert row.lat == 37.75


async def test_repeat_requests_do_not_duplicate_the_cell_row(client):
    # The upsert exists so two devices in one cell cannot race into a duplicate-key 500.
    for _ in range(3):
        await client.get("/v1/snapshot", params=OAKLAND)
    async with sessionmaker()() as session:
        rows = (await session.execute(select(CellRow))).scalars().all()
    assert len([r for r in rows if r.id == "37.75,-122.25"]) == 1


async def test_repeat_requests_advance_last_seen(client):
    await client.get("/v1/snapshot", params=OAKLAND)
    async with sessionmaker()() as session:
        first = (await session.execute(select(CellRow))).scalar_one().last_seen_at
    await client.get("/v1/snapshot", params={"lat": 37.70, "lon": -122.19})
    async with sessionmaker()() as session:
        second = (await session.execute(select(CellRow))).scalar_one().last_seen_at
    assert second >= first


async def test_forecast_returns_daily_and_hourly(client):
    r = await client.get("/v1/forecast", params={**OAKLAND, "days": 2})
    assert r.status_code == 200
    body = r.json()
    assert len(body["daily"]) == 2
    assert body["hourly"]


async def test_invalid_coordinates_use_the_error_envelope(client):
    for params in [{"lat": 91, "lon": 0}, {"lat": 0, "lon": 999}, {"lat": "abc", "lon": 0}]:
        r = await client.get("/v1/snapshot", params=params)
        assert r.status_code == 400
        assert r.json()["error"]["code"] == "invalid_request"
        assert "detail" not in r.json()


async def test_provider_failure_surfaces_a_code_not_a_stack_trace(client, source):
    source.raises = SourceError("source_timeout", "Open-Meteo timed out", retry_after=5)
    r = await client.get("/v1/snapshot", params=OAKLAND)
    assert r.status_code == 502
    assert r.json()["error"]["code"] == "source_timeout"
    assert r.headers["retry-after"] == "5"


async def test_rate_limit_maps_to_429(client, source):
    source.raises = SourceError("source_rate_limited", "limit", retry_after=60)
    r = await client.get("/v1/snapshot", params=OAKLAND)
    assert r.status_code == 429


async def test_healthz_reports_both_dependencies(client):
    r = await client.get("/healthz")
    assert r.status_code == 200
    assert r.json()["checks"] == {"postgres": "ok", "redis": "ok"}


async def test_redis_outage_degrades_to_the_provider(client, source, monkeypatch):
    """Redis is an optimisation, not a dependency. Losing it must cost speed, not uptime."""
    from redis.exceptions import ConnectionError as RedisConnectionError

    async def boom(*args, **kwargs):
        raise RedisConnectionError("redis is down")

    monkeypatch.setattr(client._transport.app.state.redis, "get", boom)
    monkeypatch.setattr(client._transport.app.state.redis, "set", boom)

    r = await client.get("/v1/snapshot", params=OAKLAND)
    assert r.status_code == 200
    assert r.json()["current"]["temp_c"] == 21.9
    assert source.calls == 1


async def test_a_cold_cell_queues_exactly_one_backfill(client, arq):
    """Two devices standing in the same cell must not queue two 30-year fetches. arq
    deduplicates on _job_id, so the id has to be derived from the cell."""
    await client.get("/v1/snapshot", params=OAKLAND)
    await client.get("/v1/snapshot", params={"lat": 37.70, "lon": -122.19})
    assert [j[1] for j in arq.jobs] == ["37.75,-122.25", "37.75,-122.25"]
    assert {j[2] for j in arq.jobs} == {"backfill:37.75,-122.25"}


async def test_context_route_returns_only_context(client):
    r = await client.get("/v1/context", params=OAKLAND)
    assert r.status_code == 200
    body = r.json()
    assert set(body) == {"cell_id", "context", "context_state", "normal"}
    assert "arc" not in body and "current" not in body
