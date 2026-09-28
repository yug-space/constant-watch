import asyncio
from unittest.mock import AsyncMock
from constant_watch.engine import Engine
from test_store import capture


async def test_pause_during_capture_discards_inflight_result(tmp_path, monkeypatch):
    engine = Engine(tmp_path)
    engine.settings.paused = False
    started, finish = asyncio.Event(), asyncio.Event()
    async def native(**kwargs):
        started.set()
        await finish.wait()
        return capture()
    monkeypatch.setattr("constant_watch.engine.native", native)
    task = asyncio.create_task(engine.capture_once())
    await started.wait()
    engine.configure(engine.settings.model_copy(update={"paused": True}))
    finish.set()
    await task
    assert engine.store.list() == []


async def test_exclusions_sent_to_native_and_skipped_not_saved(tmp_path, monkeypatch):
    engine = Engine(tmp_path)
    engine.settings.paused = False
    mock = AsyncMock(return_value={"skipped":"Excluded application"})
    monkeypatch.setattr("constant_watch.engine.native", mock)
    await engine.capture_once()
    assert "com.apple.Passwords" in mock.call_args.kwargs["excluded"]
    assert engine.store.list() == []


async def test_redacts_before_storage_and_model(tmp_path, monkeypatch):
    engine = Engine(tmp_path)
    engine.settings.paused = False
    monkeypatch.setattr("constant_watch.engine.native", AsyncMock(return_value=capture(ax_text="password: secret123", ocr_text="api_key: anothersecret")))
    await engine.capture_once()
    row = engine.store.list()[0]
    assert "secret123" not in str(row) and "anothersecret" not in str(row)


async def test_summary_worker_runs_model_and_persists(tmp_path):
    engine = Engine(tmp_path)
    row_id = engine.store.add(capture())
    engine.model.summarize = AsyncMock(return_value="Milestone ships Friday.")
    task = asyncio.create_task(engine.summary_loop())
    for _ in range(100):
        if engine.store.get(row_id)["summary_status"] == "generated": break
        await asyncio.sleep(.01)
    task.cancel()
    await asyncio.gather(task, return_exceptions=True)
    assert engine.store.get(row_id)["summary"] == "Milestone ships Friday."


async def test_model_failure_preserves_pending_source(tmp_path):
    engine = Engine(tmp_path)
    row_id = engine.store.add(capture())
    engine.model.summarize = AsyncMock(side_effect=RuntimeError("unavailable"))
    task = asyncio.create_task(engine.summary_loop())
    await asyncio.sleep(.05)
    task.cancel()
    await asyncio.gather(task, return_exceptions=True)
    assert engine.store.get(row_id)["summary_status"] == "pending"
    assert engine.store.get(row_id)["text"]
    assert engine.state["model_error"]


async def test_missing_permissions_are_not_reported_as_an_empty_screen(tmp_path):
    engine = Engine(tmp_path, capture_native=AsyncMock(return_value={
        "accessibility": False, "screen_recording": False,
        "warnings": ["Accessibility permission missing", "Screen Recording permission missing"],
    }))
    engine.settings.paused = False
    await engine.capture_once()
    assert engine.state["capture_status"] == "Enable macOS permissions to start capture"
    assert len(engine.state["warnings"]) == 2
    assert engine.store.list() == []
