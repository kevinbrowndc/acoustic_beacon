from contextlib import asynccontextmanager
from datetime import datetime, timezone
from typing import Annotated

from fastapi import Depends, FastAPI, HTTPException, Path, Request, Response
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import text
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session

from .config import Settings
from .dashboard import router as dashboard_router
from pathlib import Path as FilePath
from fastapi.staticfiles import StaticFiles
from fastapi.responses import RedirectResponse
from .database import make_engine
from .lookup import lookup_offers
from .schemas import BeaconOffersOut


def get_session(request: Request):
    with Session(request.app.state.engine) as session:
        if session.bind.dialect.name == "postgresql":
            session.execute(text("SET TRANSACTION READ ONLY"))
        yield session  # close rolls back; the public route never commits


def get_now():
    return datetime.now(timezone.utc)


def create_app(settings: Settings | None = None, engine=None):
    settings = settings or Settings()
    managed_engine = engine is None
    engine = engine if engine is not None else make_engine(settings.database_url.get_secret_value())

    @asynccontextmanager
    async def lifespan(_):
        yield
        if managed_engine:
            engine.dispose()

    app = FastAPI(title="Acoustic Beacon API", version="0.1.0", lifespan=lifespan,
        docs_url="/docs" if settings.environment != "production" else None,
        redoc_url=None)
    app.state.engine = engine
    app.state.settings = settings
    app.state.dashboard_sessions = {}
    app.include_router(dashboard_router)
    dashboard_dist = FilePath(__file__).resolve().parents[2] / "dashboard" / "dist"
    if dashboard_dist.is_dir():
        @app.get("/", include_in_schema=False)
        def dashboard_entry():
            return RedirectResponse("/merchant/")

        @app.get("/merchant", include_in_schema=False)
        def merchant_redirect():
            return RedirectResponse("/merchant/")
        app.mount("/merchant", StaticFiles(directory=dashboard_dist, html=True), name="merchant")
    if settings.cors_origins:
        app.add_middleware(CORSMiddleware, allow_origins=settings.cors_origins,
            allow_methods=["GET"], allow_headers=["Accept"], allow_credentials=False)

    @app.get("/health/live", include_in_schema=False)
    def liveness():
        return {"status": "ok"}

    @app.get("/health/ready", include_in_schema=False)
    def readiness(session: Annotated[Session, Depends(get_session)], response: Response):
        # Verifies the deployed migration, not just that PostgreSQL accepts TCP.
        revision = session.execute(text("SELECT version_num FROM alembic_version")).scalar_one_or_none()
        if revision != "0001":
            raise HTTPException(503, "Database migration pending", headers={"Cache-Control": "no-store"})
        session.execute(text("SELECT payload_id FROM beacons LIMIT 0"))
        response.headers["Cache-Control"] = "no-store"
        return {"status": "ready"}

    @app.exception_handler(SQLAlchemyError)
    async def database_unavailable(_, __):
        return JSONResponse(status_code=503, content={"detail": "Content temporarily unavailable"},
            headers={"Cache-Control": "no-store"})

    @app.get("/api/v1/beacons/{beacon_id}/offers", response_model=BeaconOffersOut)
    def beacon_offers(
        beacon_id: Annotated[str, Path(pattern=r"^(?:0[xX])?[0-9a-fA-F]{6}$", max_length=8)],
        response: Response,
        session: Annotated[Session, Depends(get_session)],
        now: Annotated[datetime, Depends(get_now)],
    ):
        result = lookup_offers(session, int(beacon_id, 16), now)
        if result is None:
            raise HTTPException(404, "Beacon unavailable", headers={"Cache-Control": "no-store"})
        response.headers["Cache-Control"] = "no-store"
        return result

    return app


app = create_app()
