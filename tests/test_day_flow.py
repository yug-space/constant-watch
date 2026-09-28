import sys
from datetime import datetime, timedelta
from constant_watch.store import Store
from test_store import capture


def at(hour, minute, second=0):
    return datetime.now().astimezone().replace(hour=hour, minute=minute, second=second, microsecond=0).isoformat()


def test_app_return_is_preserved_and_consecutive_samples_group(tmp_path):
    store = Store(tmp_path)
    day = at(9, 0)[:10]
    a = store.add(capture(captured_at=at(9, 0)))
    assert store.add(capture(captured_at=at(9, 1))) is None
    b = store.add(capture(captured_at=at(9, 2), text="A new detail"))
    c = store.add(capture(captured_at=at(9, 3), app_id="browser", app_name="Browser"))
    d = store.add(capture(captured_at=at(9, 4)))
    assert d is not None  # Unchanged Editor screen is still a return to Editor.
    store.summarize(a, "Working on a milestone.", "generated", "test")
    store.summarize(b, "Working on a milestone.", "generated", "test")
    flow = store.daily_flow(day)
    assert [s["app_name"] for s in flow["sessions"]] == ["Editor", "Browser", "Editor"]
    assert [r["id"] for r in flow["sessions"][0]["observations"]] == [a, b]
    assert flow["sessions"][0]["summary"] == "Working on a milestone."
    assert store.get(a)["last_seen_at"] == at(9, 1)
    doc = (tmp_path / "days" / f"{day}.md").read_text()
    assert doc.index("## 09:00:00") < doc.index("## 09:03:00") < doc.index("## 09:04:00")
    assert "Working on a milestone." in doc
    if sys.platform != "win32":
        assert (tmp_path / "days" / f"{day}.md").stat().st_mode & 0o077 == 0


def test_gaps_window_changes_pagination_and_rebuild(tmp_path):
    store = Store(tmp_path)
    day = at(9, 0)[:10]
    store.add(capture(captured_at=at(9, 0)))
    store.add(capture(captured_at=at(9, 10)))
    store.add(capture(captured_at=at(9, 11), window_title="Another project"))
    page = store.daily_flow(day, limit=2)
    assert page["total_sessions"] == 3 and page["next_offset"] == 2
    assert store.daily_flow(day, offset=2)["sessions"][0]["window_title"] == "Another project"
    path = tmp_path / "days" / f"{day}.md"
    path.unlink()
    store.rebuild_exports()
    assert "Another project" in path.read_text()


def test_empty_and_retained_days(tmp_path):
    store = Store(tmp_path)
    assert store.day_markdown("2000-01-01") == ""
    old = (datetime.now().astimezone() - timedelta(days=40)).isoformat()
    store.add(capture(captured_at=old))
    path = tmp_path / "days" / f"{old[:10]}.md"
    assert path.exists()
    store.prune(30)
    assert not path.exists()
    assert store.daily_flow(old[:10])["total_sessions"] == 0


def test_session_summary_is_one_narrative_and_marks_updates(tmp_path):
    store = Store(tmp_path)
    first = store.add(capture(captured_at=at(9, 0)))
    second = store.add(capture(captured_at=at(9, 1), text="New prototype detail"))
    store.summarize(first, "First detail", "generated", "test")
    store.summarize(second, "Second detail", "generated", "test")
    jobs = store.session_jobs()
    assert len(jobs) == 1
    store.save_session_summary(jobs[0], "Reviewed the milestone and prototype together.")
    session = store.daily_flow(at(9, 0)[:10])["sessions"][0]
    assert session["summary"] == "Reviewed the milestone and prototype together."
    assert session["needs_summary"] is False
    store.add(capture(captured_at=at(9, 2), text="Another change"))
    session = store.daily_flow(at(9, 0)[:10])["sessions"][0]
    assert session["needs_summary"] and session["pending_summaries"] > 0
