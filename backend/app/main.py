"""FastAPI application entry point."""

from fastapi import FastAPI

from app import __version__
from app.api.health import router as health_router


def create_app() -> FastAPI:
    app = FastAPI(title="حرب العقول", version=__version__)
    app.include_router(health_router)
    return app


app = create_app()
