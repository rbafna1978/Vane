from __future__ import annotations

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse

from vane.schemas import ErrorBody, ErrorResponse
from vane.sources.base import SourceError


class ApiError(Exception):
    def __init__(self, code: str, message: str, status: int, retry_after: int | None = None):
        super().__init__(message)
        self.code = code
        self.message = message
        self.status = status
        self.retry_after = retry_after


def _body(code: str, message: str, retry_after: int | None) -> dict[str, object]:
    return ErrorResponse(
        error=ErrorBody(code=code, message=message, retry_after=retry_after)
    ).model_dump()


def install(app: FastAPI) -> None:
    """Every error leaves as {"error": {code, message, retry_after}}.

    `message` is for logs and for me. The client maps `code` to copy that went through
    design:ux-copy — a raw upstream string reaching someone who wants to know if it will rain
    is how apps end up saying "source_timeout" out loud.
    """

    @app.exception_handler(ApiError)
    async def _api(_: Request, exc: ApiError) -> JSONResponse:
        headers = {"Retry-After": str(exc.retry_after)} if exc.retry_after else None
        return JSONResponse(
            _body(exc.code, exc.message, exc.retry_after), status_code=exc.status, headers=headers
        )

    @app.exception_handler(RequestValidationError)
    async def _validation(_: Request, exc: RequestValidationError) -> JSONResponse:
        # FastAPI's default 422 body is {"detail": [...]}, which is a second error shape the
        # client would have to parse. One envelope or the client ends up with two code paths.
        first = exc.errors()[0] if exc.errors() else {}
        loc = ".".join(str(p) for p in first.get("loc", ())[1:]) or "request"
        return JSONResponse(
            _body("invalid_request", f"{loc}: {first.get('msg', 'invalid')}", None),
            status_code=400,
        )

    @app.exception_handler(SourceError)
    async def _source(_: Request, exc: SourceError) -> JSONResponse:
        status = 429 if exc.code == "source_rate_limited" else 502
        headers = {"Retry-After": str(exc.retry_after)} if exc.retry_after else None
        return JSONResponse(
            _body(exc.code, exc.message, exc.retry_after), status_code=status, headers=headers
        )
