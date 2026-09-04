from datetime import date as Date
from datetime import datetime

from sqlalchemy import Date as SADate
from sqlalchemy import (
    DateTime,
    Float,
    ForeignKey,
    Index,
    Integer,
    SmallInteger,
    String,
    func,
    text,
)
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


class Observation(Base):
    """One day of recorded weather for one cell.

    ~11,200 rows per cell for a 30-year backfill. Deliberately unpartitioned (ADR-0001): every
    query here filters on cell_id first, so partitioning by date would pay the cost and get
    none of the pruning.
    """

    __tablename__ = "observations"
    __table_args__ = (
        # "Last time it rained here" walks backwards from today looking for the first wet day.
        # Without this it scans every dry day in 30 years to find one row.
        Index(
            "ix_observations_wet_days",
            "cell_id",
            "date",
            postgresql_using="btree",
            postgresql_where=text("precip_mm >= 0.2"),
        ),
    )

    cell_id: Mapped[str] = mapped_column(
        String(20), ForeignKey("cells.id", ondelete="CASCADE"), primary_key=True
    )
    date: Mapped[Date] = mapped_column(SADate, primary_key=True)
    tmax_c: Mapped[float | None] = mapped_column(Float, nullable=True)
    tmin_c: Mapped[float | None] = mapped_column(Float, nullable=True)
    tmean_c: Mapped[float | None] = mapped_column(Float, nullable=True)
    precip_mm: Mapped[float | None] = mapped_column(Float, nullable=True)


class DailyNormal(Base):
    """The average day. Keyed on (month, day) rather than day-of-year on purpose.

    Day-of-year shifts by one after February 29th in leap years, so day 60 means March 1st in
    some years and February 29th in others — which would quietly average two different dates
    together. (month, day) has no such ambiguity.
    """

    __tablename__ = "daily_normals"

    cell_id: Mapped[str] = mapped_column(
        String(20), ForeignKey("cells.id", ondelete="CASCADE"), primary_key=True
    )
    month: Mapped[int] = mapped_column(SmallInteger, primary_key=True)
    day: Mapped[int] = mapped_column(SmallInteger, primary_key=True)
    tmax_c: Mapped[float] = mapped_column(Float, nullable=False)
    tmin_c: Mapped[float] = mapped_column(Float, nullable=False)
    precip_mm: Mapped[float] = mapped_column(Float, nullable=False)
    # How many years actually contributed. Drives Context.confidence — a superlative drawn from
    # four years of record is a lie with a number in it.
    years: Mapped[int] = mapped_column(Integer, nullable=False)
