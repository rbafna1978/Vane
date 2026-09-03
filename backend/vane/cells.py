"""0.25 degree grid cells.

Every cached row, every backfill job, and every context computation is keyed on a cell rather
than on raw coordinates. Two users a kilometre apart share a cell and therefore share the
30-year backfill, which is the whole reason the on-demand trick is affordable (ADR-0004).
"""

from __future__ import annotations

import math
from dataclasses import dataclass

GRID = 0.25


class InvalidCoordinate(ValueError):
    """Raised for coordinates outside the range of the planet."""


@dataclass(frozen=True, slots=True)
class Cell:
    """A snapped grid cell. `id` is the canonical key used in Postgres and Redis."""

    lat: float
    lon: float

    @property
    def id(self) -> str:
        return f"{self.lat:.2f},{self.lon:.2f}"


def _snap(value: float) -> float:
    # floor(x + 0.5) rather than round(): Python's round() is banker's rounding, which sends
    # exact midpoints to the nearest even multiple and makes the grid subtly asymmetric.
    return math.floor(value / GRID + 0.5) * GRID


def cell_for(lat: float, lon: float) -> Cell:
    """Snap a coordinate to its grid cell.

    Trust boundary: `lat`/`lon` arrive from the client. NaN and infinity are rejected rather
    than allowed to poison a cache key or a database row.
    """
    if not math.isfinite(lat) or not math.isfinite(lon):
        raise InvalidCoordinate("lat and lon must be finite")
    if not -90.0 <= lat <= 90.0:
        raise InvalidCoordinate(f"lat {lat} outside [-90, 90]")
    if not -180.0 <= lon <= 180.0:
        raise InvalidCoordinate(f"lon {lon} outside [-180, 180]")

    snapped_lat = min(90.0, max(-90.0, _snap(lat)))
    snapped_lon = _snap(lon)
    # +180 and -180 are the same meridian; collapse to one cell so they cannot hold two
    # separate backfills of identical data.
    if snapped_lon >= 180.0:
        snapped_lon -= 360.0

    return Cell(lat=snapped_lat, lon=snapped_lon)
