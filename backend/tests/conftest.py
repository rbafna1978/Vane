import json
import os
import pathlib
from collections.abc import AsyncIterator

# Point every import at the test database before vane.config caches its settings.
os.environ["DATABASE_URL"] = "postgresql+asyncpg://vane:vane@localhost:5432/vane_test"
os.environ["REDIS_URL"] = "redis://localhost:6379/15"

import pytest  # noqa: E402
from httpx import ASGITransport, AsyncClient  # noqa: E402
from sqlalchemy.ext.asyncio import create_async_engine  # noqa: E402

from vane import db  # noqa: E402
from vane.cells import Cell  # noqa: E402
from vane.deps import get_source  # noqa: E402
from vane.main import create_app  # noqa: E402
from vane.models import Base  # noqa: E402
from vane.schemas import Forecast  # noqa: E402
from vane.sources.base import SnapshotData, SourceError  # noqa: E402

FIXTURES = pathlib.Path(__file__).parent / "fixtures"


def openmeteo_payload() -> dict:
    return json.loads((FIXTURES / "openmeteo.json").read_text())


class FakeSource:
    """A WeatherSource that answers from the recorded fixture and counts calls.

    The call count is the point: it is how the cache tests prove a second request did not
    reach the provider, which is the behaviour that keeps us inside Open-Meteo's limits.
    """

    def __init__(self, snapshot: SnapshotData, forecast: Forecast) -> None:
        self._snapshot = snapshot
        self._forecast = forecast
        self.calls = 0
        self.raises: SourceError | None = None

    async def snapshot(self, cell: Cell) -> SnapshotData:
        self.calls += 1
        if self.raises:
            raise self.raises
        return self._snapshot

    async def forecast(self, cell: Cell, days: int) -> Forecast:
        self.calls += 1
        if self.raises:
            raise self.raises
        return self._forecast


@pytest.fixture
async def _database() -> AsyncIterator[None]:
    """Rebuild the schema per test, on the test's own event loop.

    Every engine here is created and disposed inside one test, because an asyncpg connection
    pool is bound to the loop that made it — a session-scoped engine leaks into the next
    test's loop and fails on teardown with a Future attached to a different loop.
    """
    admin = create_async_engine(
        "postgresql+asyncpg://vane:vane@localhost:5432/postgres", isolation_level="AUTOCOMMIT"
    )
    async with admin.connect() as conn:
        await conn.exec_driver_sql(
            "SELECT pg_terminate_backend(pid) FROM pg_stat_activity "
            "WHERE datname = 'vane_test' AND pid <> pg_backend_pid()"
        )
        await conn.exec_driver_sql("DROP DATABASE IF EXISTS vane_test")
        await conn.exec_driver_sql("CREATE DATABASE vane_test")
    await admin.dispose()

    async with db.engine().begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    yield
    await db.dispose()


@pytest.fixture
async def source() -> FakeSource:
    from vane.sources.openmeteo import OpenMeteoSource

    payload = openmeteo_payload()

    class _Stub:
        async def get(self, url, params=None):  # noqa: ANN001, ANN201
            import httpx

            return httpx.Response(200, json=payload, request=httpx.Request("GET", url))

    real = OpenMeteoSource(_Stub())  # type: ignore[arg-type]
    cell = Cell(lat=37.75, lon=-122.25)
    return FakeSource(await real.snapshot(cell), await real.forecast(cell, 2))


@pytest.fixture
async def client(_database: None, source: FakeSource) -> AsyncIterator[AsyncClient]:
    app = create_app()
    app.dependency_overrides[get_source] = lambda: source
    async with AsyncClient(
        transport=ASGITransport(app=app), base_url="http://test"
    ) as ac, app.router.lifespan_context(app):
        await app.state.redis.flushdb()
        yield ac
