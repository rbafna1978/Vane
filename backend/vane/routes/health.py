from fastapi import APIRouter, Request
from fastapi.responses import JSONResponse
from sqlalchemy import text

from vane.db import sessionmaker

router = APIRouter()


@router.get("/healthz")
async def healthz(request: Request) -> JSONResponse:
    """Liveness plus real dependency checks.

    A healthz that only proves the process is running will happily report green while every
    request 500s on a dead database, so this touches both dependencies.
    """
    checks: dict[str, str] = {}
    ok = True

    try:
        async with sessionmaker()() as session:
            await session.execute(text("SELECT 1"))
        checks["postgres"] = "ok"
    except Exception as exc:  # noqa: BLE001 - report, never crash the probe
        checks["postgres"] = f"error: {type(exc).__name__}"
        ok = False

    try:
        await request.app.state.redis.ping()
        checks["redis"] = "ok"
    except Exception as exc:  # noqa: BLE001
        checks["redis"] = f"error: {type(exc).__name__}"
        ok = False

    return JSONResponse({"status": "ok" if ok else "degraded", "checks": checks},
                        status_code=200 if ok else 503)
