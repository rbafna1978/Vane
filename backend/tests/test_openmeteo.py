"""Adapter parsing, against a payload recorded from the real API. No network."""

from datetime import timedelta

import httpx
import pytest

from tests.conftest import openmeteo_payload
from vane.cells import Cell
from vane.sources.base import SourceError
from vane.sources.openmeteo import OpenMeteoSource

CELL = Cell(lat=37.75, lon=-122.25)


def _source(handler) -> OpenMeteoSource:
    return OpenMeteoSource(httpx.AsyncClient(transport=httpx.MockTransport(handler)))


def _ok(request):
    return httpx.Response(200, json=openmeteo_payload())


async def test_snapshot_attaches_the_local_utc_offset():
    # Open-Meteo returns naive local strings with timezone=auto. If the offset is not attached,
    # every "is this hour today?" question is wrong for anyone outside UTC.
    data = await _source(_ok).snapshot(CELL)
    assert data.observed_at.tzinfo is not None
    assert data.observed_at.utcoffset() == timedelta(seconds=-25200)
    assert data.sun.sunrise.utcoffset() == timedelta(seconds=-25200)


async def test_snapshot_maps_current_conditions():
    # Compared against the fixture's own values rather than a literal. Hardcoding the captured
    # temperature means every re-record of the payload breaks the suite for no reason, and the
    # thing under test is the mapping, not the weather in Oakland on one afternoon.
    expected = openmeteo_payload()["current"]
    data = await _source(_ok).snapshot(CELL)
    assert data.current.temp_c == expected["temperature_2m"]
    assert data.current.cloud_cover == expected["cloud_cover"]
    assert data.current.wind_kt > 0
    assert 0 <= data.current.humidity <= 100
    assert isinstance(data.current.code, int)


async def test_arc_is_ordered_and_hourly():
    data = await _source(_ok).snapshot(CELL)
    times = [p.t for p in data.arc]
    assert times == sorted(times)
    assert all(b - a == timedelta(hours=1) for a, b in zip(times, times[1:], strict=False))


async def test_null_precipitation_becomes_zero():
    payload = openmeteo_payload()
    payload["hourly"]["precipitation"][0] = None
    data = await _source(lambda r: httpx.Response(200, json=payload)).snapshot(CELL)
    assert data.arc[0].precip_mm == 0.0


async def test_ragged_arrays_raise_rather_than_silently_misalign():
    # zip(strict=True) matters here: a short array would otherwise truncate the arc and put
    # temperatures against the wrong hours with no error at all.
    payload = openmeteo_payload()
    payload["hourly"]["temperature_2m"] = payload["hourly"]["temperature_2m"][:5]
    with pytest.raises(ValueError):
        await _source(lambda r: httpx.Response(200, json=payload)).snapshot(CELL)


async def test_forecast_days_are_dates_with_sun_times():
    fc = await _source(_ok).forecast(CELL, 2)
    assert len(fc.daily) == 2
    assert fc.daily[0].tmin_c <= fc.daily[0].tmax_c
    assert fc.daily[0].sunrise < fc.daily[0].sunset
    assert fc.cell_id == "37.75,-122.25"


@pytest.mark.parametrize(
    ("status", "code"),
    [(429, "source_rate_limited"), (400, "source_rejected"), (500, "source_rejected")],
)
async def test_upstream_failures_carry_a_stable_code(status, code):
    def handler(request):
        return httpx.Response(status, json={"reason": "nope"})

    with pytest.raises(SourceError) as exc:
        await _source(handler).snapshot(CELL)
    assert exc.value.code == code


async def test_timeout_is_retryable():
    def handler(request):
        raise httpx.ReadTimeout("slow", request=request)

    with pytest.raises(SourceError) as exc:
        await _source(handler).snapshot(CELL)
    assert exc.value.code == "source_timeout"
    assert exc.value.retry_after is not None
