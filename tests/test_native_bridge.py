import asyncio
from unittest.mock import AsyncMock

import httpx
import pytest

from constant_watch.native_bridge import NativeBridge
from constant_watch.server import create_app


async def test_commands_keep_exclusions_and_match_their_own_response():
    bridge = NativeBridge()
    capture = asyncio.create_task(bridge.call(excluded=["com.example.private"]))
    status = asyncio.create_task(bridge.call("status"))
    first = await bridge.next()
    second = await bridge.next()
    assert first["command"] == "capture"
    assert first["excluded"] == ["com.example.private"]
    assert second["command"] == "status"
    assert bridge.complete(second["id"], {"accessibility": True})
    assert await status == {"accessibility": True}
    assert bridge.complete(first["id"], {"skipped": "Excluded application"})
    assert await capture == {"skipped": "Excluded application"}
    assert not bridge.complete(first["id"], {})
    assert not bridge.pending and not bridge.jobs


async def test_timeout_and_cancellation_discard_stale_commands():
    bridge = NativeBridge(timeout=0.01)
    with pytest.raises(RuntimeError, match="not responding"):
        await bridge.call("status")
    assert not bridge.jobs and not bridge.pending
    task = asyncio.create_task(bridge.call())
    job = await bridge.next()
    task.cancel()
    with pytest.raises(asyncio.CancelledError):
        await task
    assert not bridge.complete(job["id"], {"ax_text": "must not store"})
    assert not bridge.pending


async def test_api_uses_app_permissions_and_authenticates_native_bridge(tmp_path, monkeypatch):
    monkeypatch.setenv("CONSTANT_WATCH_NATIVE_TOKEN", "test-native-token")
    # The helper must never run when the native UI owns capture.
    helper = AsyncMock(side_effect=AssertionError("launched separate helper"))
    monkeypatch.setattr("constant_watch.server.native", helper)
    monkeypatch.setattr("constant_watch.engine.native", helper)
    app = create_app(tmp_path, run_capture=False)
    app.state.engine.model.status = AsyncMock(return_value={"available": True, "model": "test"})
    auth = {"X-Constant-Watch-Native": "test-native-token", "X-Constant-Watch": "local"}
    async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://localhost") as client:
        assert (await client.get("/api/native/next")).status_code == 403
        assert (await client.post("/api/native/result/missing", json={}, headers={"X-Constant-Watch": "local"})).status_code == 403
        assert (await client.post("/api/native/result/missing", json={}, headers=auth)).status_code == 410
        request = asyncio.create_task(client.get("/api/status"))
        job = (await client.get("/api/native/next", headers=auth)).json()
        assert job["command"] == "status"
        permissions = {"accessibility": True, "screen_recording": True}
        assert (await client.post(f'/api/native/result/{job["id"]}', json=permissions, headers=auth)).status_code == 200
        assert (await request).json()["permissions"] == permissions
        engine = app.state.engine
        engine.settings.paused = False
        capture = asyncio.create_task(engine.capture_once())
        job = (await client.get("/api/native/next", headers=auth)).json()
        assert job["command"] == "capture"
        assert job["excluded"] == engine.settings.excluded_apps
        await client.post(f'/api/native/result/{job["id"]}', json={"skipped": "Excluded application"}, headers=auth)
        await capture
        assert engine.state["capture_status"] == "Excluded application"
        assert not engine.store.apps()
    helper.assert_not_called()
