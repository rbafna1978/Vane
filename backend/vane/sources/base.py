"""Provider protocols (ADR-0003).

Two narrow protocols rather than one wide one: Open-Meteo serves conditions and forecast,
NWS serves alerts and nothing else. Forcing both into one interface would produce two classes
that each no-op on half their surface.

`WeatherSource.archive()` is deliberately absent until phase 2 adds the backfill that calls it.
"""

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


class WeatherSource(Protocol):
    async def snapshot(self, cell: Cell) -> SnapshotData: ...
    async def forecast(self, cell: Cell, days: int) -> Forecast: ...
