from datetime import date

from vane import sentences as s


def test_ordinal_day_handles_the_teens():
    # 11th, 12th, 13th are the cases a naive `day % 10` implementation gets wrong.
    assert [s.ordinal_day(n) for n in (11, 12, 13)] == ["11th", "12th", "13th"]


def test_ordinal_day_handles_the_ones():
    assert [s.ordinal_day(n) for n in (1, 2, 3, 4)] == ["1st", "2nd", "3rd", "4th"]


def test_ordinal_day_handles_the_twenties():
    assert [s.ordinal_day(n) for n in (21, 22, 23, 30, 31)] == [
        "21st", "22nd", "23rd", "30th", "31st"
    ]


def test_headlines_read_as_written():
    d = date(2026, 9, 3)
    assert s.warmest(d, 30) == "Warmest September 3rd in 30 years."
    assert s.nth_warmest(d, 3, 30) == "Third-warmest September 3rd in 30 years."
    assert s.dry_spell(47) == "47 days since it last rained here."
    assert s.warm_streak(9) == "9 straight days warmer than normal."


def test_every_headline_is_one_sentence():
    # It renders at 28pt as the second most prominent thing on screen. Two sentences there
    # stops being a headline and starts being a paragraph.
    d = date(2026, 9, 3)
    for text in (
        s.warmest(d, 30), s.coolest(d, 30), s.nth_warmest(d, 2, 30),
        s.dry_spell(47), s.warm_streak(9), s.cool_streak(4),
    ):
        assert text.count(".") == 1
        assert text.endswith(".")
        assert text[0].isupper() or text[0].isdigit()
