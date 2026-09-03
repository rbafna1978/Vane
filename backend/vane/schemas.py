"""The API contract. These models are the boundary — provider response shapes never escape
their adapter, and the iOS client is generated against exactly these fields.
"""

from datetime import date as Date
from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field

ContextState = Literal["warm", "warming", "cold"]


class Current(BaseModel):
    temp_c: float
    feels_c: float
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


class NormalPoint(BaseModel):
    """The dashed line behind the trace. Empty until the cell is warm."""

    t: datetime
    temp_c: float


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
    current: Current
    arc: list[ArcPoint]
    normal: list[NormalPoint] = Field(default_factory=list)
    context: Context | None = None
    context_state: ContextState = "cold"
    sun: Sun


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
