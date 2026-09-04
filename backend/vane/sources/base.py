"""Provider protocols (ADR-0003).

Two narrow protocols rather than one wide one: Open-Meteo serves conditions and forecast,
NWS serves alerts and nothing else. Forcing both into one interface would produce two classes
that each no-op on half their surface.

`archive()` arrived in phase 2 alongside the backfill job that calls it.
"""

from datetime import date as Date
from datetime import datetime
from typing import Protocol

from pydantic import BaseModel

from vane.cells import Cell
from vane.schemas import ArcPoint, Current, Forecast, Sun


class SourceError(RuntimeError):
    """The upstream source failed. Carries a stable code the route maps to client copy."""

    def __init__(self, code: str, message: str, retry_after: int | None = None) -> None:
        super().__init__(message)
        self.code = code
        self.message = message
        self.retry_after = retry_after


class SnapshotData(BaseModel):
    """What a source can answer about right now. Context and normals are ours, not theirs."""

    observed_at: datetime
    current: Current
    arc: list[ArcPoint]
    sun: Sun
    # Today's forecast high and low, not the reading right now. The context engine ranks
    # today against 30 years of daily maxima, so it must compare a max to maxes — using the
    # current temperature would report "coolest ever" every morning before the day warmed up.
    today_tmax_c: float
    today_tmin_c: float


class DailyRecord(BaseModel):
    """One day of recorded history. Values are nullable because reanalysis has gaps, and a
    gap must stay a gap — filling it with a neighbour would fabricate the record we make
    superlative claims against."""

    d: Date
    tmax_c: float | None
    tmin_c: float | None
    tmean_c: float | None
    precip_mm: float | None


class WeatherSource(Protocol):
    async def snapshot(self, cell: Cell) -> SnapshotData: ...
    async def forecast(self, cell: Cell, days: int) -> Forecast: ...
    async def archive(self, cell: Cell, start: Date, end: Date) -> list[DailyRecord]: ...
