from __future__ import annotations

from sqlalchemy import func
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.ext.asyncio import AsyncSession

from vane.cells import Cell
from vane.models import Cell as CellRow
from vane.schemas import ContextState

# The column is a plain varchar, so an unexpected value is possible in principle (a bad
# migration, a hand-edited row). Anything unrecognised degrades to "cold", which the client
# already renders as "no context line yet" rather than as an error.
_STATES: dict[str, ContextState] = {"cold": "cold", "warming": "warming", "warm": "warm"}


async def touch(session: AsyncSession, cell: Cell) -> ContextState:
    """Record that someone asked about this cell, and return its warm/cold status.

    Upsert rather than select-then-insert: two devices in the same cell can hit this
    concurrently, and the race would otherwise produce a duplicate-key 500 on the request that
    loses. `ON CONFLICT` makes the loser update instead of fail.
    """
    stmt = (
        insert(CellRow)
        .values(id=cell.id, lat=cell.lat, lon=cell.lon, status="cold")
        .on_conflict_do_update(index_elements=[CellRow.id], set_={"last_seen_at": func.now()})
        .returning(CellRow.status)
    )
    status = (await session.execute(stmt)).scalar_one()
    await session.commit()
    return _STATES.get(status, "cold")
