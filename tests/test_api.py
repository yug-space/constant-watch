from fastapi.testclient import TestClient
from constant_watch.server import create_app
from test_store import capture


def test_api_local_controls_and_journal(tmp_path):
    app = create_app(tmp_path, run_capture=False)
    engine = app.state.engine
    row_id = engine.store.add(capture())
    day = engine.store.get(row_id)["day"]
    with TestClient(app) as client:
        assert client.get("/").status_code == 200
        assert client.get("/api/apps").json()[0]["app_name"] == "Editor"
        assert len(client.get("/api/observations?q=alpha").json()) == 1
        assert "OCR text" in client.get("/api/markdown", params={"app_id":"com.example.Editor","day":day}).text
        settings = engine.settings.model_dump()
        settings["paused"] = True
        assert client.put("/api/settings", json=settings).status_code == 403
        assert client.put("/api/settings", json=settings, headers={"Origin":"https://evil.test","X-Constant-Watch":"local"}).status_code == 403
        assert client.put("/api/settings", json=settings, headers={"X-Constant-Watch":"local"}).status_code == 200
        assert engine.settings.paused
        assert client.get("/api/apps", headers={"Host":"evil.test"}).status_code == 400
        assert client.get("/api/apps", headers={"Sec-Fetch-Site":"cross-site"}).status_code == 403
        assert client.get("/api/observations?limit=9999").status_code == 422
        assert client.get("/api/markdown?app_id=../../etc&day=passwd").status_code == 422
        assert client.get("/api/day-flow", params={"day":day}).json()["total_sessions"] == 1
        assert "Daily flow" in client.get("/api/markdown", params={"day":day}).text
        assert client.get("/api/day-flow?day=../../bad").status_code == 422


def test_second_daemon_cannot_use_same_data(tmp_path):
    with TestClient(create_app(tmp_path, run_capture=False)):
        import pytest
        with pytest.raises(RuntimeError, match="already running"):
            with TestClient(create_app(tmp_path, run_capture=False)):
                pass
