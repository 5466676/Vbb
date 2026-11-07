"""Liveness endpoint used by Docker and load balancers."""

import time

from fastapi import APIRouter

from app import __version__

router = APIRouter(tags=["health"])


@router.get("/health")
async def health() -> dict:
    """Cheap check the app calls before online screens (also gives the server clock)."""
    return {"status": "ok", "version": __version__, "server_time_ms": int(time.time() * 1000)}
