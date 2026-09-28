import asyncio
import sys
import os
import secrets
from contextlib import asynccontextmanager
from pathlib import Path
from urllib.parse import urlparse
from datetime import date
from typing import Literal

from fastapi import FastAPI, HTTPException, Query, Request
from fastapi.responses import FileResponse, PlainTextResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from starlette.middleware.trustedhost import TrustedHostMiddleware

from .capture import native
from .platform_support import acquire_lock
from .config import Settings, data_dir
from .engine import Engine
from .native_bridge import NativeBridge
from .recall import Recall
from .review import review
from pydantic import BaseModel, Field

class RecallQuestion(BaseModel):
    question: str = Field(min_length=1, max_length=500)
    day: str = ""
    app_id: str = ""
    topic: str = ""


def create_app(root: Path | None = None, run_capture: bool = True):
    root = root or data_dir()
    native_token = os.environ.get("CONSTANT_WATCH_NATIVE_TOKEN")
    bridge = NativeBridge() if native_token else None
    engine = Engine(root, capture_native=bridge.call if bridge else None)

    @asynccontextmanager
    async def lifespan(app):
        lock = acquire_lock(root / "daemon.lock")
        try:
            if run_capture:
                await engine.start()
            yield
        finally:
            await engine.stop()
            if bridge:
                bridge.close()
            lock.close()

    app = FastAPI(title="Constant Watch", lifespan=lifespan, docs_url=None, redoc_url=None)
    app.state.engine = engine
    app.state.native_bridge = bridge
    app.add_middleware(TrustedHostMiddleware, allowed_hosts=["localhost", "127.0.0.1", "testserver"])

    @app.middleware("http")
    async def local_only(request: Request, call_next):
        origin = request.headers.get("origin")
        if origin:
            parsed = urlparse(origin)
            if parsed.scheme != "http" or parsed.netloc != request.headers.get("host"):
                return JSONResponse({"detail": "Cross-origin access is disabled"}, status_code=403)
        if request.headers.get("sec-fetch-site") == "cross-site":
            return JSONResponse({"detail": "Cross-site access is disabled"}, status_code=403)
        if request.method not in ("GET", "HEAD", "OPTIONS") and request.headers.get("x-constant-watch") != "local":
            return JSONResponse({"detail": "Local control header required"}, status_code=403)
        response = await call_next(request)
        response.headers["Cache-Control"] = "no-store"
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["Content-Security-Policy"] = "default-src 'self'; style-src 'self'; script-src 'self'; img-src 'self' data:; frame-ancestors 'none'; base-uri 'none'; form-action 'self'"
        return response

    def verify_native(request):
        if not bridge or not secrets.compare_digest(request.headers.get("x-constant-watch-native", ""), native_token):
            raise HTTPException(403, "Native app connection required")

    @app.get("/api/native/next")
    async def native_next(request: Request):
        verify_native(request)
        return await bridge.next()

    @app.post("/api/native/result/{job_id}")
    async def native_result(job_id: str, value: dict, request: Request):
        verify_native(request)
        if not bridge.complete(job_id, value):
            raise HTTPException(410, "Native request has expired")
        return {"accepted": True}

    @app.get("/api/health")
    async def health():
        return {"application": "constant-watch", "version": "0.1.0"}

    @app.post("/api/open-ollama")
    async def open_ollama():
        import webbrowser
        webbrowser.open("https://ollama.com/download/windows" if sys.platform == "win32" else "https://ollama.com/download/mac")
        return {"opened": True}

    @app.get("/api/status")
    async def status():
        try:
            permissions = await (bridge.call if bridge else native)("status")
        except Exception as exc:
            permissions = {"accessibility": False, "screen_recording": False, "error": str(exc)}
        return {**engine.state, "settings": engine.settings.model_dump(), "permissions": permissions,
                "model": await engine.model.status(engine.settings.model), "pending_summaries": len(engine.store.pending()),
                "data_directory": str(root), "platform": sys.platform,
                "mcp_config": {"mcpServers": {"constant-watch": {"command": sys.executable,
                    "args": ["mcp"] if getattr(sys, "frozen", False) else ["-m", "constant_watch.cli", "mcp"],
                    "env": {"CONSTANT_WATCH_DATA": str(root)}}}}}

    @app.post("/api/permissions")
    async def permissions(kind: Literal["all", "accessibility", "screen"] = "all"):
        try:
            return await (bridge.call if bridge else native)("permissions" if kind == "all" else f"request-{kind}")
        except Exception as exc:
            raise HTTPException(503, str(exc)) from exc

    @app.post("/api/model/setup")
    async def setup_model():
        engine.setup_model()
        return {"started": True}

    @app.put("/api/settings")
    async def settings(value: Settings):
        engine.configure(value)
        return value.model_dump()

    @app.get("/api/apps")
    async def apps():
        return engine.store.apps()

    @app.get("/api/observations")
    async def observations(app_id: str = "", day: str = "", q: str = Query("", max_length=500), limit: int = Query(50, ge=1, le=200), before: int | None = None):
        return engine.store.list(app_id, day, q, limit, before)

    @app.get("/api/markdown")
    async def markdown(day: date, app_id: str = ""):
        day = day.isoformat()
        content = engine.store.markdown(app_id, day) if app_id else engine.store.day_markdown(day)
        if not content:
            raise HTTPException(404, "No notes for this application and date")
        return PlainTextResponse(content, headers={"Content-Disposition": 'attachment; filename="screen-notes.md"'})

    @app.get("/api/day-flow")
    async def day_flow(day: date, offset: int = Query(0, ge=0), limit: int = Query(50, ge=1, le=200)):
        return engine.store.daily_flow(day.isoformat(), offset, limit)

    recall = Recall(engine.store)

    @app.get("/api/review")
    async def read_review(start: date, end: date):
        try:
            return review(engine.store, start.isoformat(), end.isoformat())
        except ValueError as exc:
            raise HTTPException(422, str(exc)) from exc

    @app.post("/api/ask")
    async def ask(value: RecallQuestion):
        try:
            return recall.ask(value.question, value.day, value.app_id, value.topic)
        except ValueError as exc:
            raise HTTPException(422, str(exc)) from exc

    @app.get("/api/topics")
    async def topics(day: date | None = None):
        return recall.topics(day.isoformat() if day else '')

    @app.get("/api/topics/{key}")
    async def topic(key: str, day: date | None = None, offset: int = Query(0, ge=0), limit: int = Query(50, ge=1, le=100)):
        return recall.topic(key, day.isoformat() if day else '', offset, limit)

    @app.get("/api/evidence/{row_id}")
    async def observation(row_id: int):
        value = recall.observation(row_id)
        if value is None:
            raise HTTPException(404, "This capture is unavailable or has expired under retention settings.")
        return value

    static = Path(__file__).parent / "static"
    app.mount("/static", StaticFiles(directory=static), name="static")

    @app.get("/")
    async def index():
        return FileResponse(static / "landing.html")

    @app.get("/journal")
    async def journal():
        return FileResponse(static / "index.html")

    return app
