from datetime import datetime

from sqlalchemy import DateTime, Float, String, func
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column


class Base(DeclarativeBase):
    pass


class Cell(Base):
    """One 0.25 degree grid cell that someone has asked about.

    A row appearing here is the demand signal: it means a real user stood in this cell and
    opened the app, which is what phase 2's backfill worker consumes to decide where to spend
    30 years of history fetching (ADR-0004). Cells nobody visits never get a row and never
    get backfilled.
    """

    __tablename__ = "cells"

    id: Mapped[str] = mapped_column(String(20), primary_key=True)
    lat: Mapped[float] = mapped_column(Float, nullable=False)
    lon: Mapped[float] = mapped_column(Float, nullable=False)
    # cold: no normals and nothing queued. warming: backfill enqueued. warm: normals present.
    status: Mapped[str] = mapped_column(String(10), nullable=False, default="cold")
    warmed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    first_seen_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
    last_seen_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
