"""The context engine, against seeded deterministic history. No network, no real weather.

Every claim this engine makes appears at 28pt as the second most prominent thing on screen,
so the tests here are about truthfulness, not just shape.
"""

from datetime import date, timedelta

import pytest
from sqlalchemy import text

from vane import context as ctx
from vane.db import sessionmaker

CELL = "37.75,-122.25"
TODAY = date(2026, 9, 4)


async def seed(observations: list[tuple[date, float, float]], normals_tmax: float = 25.0) -> None:
    """observations: (date, tmax_c, precip_mm). Normals are derived from what we insert."""
    async with sessionmaker()() as s:
        await s.execute(
            text("INSERT INTO cells (id, lat, lon, status) VALUES (:i, 37.75, -122.25, 'warm')"),
            {"i": CELL},
        )
        for d, tmax, precip in observations:
            await s.execute(
                text(
                    "INSERT INTO observations (cell_id, date, tmax_c, tmin_c, tmean_c, precip_mm)"
                    " VALUES (:c, :d, :tx, :tn, :tm, :p)"
                ),
                {"c": CELL, "d": d, "tx": tmax, "tn": tmax - 10, "tm": tmax - 5, "p": precip},
            )
        for month, day in {(d.month, d.day) for d, _, _ in observations}:
            await s.execute(
                text(
                    "INSERT INTO daily_normals (cell_id, month, day, tmax_c, tmin_c, precip_mm,"
                    " years) VALUES (:c, :m, :dy, :tx, :tn, 0, 30)"
                ),
                {"c": CELL, "m": month, "dy": day, "tx": normals_tmax, "tn": normals_tmax - 10},
            )
        await s.commit()


def past_sept_4s(highs: list[float]) -> list[tuple[date, float, float]]:
    return [(date(2026 - i - 1, 9, 4), h, 0.0) for i, h in enumerate(highs)]


async def test_todays_high_is_ranked_not_the_current_reading(_database):
    """Regression. Ranking the current temperature against 30 years of daily maxima reports
    'coolest ever' every morning before the day has warmed up — a false superlative on the
    most prominent line in the app."""
    await seed(past_sept_4s([20.7, 20.8, 21.4, 21.6] + [30.0] * 26))
    async with sessionmaker()() as s:
        # Today's high, 21.7, beats four of the record lows — not a record.
        high = await ctx.gather(s, CELL, TODAY, 21.7)
        # A mid-morning reading of 18.0 would look like a record if we ranked it.
        reading = await ctx.gather(s, CELL, TODAY, 18.0)
    assert high.rank_from_cold == 5
    assert reading.rank_from_cold == 1
    assert ctx.choose(high, TODAY, rain_today=False) != ctx.choose(reading, TODAY, False)


async def test_ties_do_not_earn_a_superlative(_database):
    """If a past year matched today exactly, today is not uniquely the warmest."""
    await seed(past_sept_4s([30.0] + [20.0] * 11))
    async with sessionmaker()() as s:
        facts = await ctx.gather(s, CELL, TODAY, 30.0)
    assert facts.rank == 2
    result = ctx.choose(facts, TODAY, rain_today=False)
    assert result is not None
    assert "Warmest" not in result.headline
    assert result.headline == "Second-warmest September 4th in 12 years."


async def test_a_genuine_record_says_so(_database):
    await seed(past_sept_4s([20.0] * 12))
    async with sessionmaker()() as s:
        facts = await ctx.gather(s, CELL, TODAY, 35.0)
    result = ctx.choose(facts, TODAY, rain_today=False)
    assert result is not None
    assert result.headline == "Warmest September 4th in 12 years."
    assert result.confidence == "high"


async def test_short_record_makes_no_superlative_claims(_database):
    """Four years of record cannot support 'warmest in four years' as a headline."""
    await seed(past_sept_4s([20.0] * 4))
    async with sessionmaker()() as s:
        facts = await ctx.gather(s, CELL, TODAY, 35.0)
    assert facts.rank == 1
    assert ctx.choose(facts, TODAY, rain_today=False) is None


async def test_streak_counts_consecutive_days_and_stops_at_the_break(_database):
    rows = [(TODAY - timedelta(days=i), 20.0, 0.0) for i in range(1, 9)]
    rows.append((TODAY - timedelta(days=9), 30.0, 0.0))  # the warm day that ends it
    rows += [(TODAY - timedelta(days=i), 20.0, 0.0) for i in range(10, 15)]
    await seed(rows, normals_tmax=25.0)
    async with sessionmaker()() as s:
        facts = await ctx.gather(s, CELL, TODAY, 20.0)
    assert facts.cool_streak == 8
    assert facts.warm_streak == 0
    result = ctx.choose(facts, TODAY, rain_today=False)
    assert result is not None
    assert result.headline == "8 straight days cooler than normal."


async def test_days_since_rain_ignores_trace_amounts(_database):
    rows = [(TODAY - timedelta(days=i), 25.0, 0.0) for i in range(1, 40)]
    rows[4] = (TODAY - timedelta(days=5), 25.0, 0.1)   # dew, not rain
    rows[29] = (TODAY - timedelta(days=30), 25.0, 4.0)  # actual rain
    await seed(rows)
    async with sessionmaker()() as s:
        facts = await ctx.gather(s, CELL, TODAY, 25.0)
    assert facts.days_since_rain == 30


async def test_rain_arriving_outranks_everything(_database):
    """A dry spell about to break changes what someone does today; a record does not."""
    rows = [(TODAY - timedelta(days=i), 25.0, 0.0) for i in range(1, 30)]
    rows[19] = (TODAY - timedelta(days=20), 25.0, 6.0)  # last rain, 20 days ago
    rows += past_sept_4s([10.0] * 12)
    await seed(rows)
    async with sessionmaker()() as s:
        facts = await ctx.gather(s, CELL, TODAY, 40.0)
    assert facts.rank == 1  # it is also a record
    result = ctx.choose(facts, TODAY, rain_today=True)
    assert result is not None
    assert result.kind == "since"
    assert result.headline.startswith("Rain today.")


async def test_an_ordinary_day_says_nothing(_database):
    """Returning None is the feature. Filler is what this app exists to avoid."""
    rows = [(TODAY - timedelta(days=i), 25.0, 3.0) for i in range(1, 20)]
    rows += past_sept_4s([20.0, 22.0, 24.0, 26.0, 28.0, 30.0] * 2)
    await seed(rows)
    async with sessionmaker()() as s:
        facts = await ctx.gather(s, CELL, TODAY, 25.0)
    assert ctx.choose(facts, TODAY, rain_today=False) is None


@pytest.mark.parametrize("high", [-40.0, 55.0])
async def test_extremes_do_not_crash_the_ranker(_database, high):
    await seed(past_sept_4s([20.0] * 12))
    async with sessionmaker()() as s:
        facts = await ctx.gather(s, CELL, TODAY, high)
    assert ctx.choose(facts, TODAY, rain_today=False) is not None


async def test_a_gap_in_the_record_ends_the_streak(_database):
    """Reanalysis has holes. Counting across one would claim consecutive days we never saw."""
    rows = [(TODAY - timedelta(days=i), 20.0, 0.0) for i in range(1, 4)]
    # days 4 and 5 are missing entirely
    rows += [(TODAY - timedelta(days=i), 20.0, 0.0) for i in range(6, 15)]
    await seed(rows, normals_tmax=25.0)
    async with sessionmaker()() as s:
        facts = await ctx.gather(s, CELL, TODAY, 20.0)
    assert facts.cool_streak == 3
