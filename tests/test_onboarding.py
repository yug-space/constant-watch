from unittest.mock import AsyncMock
from fastapi.testclient import TestClient
from constant_watch.config import Settings, load_settings
from constant_watch.server import create_app


def test_new_user_starts_paused_and_can_finish_without_auth(tmp_path):
    app = create_app(tmp_path, run_capture=False)
    assert app.state.engine.settings.paused
    assert not app.state.engine.settings.onboarding_complete
    with TestClient(app) as client:
        landing = client.get("/")
        assert landing.status_code == 200 and "Keep the thread." in landing.text
        assert client.get("/static/assets/alpine-hero.jpg").status_code == 200
        assert client.get("/journal").status_code == 200
        settings = Settings(onboarding_complete=True, paused=False, purpose="review")
        assert client.put("/api/settings", json=settings.model_dump(), headers={"X-Constant-Watch":"local"}).status_code == 200
    saved = load_settings(tmp_path)
    assert saved.onboarding_complete and not saved.paused and saved.purpose == "review"


def test_permission_requests_are_separate(tmp_path, monkeypatch):
    native = AsyncMock(return_value={"accessibility":True,"screen_recording":False})
    monkeypatch.setattr("constant_watch.server.native", native)
    with TestClient(create_app(tmp_path, run_capture=False)) as client:
        assert client.post("/api/permissions?kind=accessibility", headers={"X-Constant-Watch":"local"}).status_code == 200
        native.assert_awaited_with("request-accessibility")
        assert client.post("/api/permissions?kind=screen", headers={"X-Constant-Watch":"local"}).status_code == 200
        native.assert_awaited_with("request-screen")
        assert client.post("/api/permissions?kind=bad", headers={"X-Constant-Watch":"local"}).status_code == 422
