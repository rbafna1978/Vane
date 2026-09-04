"""The on-demand backfill (ADR-0004).

The whole economic trick of this product: 30 years of daily record is fetched for a 0.25 degree
cell the first time a real person stands in it, and never again. We never backfill the planet.
"""

from __future__ import annotations

import logging
from datetime import date as Date
from datetime import timedelta
from typing import Any

import httpx
from sqlalchemy import delete, func, text, update
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.ext.asyncio import AsyncSession

from vane.cells import Cell, cell_for
from vane.config import settings
from vane.models import Cell as CellRow
from vane.models import DailyNormal, Observation
from vane.sources.base import DailyRecord, WeatherSource

log = logging.getLogger(__name__)

# Postgres binds at most 32,767 parameters per statement. At 6 columns a 30-year backfill is
# ~67,000, so the insert has to be chunked even though the fetch is a single request.
_COLUMNS = 6
CHUNK_ROWS = 32_000 // _COLUMNS


async def backfill_cell(session: AsyncSession, source: WeatherSource, cell: Cell) -> int:
    """Fetch and store the cell's record, then derive its normals. Returns rows written.

    Idempotent: re-running upserts the same rows and recomputes the same normals, so a retry
    after a partial failure is safe and needs no resume bookkeeping.
    """
    end = Date.today() - timedelta(days=1)
    start = end.replace(year=end.year - settings().backfill_years)

    await session.execute(
        update(CellRow).where(CellRow.id == cell.id).values(status="warming")
    )
    await session.commit()

    records = await source.archive(cell, start, end)
    written = await _store(session, cell, records)
    await _recompute_normals(session, cell)

    await session.execute(
        update(CellRow)
        .where(CellRow.id == cell.id)
        .values(status="warm", warmed_at=func.now())
    )
    await session.commit()
    log.info("backfilled %s: %d days from %s to %s", cell.id, written, start, end)
    return written


async def _store(session: AsyncSession, cell: Cell, records: list[DailyRecord]) -> int:
    rows = [
        {
            "cell_id": cell.id,
            "date": r.d,
            "tmax_c": r.tmax_c,
            "tmin_c": r.tmin_c,
            "tmean_c": r.tmean_c,
            "precip_mm": r.precip_mm,
        }
        for r in records
    ]
    if not rows:
        return 0

    for start in range(0, len(rows), CHUNK_ROWS):
        chunk = rows[start : start + CHUNK_ROWS]
        stmt = insert(Observation).values(chunk)
        # A re-run must overwrite, not conflict: reanalysis revises recent days, so the newer
        # fetch is the more correct one.
        await session.execute(
            stmt.on_conflict_do_update(
                index_elements=[Observation.cell_id, Observation.date],
                set_={
                    "tmax_c": stmt.excluded.tmax_c,
                    "tmin_c": stmt.excluded.tmin_c,
                    "tmean_c": stmt.excluded.tmean_c,
                    "precip_mm": stmt.excluded.precip_mm,
                },
            )
        )
    # One commit for the whole cell: a half-written record would let the context engine make
    # superlative claims against an incomplete history.
    await session.commit()
    return len(rows)


async def _recompute_normals(session: AsyncSession, cell: Cell) -> None:
    """Derive the average day from the record, keyed on (month, day).

    Done in SQL rather than in Python because it is one aggregate over 11k rows the database
    already holds; pulling them into the worker to average them would be a round trip for
    arithmetic Postgres does better.
    """
    await session.execute(delete(DailyNormal).where(DailyNormal.cell_id == cell.id))
    await session.execute(
        text(
            """
            INSERT INTO daily_normals (cell_id, month, day, tmax_c, tmin_c, precip_mm, years)
            SELECT cell_id,
                   EXTRACT(MONTH FROM date)::smallint,
                   EXTRACT(DAY   FROM date)::smallint,
                   AVG(tmax_c), AVG(tmin_c), AVG(COALESCE(precip_mm, 0)),
                   COUNT(DISTINCT EXTRACT(YEAR FROM date))
            FROM observations
            WHERE cell_id = :cell AND tmax_c IS NOT NULL AND tmin_c IS NOT NULL
            GROUP BY cell_id, 2, 3
            """
        ),
        {"cell": cell.id},
    )
    await session.commit()


async def run_backfill(ctx: dict[str, Any], cell_id: str) -> int:
    """arq entrypoint. Takes cell_id rather than a Cell so the job payload stays plain JSON."""
    from vane.db import sessionmaker
    from vane.sources.openmeteo import OpenMeteoSource

    lat, lon = (float(x) for x in cell_id.split(","))
    cell = cell_for(lat, lon)
    client: httpx.AsyncClient = ctx["http"]
    async with sessionmaker()() as session:
        try:
            return await backfill_cell(session, OpenMeteoSource(client), cell)
        except Exception:
            # Reset to cold so the next request for this cell enqueues a fresh attempt.
            # Leaving it at "warming" after arq exhausts its retries would strand the cell
            # permanently contextless, and silently — the exact failure ADR-0004 exists to
            # prevent.
            await session.rollback()
            await session.execute(
                update(CellRow).where(CellRow.id == cell.id).values(status="cold")
            )
            await session.commit()
            log.exception("backfill failed for %s; reset to cold for retry", cell.id)
            raise
