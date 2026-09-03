# Vane backend

FastAPI service behind the Vane iOS app. Fetching a forecast is not the product —
contextualising it against local history is — so this service exists to hold 30 years of
observations per grid cell and answer "is this unusual?".

Phase 1 ships the skeleton and the two read paths. The context engine is phase 2.

## Run it

Requires Docker.

```bash
cd backend
docker compose up --build
```

Migrations run on boot. Then:

```bash
curl "localhost:8000/v1/snapshot?lat=37.8044&lon=-122.2712"
curl "localhost:8000/v1/forecast?lat=37.8044&lon=-122.2712&days=7"
curl localhost:8000/healthz
```

## Develop

```bash
uv venv --python 3.12 && uv sync --all-groups
docker compose up -d postgres redis
cp .env.example .env
uv run alembic upgrade head
uv run uvicorn vane.main:app --reload
```

## Check

```bash
uv run pytest          # 46 tests, no network
uv run ruff check .
uv run mypy vane       # strict
```

Tests need the compose Postgres running; they build and drop a separate `vane_test`
database and use Redis db 15. No test touches the network — route tests inject a fake
provider, and the adapter tests replay a payload recorded from the real API into
`httpx.MockTransport`.

## Shape

```
vane/cells.py        lat/lon -> 0.25 degree cell. Everything downstream is keyed on this.
vane/sources/        provider adapters. Open-Meteo shapes stop here (ADR-0003).
vane/routes/         HTTP. One request per app open (/v1/snapshot).
vane/cells_repo.py   records which cells real users stand in — phase 2's backfill queue.
vane/cache.py        Redis, fails open: an outage costs speed, not uptime.
vane/http.py         ETag revalidation, which is what makes offline-first cheap.
vane/errors.py       one error envelope, {"error": {code, message, retry_after}}.
```

Decisions and their reasoning live in [../docs/adr](../docs/adr) and [../DECISIONS.md](../DECISIONS.md).

## Deploy (Railway)

```bash
brew install railway          # already installed
railway login                 # opens a browser
railway init                  # from backend/
```

Then add Postgres and Redis from the Railway dashboard and `railway up`. `railway.json`
builds the Dockerfile, runs `alembic upgrade head` on start, and health-checks `/healthz`.

Railway injects `DATABASE_URL` as `postgresql://`; `vane/config.py` rewrites it to
`postgresql+asyncpg://` on load, so no manual variable editing is needed.

Before launch: take a Railway backup and **restore it once** (ADR-0005). An untested backup
is not a backup.

## Not built yet

- **Context, normals, backfill.** `/v1/snapshot` returns `context: null` and
  `context_state: "cold"` for every cell, honestly, because no cell has history yet.
- **Rate limiting.** `/v1/snapshot` and `/v1/forecast` are unauthenticated, so anyone with
  the URL can spend our Open-Meteo quota. Fine while the URL is private; must be closed
  before the app is public.
- **Cache stampede protection.** See the `ponytail:` note in `routes/weather.py`.
- **Alerts.** `AlertSource` has no implementation; NWS lands with the US alert work.
