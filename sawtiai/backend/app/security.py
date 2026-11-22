"""API-key authentication and a small per-client rate limiter.

The key is sent by the app as `Authorization: Bearer <key>` (or `X-API-Key`).
It lives only in the server's environment (a Hugging Face Space *secret*) and
in the phone's encrypted storage after the user types it - never in the APK
or in git.
"""

from __future__ import annotations

import hmac
import threading
import time
from collections import defaultdict, deque

from fastapi import Depends, HTTPException, Request, status

from .config import settings


class RateLimiter:
    def __init__(self) -> None:
        self._hits: dict[str, deque[float]] = defaultdict(deque)
        self._lock = threading.Lock()

    def check(self, client: str, limit: int, window: float = 60.0) -> bool:
        now = time.monotonic()
        with self._lock:
            q = self._hits[client]
            while q and now - q[0] > window:
                q.popleft()
            if len(q) >= limit:
                return False
            q.append(now)
            return True


limiter = RateLimiter()
_failed = RateLimiter()


def _client_id(request: Request) -> str:
    fwd = request.headers.get("x-forwarded-for", "")
    if fwd:
        return fwd.split(",")[0].strip()
    return request.client.host if request.client else "unknown"


def require_api_key(request: Request) -> None:
    client = _client_id(request)
    if not settings.api_key:
        raise HTTPException(status.HTTP_503_SERVICE_UNAVAILABLE,
                            detail={"code": "server_not_configured",
                                    "message": "الخادم غير مهيأ: لم يتم ضبط مفتاح الوصول SAWTI_API_KEY."})
    auth = request.headers.get("authorization", "")
    supplied = auth[7:].strip() if auth.lower().startswith("bearer ") else request.headers.get("x-api-key", "").strip()
    if not supplied or not hmac.compare_digest(supplied.encode(), settings.api_key.encode()):
        # Slow down key guessing: 10 failures per minute per client, then 429.
        if not _failed.check(client, 10):
            raise HTTPException(status.HTTP_429_TOO_MANY_REQUESTS,
                                detail={"code": "too_many_attempts", "message": "محاولات كثيرة. انتظر دقيقة."})
        raise HTTPException(status.HTTP_401_UNAUTHORIZED,
                            detail={"code": "unauthorized", "message": "مفتاح الوصول غير صحيح."},
                            headers={"WWW-Authenticate": "Bearer"})
    if not limiter.check(client, settings.rate_limit_per_minute):
        raise HTTPException(status.HTTP_429_TOO_MANY_REQUESTS,
                            detail={"code": "rate_limited", "message": "طلبات كثيرة جداً. حاول بعد قليل."})


Authorized = Depends(require_api_key)
