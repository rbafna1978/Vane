"""Open-Meteo adapter.

No API key, ERA5 archive behind the same account-free model, and generous limits — which is why
it is primary. Everything provider-shaped stops at this file: callers see only `vane.schemas`.
"""

from __future__ import annotations

import contextlib
from datetime import date as Date
from datetime import datetime, timedelta, timezone
from typing import Any

import httpx

from vane.cells import Cell
from vane.config import settings
from vane.schemas import (
    ArcPoint,
    Current,
    Forecast,
    ForecastDay,
    ForecastHour,
    Sun,
)
from vane.sources.base import SnapshotData, SourceError

_CURRENT = (
    "temperature_2m,apparent_temperature,relative_humidity_2m,surface_pressure,"
    "wind_speed_10m,wind_direction_10m,weather_code"
)
_HOURLY = "temperature_2m,precipitation,precipitation_probability,weather_code"
_DAILY = "sunrise,sunset,temperature_2m_max,temperature_2m_min,precipitation_sum,weather_code"


def _at(offset_seconds: int) -> timezone:
    return timezone(timedelta(seconds=offset_seconds))


def _dt(raw: str, tz: timezone) -> datetime:
    """Open-Meteo returns naive local ISO strings when timezone=auto.

    Attaching the reported UTC offset here is what stops every downstream 'is this hour today?'
    question from being wrong for anyone not on UTC.
    """
    return datetime.fromisoformat(raw).replace(tzinfo=tz)


class OpenMeteoSource:
    def __init__(self, client: httpx.AsyncClient) -> None:
        self._client = client

    async def _get(self, params: dict[str, Any]) -> dict[str, Any]:
        try:
            response = await self._client.get(
                f"{settings().open_meteo_base}/forecast", params=params
            )
        except httpx.TimeoutException as exc:
            raise SourceError("source_timeout", "Open-Meteo timed out", retry_after=5) from exc
        except httpx.HTTPError as exc:
            raise SourceError("source_unreachable", str(exc), retry_after=15) from exc

        if response.status_code == 429:
            raise SourceError("source_rate_limited", "Open-Meteo rate limit", retry_after=60)
        if response.status_code >= 400:
            # Open-Meteo puts the useful part in `reason` and still speaks JSON on 4xx.
            reason = "upstream error"
            with contextlib.suppress(ValueError):
                reason = str(response.json().get("reason", reason))
            raise SourceError("source_rejected", reason)

        payload: dict[str, Any] = response.json()
        return payload

    async def snapshot(self, cell: Cell) -> SnapshotData:
        data = await self._get(
            {
                "latitude": cell.lat,
                "longitude": cell.lon,
                "current": _CURRENT,
                "hourly": _HOURLY,
                "daily": "sunrise,sunset",
                "timezone": "auto",
                "wind_speed_unit": "kn",
                "forecast_days": 1,
            }
        )
        tz = _at(int(data["utc_offset_seconds"]))
        cur = data["current"]
        hourly = data["hourly"]
        daily = data["daily"]

        arc = [
            ArcPoint(
                t=_dt(t, tz),
                temp_c=temp,
                precip_mm=precip or 0.0,
                code=int(code),
            )
            for t, temp, precip, code in zip(
                hourly["time"],
                hourly["temperature_2m"],
                hourly["precipitation"],
                hourly["weather_code"],
                strict=True,
            )
        ]

        return SnapshotData(
            observed_at=_dt(cur["time"], tz),
            current=Current(
                temp_c=cur["temperature_2m"],
                feels_c=cur["apparent_temperature"],
                wind_kt=cur["wind_speed_10m"],
                wind_deg=int(cur["wind_direction_10m"]),
                humidity=int(cur["relative_humidity_2m"]),
                pressure_hpa=cur["surface_pressure"],
                code=int(cur["weather_code"]),
            ),
            arc=arc,
            sun=Sun(sunrise=_dt(daily["sunrise"][0], tz), sunset=_dt(daily["sunset"][0], tz)),
        )

    async def forecast(self, cell: Cell, days: int) -> Forecast:
        data = await self._get(
            {
                "latitude": cell.lat,
                "longitude": cell.lon,
                "hourly": _HOURLY,
                "daily": _DAILY,
                "timezone": "auto",
                "wind_speed_unit": "kn",
                "forecast_days": days,
            }
        )
        tz = _at(int(data["utc_offset_seconds"]))
        hourly = data["hourly"]
        daily = data["daily"]

        return Forecast(
            cell_id=cell.id,
            hourly=[
                ForecastHour(
                    t=_dt(t, tz),
                    temp_c=temp,
                    precip_mm=precip or 0.0,
                    precip_probability=None if prob is None else int(prob),
                    code=int(code),
                )
                for t, temp, precip, prob, code in zip(
                    hourly["time"],
                    hourly["temperature_2m"],
                    hourly["precipitation"],
                    hourly["precipitation_probability"],
                    hourly["weather_code"],
                    strict=True,
                )
            ],
            daily=[
                ForecastDay(
                    d=Date.fromisoformat(d),
                    tmax_c=tmax,
                    tmin_c=tmin,
                    precip_mm=precip or 0.0,
                    code=int(code),
                    sunrise=_dt(sunrise, tz),
                    sunset=_dt(sunset, tz),
                )
                for d, tmax, tmin, precip, code, sunrise, sunset in zip(
                    daily["time"],
                    daily["temperature_2m_max"],
                    daily["temperature_2m_min"],
                    daily["precipitation_sum"],
                    daily["weather_code"],
                    daily["sunrise"],
                    daily["sunset"],
                    strict=True,
                )
            ],
        )
