"""The API contract. These models are the boundary — provider response shapes never escape
their adapter, and the iOS client is generated against exactly these fields.
"""

from datetime import date as Date
from datetime import datetime
from typing import Literal

from pydantic import BaseModel

ContextState = Literal["warm", "warming", "cold"]


class Current(BaseModel):
    temp_c: float
    feels_c: float
    # Drives the interface's colour state alongside sun position. Real measured cover rather
    # than inferred from the weather code: "partly cloudy" spans 25-75% and the palette needs
    # the number, not the bucket.
    cloud_cover: int
    wind_kt: float
    wind_deg: int
    humidity: int
    pressure_hpa: float
    code: int


class ArcPoint(BaseModel):
    """One hour of today. The trace on the barograph is drawn from these."""

    t: datetime
    temp_c: float
    precip_mm: float
    code: int


class NormalBand(BaseModel):
    """The dashed reference behind the trace: the average high and low for this calendar date.

    A band rather than an hourly curve. We hold daily history, so an hourly normal would have
    to be invented from a diurnal shape — and a fabricated curve behind a real trace is
    exactly the kind of quiet dishonesty this app is built against. Two dashed rules also read
    more like printed chart paper than a second wiggle does.
    """

    tmax_c: float
    tmin_c: float
    years: int


class Sun(BaseModel):
    sunrise: datetime
    sunset: datetime


class Context(BaseModel):
    headline: str
    kind: Literal["percentile", "streak", "since", "threshold", "seasonal_edge"]
    facts: dict[str, float | int | str]
    confidence: Literal["high", "low"]


class Snapshot(BaseModel):
    cell_id: str
    observed_at: datetime
    # The location's own UTC offset. Sent explicitly rather than left to the client to infer
    # from timestamps: sunrise must render in the time of the place being looked at, not the
    # time of the phone, and inferring an offset from a midnight boundary breaks on DST days.
    utc_offset_seconds: int
    current: Current
    arc: list[ArcPoint]
    normal: NormalBand | None = None
    context: Context | None = None
    context_state: ContextState = "cold"
    sun: Sun


class ContextResponse(BaseModel):
    """`/v1/context` on its own. Smaller than a Snapshot on purpose: the morning push worker
    wants the sentence, not the arc."""

    cell_id: str
    context: Context | None = None
    context_state: ContextState = "cold"
    normal: NormalBand | None = None


class ForecastHour(BaseModel):
    t: datetime
    temp_c: float
    precip_mm: float
    precip_probability: int | None = None
    code: int


class ForecastDay(BaseModel):
    d: Date
    tmax_c: float
    tmin_c: float
    precip_mm: float
    code: int
    sunrise: datetime
    sunset: datetime


class Forecast(BaseModel):
    cell_id: str
    hourly: list[ForecastHour]
    daily: list[ForecastDay]


class ErrorBody(BaseModel):
    code: str
    message: str
    retry_after: int | None = None


class ErrorResponse(BaseModel):
    error: ErrorBody
