"""ETag helpers.

This is what makes 'opens instantly with cached state and reconciles' cheap: the client renders
from its local store, then revalidates with the ETag it stored, and usually pays one small 304
instead of a full payload.
"""

from __future__ import annotations

import hashlib

from fastapi import Request, Response
from pydantic import BaseModel


def etag_response(request: Request, model: BaseModel, max_age_s: int) -> Response:
    body = model.model_dump_json().encode()
    etag = '"' + hashlib.sha256(body).hexdigest()[:32] + '"'
    headers = {"ETag": etag, "Cache-Control": f"private, max-age={max_age_s}"}

    if request.headers.get("if-none-match") == etag:
        return Response(status_code=304, headers=headers)
    return Response(content=body, media_type="application/json", headers=headers)
