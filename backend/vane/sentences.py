"""Context headlines — the one sentence that is the entire reason this app exists.

Voice, decided with design:ux-copy: an instrument reports, it does not comment. No
exclamation, no second person, no adjectives that are not measurements. Numerals for counts
("47 days"), words for ordinals ("Third-warmest"), which is ordinary editorial practice and
keeps the data-face numerals reading as data.

Rendered server-side so the wording can be revised without an App Store release. The client
also receives the structured facts, so it can lay the sentence out rather than just print it.
"""

from __future__ import annotations

from datetime import date as Date

_ORDINALS = {2: "Second", 3: "Third", 4: "Fourth", 5: "Fifth"}


def ordinal_day(day: int) -> str:
    """1 -> '1st'. 11, 12, 13 are the exceptions that catch every naive implementation."""
    if 11 <= day % 100 <= 13:
        return f"{day}th"
    return f"{day}{ {1: 'st', 2: 'nd', 3: 'rd'}.get(day % 10, 'th') }"


def date_phrase(d: Date) -> str:
    return f"{d.strftime('%B')} {ordinal_day(d.day)}"


def warmest(d: Date, years: int) -> str:
    return f"Warmest {date_phrase(d)} in {years} years."


def coolest(d: Date, years: int) -> str:
    return f"Coolest {date_phrase(d)} in {years} years."


def nth_warmest(d: Date, rank: int, years: int) -> str:
    return f"{_ORDINALS[rank]}-warmest {date_phrase(d)} in {years} years."


def nth_coolest(d: Date, rank: int, years: int) -> str:
    return f"{_ORDINALS[rank]}-coolest {date_phrase(d)} in {years} years."


def dry_spell(days: int) -> str:
    return f"{days} days since it last rained here."


def rain_ending_dry_spell(days: int) -> str:
    return f"Rain today. {days} days since the last."


def warm_streak(days: int) -> str:
    return f"{days} straight days warmer than normal."


def cool_streak(days: int) -> str:
    return f"{days} straight days cooler than normal."
