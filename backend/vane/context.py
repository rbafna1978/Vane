"""The context engine. Everything else in this service exists to feed this file.

Every other weather app shows a number. This turns the number into a claim about the place:
is today unusual here, and in what direction. The claims must be exactly true — a superlative
drawn from a short record is a lie with a number in it, so short records make weaker claims
or none at all.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import date as Date
from datetime import timedelta

from sqlalchemy import Row, text
from sqlalchemy.ext.asyncio import AsyncSession

from vane import sentences as s
from vane.schemas import Context, NormalBand

# Below 0.2mm is instrument noise and dew, not a day it rained.
WET_DAY_MM = 0.2
# Under a decade of record, superlatives stop being interesting and start being artefacts of a
# short sample. Those cells get facts, not claims.
MIN_YEARS_FOR_CLAIMS = 10
# A dry spell only becomes worth the most prominent sentence on screen at this length.
DRY_SPELL_DAYS = 25
DRY_SPELL_DAYS_IF_RAIN_COMING = 14
STREAK_DAYS = 5
NEAR_RECORD_RANK = 5


@dataclass(frozen=True, slots=True)
class Facts:
    """Everything we know about how today compares. Assembled once, then ranked."""

    rank: int | None = None  # 1 = warmest on record for this calendar date
    rank_from_cold: int | None = None
    years: int = 0
    days_since_rain: int | None = None
    warm_streak: int = 0
    cool_streak: int = 0
    normal: NormalBand | None = None


async def gather(
    session: AsyncSession, cell_id: str, today: Date, today_tmax: float
) -> Facts:
    """`today_tmax` must be today's forecast high, not the current reading — see SnapshotData."""
    normal = await _normal(session, cell_id, today)
    rank, rank_cold, years = await _rank(session, cell_id, today, today_tmax)
    return Facts(
        rank=rank,
        rank_from_cold=rank_cold,
        years=years,
        days_since_rain=await _days_since_rain(session, cell_id, today),
        warm_streak=(streaks := await _streaks(session, cell_id, today))[0],
        cool_streak=streaks[1],
        normal=normal,
    )


async def _normal(session: AsyncSession, cell_id: str, today: Date) -> NormalBand | None:
    row = (
        await session.execute(
            text(
                "SELECT tmax_c, tmin_c, years FROM daily_normals "
                "WHERE cell_id = :c AND month = :m AND day = :d"
            ),
            {"c": cell_id, "m": today.month, "d": today.day},
        )
    ).one_or_none()
    if row is None:
        return None
    return NormalBand(tmax_c=round(row.tmax_c, 1), tmin_c=round(row.tmin_c, 1), years=row.years)


async def _rank(
    session: AsyncSession, cell_id: str, today: Date, today_tmax: float
) -> tuple[int | None, int | None, int]:
    """Rank today's high among every previous instance of this calendar date.

    Matched on (month, day) rather than day-of-year: after February 29th the day-of-year
    numbering shifts, so day 247 is September 3rd in some years and September 4th in others,
    and the comparison would quietly be against the wrong date.
    """
    rows = (
        await session.execute(
            text(
                "SELECT tmax_c FROM observations "
                "WHERE cell_id = :c AND EXTRACT(MONTH FROM date) = :m "
                "AND EXTRACT(DAY FROM date) = :d AND date < :today AND tmax_c IS NOT NULL"
            ),
            {"c": cell_id, "m": today.month, "d": today.day, "today": today},
        )
    ).all()
    values = [r.tmax_c for r in rows]
    if not values:
        return None, None, 0

    # Ties count against the claim in both directions: if a past year matched today exactly,
    # today is not uniquely the warmest and must not say it is.
    warmer_or_equal = sum(1 for v in values if v >= today_tmax)
    cooler_or_equal = sum(1 for v in values if v <= today_tmax)
    return warmer_or_equal + 1, cooler_or_equal + 1, len(values)


async def _days_since_rain(session: AsyncSession, cell_id: str, today: Date) -> int | None:
    last = (
        await session.execute(
            text(
                "SELECT max(date) AS d FROM observations "
                "WHERE cell_id = :c AND precip_mm >= :wet AND date <= :today"
            ),
            {"c": cell_id, "wet": WET_DAY_MM, "today": today},
        )
    ).scalar_one_or_none()
    return None if last is None else (today - last).days


async def _streaks(session: AsyncSession, cell_id: str, today: Date) -> tuple[int, int]:
    """Consecutive days, ending at the most recent record, on one side of normal.

    Compared against each day's own normal rather than a fixed threshold, so the sentence
    means the same thing in Reykjavik and Phoenix.
    """
    rows: list[Row[tuple[Date, float, float]]] = list(
        (
            await session.execute(
                text(
                    "SELECT o.date, o.tmax_c, n.tmax_c AS normal_tmax "
                    "FROM observations o "
                    "JOIN daily_normals n ON n.cell_id = o.cell_id "
                    "  AND n.month = EXTRACT(MONTH FROM o.date) "
                    "  AND n.day = EXTRACT(DAY FROM o.date) "
                    "WHERE o.cell_id = :c AND o.date <= :today AND o.tmax_c IS NOT NULL "
                    "ORDER BY o.date DESC LIMIT 400"
                ),
                {"c": cell_id, "today": today},
            )
        ).all()
    )
    warm = cool = 0
    expected = None
    for row in rows:
        # A gap in the record ends the streak. Reanalysis has holes, and counting across one
        # would turn "8 straight days" into a claim about days we have no record of.
        if expected is not None and row.date != expected:
            break
        expected = row.date - timedelta(days=1)

        if row.tmax_c > row.normal_tmax:
            if cool:
                break
            warm += 1
        elif row.tmax_c < row.normal_tmax:
            if warm:
                break
            cool += 1
        else:
            break
    return warm, cool


def choose(facts: Facts, today: Date, rain_today: bool) -> Context | None:
    """Pick the single most interesting true thing, or nothing.

    Returning None is a feature. "72 degrees and sunny" restated as a fact is the filler this
    app exists to avoid, and an empty context line is quieter and better than a boring one.
    """
    confidence = "high" if facts.years >= MIN_YEARS_FOR_CLAIMS else "low"
    base = {"years": facts.years}

    days = facts.days_since_rain
    # A long dry spell about to break is the most useful thing we can say, so it outranks a
    # record: it changes what someone does today.
    if rain_today and days is not None and days >= DRY_SPELL_DAYS_IF_RAIN_COMING:
        return Context(
            headline=s.rain_ending_dry_spell(days),
            kind="since",
            facts={**base, "days_since_rain": days},
            confidence=confidence,
        )

    if facts.years >= MIN_YEARS_FOR_CLAIMS and facts.rank is not None:
        rank, cold_rank, years = facts.rank, facts.rank_from_cold, facts.years
        if rank == 1:
            return Context(
                headline=s.warmest(today, years), kind="percentile",
                facts={**base, "rank": rank}, confidence=confidence,
            )
        if cold_rank == 1:
            return Context(
                headline=s.coolest(today, years), kind="percentile",
                facts={**base, "rank_from_cold": cold_rank}, confidence=confidence,
            )
        if rank < NEAR_RECORD_RANK:
            return Context(
                headline=s.nth_warmest(today, rank, years), kind="percentile",
                facts={**base, "rank": rank}, confidence=confidence,
            )
        if cold_rank is not None and cold_rank < NEAR_RECORD_RANK:
            return Context(
                headline=s.nth_coolest(today, cold_rank, years), kind="percentile",
                facts={**base, "rank_from_cold": cold_rank}, confidence=confidence,
            )

    if days is not None and days >= DRY_SPELL_DAYS:
        return Context(
            headline=s.dry_spell(days), kind="since",
            facts={**base, "days_since_rain": days}, confidence=confidence,
        )

    if facts.warm_streak >= STREAK_DAYS:
        return Context(
            headline=s.warm_streak(facts.warm_streak), kind="streak",
            facts={**base, "streak": facts.warm_streak}, confidence=confidence,
        )
    if facts.cool_streak >= STREAK_DAYS:
        return Context(
            headline=s.cool_streak(facts.cool_streak), kind="streak",
            facts={**base, "streak": facts.cool_streak}, confidence=confidence,
        )

    return None


async def normals_for(
    session: AsyncSession, cell_id: str, dates: list[Date]
) -> dict[Date, NormalBand]:
    """The 30-year normal for each of a set of calendar dates.

    One query for the whole forecast rather than one per day — ten round trips to answer a
    single screen is the shape of an N+1, and it would sit on the request path.
    """
    if not dates:
        return {}

    # Matched on a single packed key (month * 100 + day) rather than a pair. Two parallel
    # `unnest` calls make Postgres pick between overloads it cannot disambiguate from an
    # untyped parameter, and pairing them positionally is fragile besides.
    rows = (
        await session.execute(
            text(
                "SELECT month, day, tmax_c, tmin_c, years FROM daily_normals "
                "WHERE cell_id = :c AND (month * 100 + day) = ANY(CAST(:keys AS int[]))"
            ),
            {"c": cell_id, "keys": [d.month * 100 + d.day for d in dates]},
        )
    ).all()

    by_key = {
        (row.month, row.day): NormalBand(
            tmax_c=round(row.tmax_c, 1), tmin_c=round(row.tmin_c, 1), years=row.years
        )
        for row in rows
    }
    return {d: band for d in dates if (band := by_key.get((d.month, d.day))) is not None}
