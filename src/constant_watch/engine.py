import asyncio
from datetime import datetime
import logging

from .capture import native
from .config import load_settings, save_settings
from .model import LocalModel
from .privacy import merge_text, redact
from .context import safe_source
from .store import Store

log = logging.getLogger(__name__)


class Engine:
    def __init__(self, root, capture_native=None):
        self.root = root
        self.capture_native = capture_native
        self.settings = load_settings(root)
        self.store = Store(root)
        self.model = LocalModel()
        self.state = {"last_capture": None, "last_app": None, "error": None, "capture_status": "Starting", "warnings": []}
        self.tasks = []
        self.revision = 0
        self.wake = asyncio.Event()
        self.setup_task = None

    def setup_model(self):
        if self.setup_task and not self.setup_task.done():
            return
        async def download():
            self.state["download"] = {"running": True, "status": "Connecting to Ollama", "fraction": 0.0}
            def progress(value):
                self.state["download"] = {"running": True, "status": value.get("status", "Downloading"),
                    "fraction": value.get("completed", 0) / max(value.get("total", 1), 1)}
            try:
                await self.model.pull(self.settings.model, progress)
                self.state["download"] = {"running": False, "status": "Model ready", "fraction": 1.0}
            except asyncio.CancelledError:
                raise
            except Exception:
                self.state["download"] = {"running": False, "status": "Could not download. Open Ollama and try again.", "fraction": 0.0}
        self.setup_task = asyncio.create_task(download())
        self.tasks.append(self.setup_task)

    async def start(self):
        self.store.prune(self.settings.retention_days)
        self.store.rebuild_exports()
        self.tasks = [asyncio.create_task(self.capture_loop()), asyncio.create_task(self.summary_loop())]

    async def stop(self):
        for task in self.tasks:
            task.cancel()
        await asyncio.gather(*self.tasks, return_exceptions=True)

    def configure(self, settings):
        self.revision += 1
        self.settings = settings
        save_settings(self.root, settings)
        self.store.prune(settings.retention_days)
        self.wake.set()

    async def capture_once(self):
        if self.settings.paused:
            self.state["capture_status"] = "Paused"
            return
        revision = self.revision
        capture = await (self.capture_native or native)(excluded=self.settings.excluded_apps)
        if revision != self.revision or self.settings.paused:
            return  # A pause/exclusion changed while native capture was in flight.
        self.state["warnings"] = capture.get("warnings", [])
        if capture.get("skipped"):
            self.state["capture_status"] = capture["skipped"]
            return
        if "Constant Watch — Screen memory" in capture.get("window_title", ""):
            self.state["capture_status"] = "Viewing your journal"
            return
        for key in ("app_name", "window_title", "ax_text", "ocr_text"):
            capture[key] = redact(capture.get(key, ""))[:12000]
        capture["text"] = (capture["ax_text"] + "\n" + capture["ocr_text"]).strip()
        capture["source_url"] = safe_source(capture.get("source_url", ""))
        self.state["last_app"] = capture.get("app_name")
        if not capture["text"]:
            self.state["capture_status"] = ("Enable macOS permissions to start capture"
                if capture.get("accessibility") is False and capture.get("screen_recording") is False
                else "Waiting for readable screen text")
            return
        row_id = self.store.add(capture)
        self.state.update(error=None, capture_status="Watching" if row_id else "Screen unchanged")
        if row_id:
            self.state["last_capture"] = datetime.now().astimezone().isoformat()

    async def capture_loop(self):
        ticks = 0
        while True:
            try:
                await self.capture_once()
                ticks += 1
                if ticks % 360 == 0:
                    self.store.prune(self.settings.retention_days)
            except asyncio.CancelledError:
                raise
            except Exception as exc:
                self.state.update(error=str(exc)[:300], capture_status="Capture needs attention")
                log.warning("Capture failed: %s", type(exc).__name__)
            try:
                await asyncio.wait_for(self.wake.wait(), self.settings.interval_seconds)
            except TimeoutError:
                pass
            self.wake.clear()

    async def summary_loop(self):
        while True:
            try:
                pending = self.store.pending()
                if not pending:
                    await self.summarize_sessions()
                    await asyncio.sleep(2)
                    continue
                for row_id in pending:
                    row = self.store.get(row_id)
                    if not row:
                        continue
                    try:
                        model = self.settings.model
                        summary = await self.model.summarize(row["clean_text"] or row["text"], row["app_name"], row["window_title"], model)
                        self.store.summarize(row_id, redact(summary), "generated", model)
                        self.state["model_error"] = None
                    except asyncio.CancelledError:
                        raise
                    except Exception as exc:
                        # Preserve source text and retry later; never label raw excerpts as model output.
                        self.state["model_error"] = f"Summarization unavailable ({type(exc).__name__}); source text is saved."
                        await asyncio.sleep(30)
                        break
                await self.summarize_sessions()
            except asyncio.CancelledError:
                raise
            except Exception as exc:
                self.state["model_error"] = f"Summary worker error: {type(exc).__name__}"
                await asyncio.sleep(10)

    async def summarize_sessions(self):
        for session in self.store.session_jobs():
            evidence = "\n\n".join(dict.fromkeys(r["clean_text"] or r["text"] for r in session["observations"]))
            if len(evidence) > 6500:
                evidence = evidence[:2200] + "\n[Intermediate screen text omitted]\n" + evidence[-4000:]
            summary = await self.model.summarize(evidence, session["app_name"], session["window_title"], self.settings.model)
            self.store.save_session_summary(session, redact(summary))
