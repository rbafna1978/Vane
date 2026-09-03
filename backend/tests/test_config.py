"""Config normalisation. Cheap test, but it guards a deploy-time failure that reads as a
driver error rather than as a URL scheme problem.
"""

import pytest

from vane.config import Settings


@pytest.mark.parametrize(
    ("given", "expected"),
    [
        # What Railway, Heroku and most managed Postgres actually inject.
        ("postgresql://u:p@host:5432/db", "postgresql+asyncpg://u:p@host:5432/db"),
        ("postgres://u:p@host:5432/db", "postgresql+asyncpg://u:p@host:5432/db"),
        # Already correct, must be left alone.
        ("postgresql+asyncpg://u:p@host:5432/db", "postgresql+asyncpg://u:p@host:5432/db"),
    ],
)
def test_database_url_always_uses_the_async_driver(given, expected):
    assert Settings(database_url=given).database_url == expected


def test_password_with_special_characters_survives():
    url = "postgres://u:p%40ss%2Fword@host:5432/db"
    assert Settings(database_url=url).database_url.endswith("p%40ss%2Fword@host:5432/db")
