import sys
from datetime import datetime, timedelta
from constant_watch.store import Store, app_slug
from constant_watch.privacy import redact, merge_text


def capture(**changes):
    return {"app_id":"com.example.Editor", "app_name":"Editor", "window_title":"Project planning",
            "ax_text":"Milestone alpha ships Friday", "ocr_text":"Milestone alpha ships Friday\nBudget approved",
            "text":"Milestone alpha ships Friday\nBudget approved", **changes}


def test_journal_persistence_dedup_and_summary_search(tmp_path):
    store = Store(tmp_path)
    row_id = store.add(capture())
    assert row_id
    assert store.add(capture()) is None
    assert len(store.list(query="alpha Friday")) == 1
    store.summarize(row_id, "Release milestone planned.", "generated", "qwen2.5:0.5b")
    assert len(store.list(query="release")) == 1
    store.summarize(row_id, "Shipping this week.", "generated", "qwen2.5:0.5b")
    assert store.list(query="release") == []
    reopened = Store(tmp_path)
    row = reopened.get(row_id)
    document = tmp_path / "apps" / app_slug(row["app_id"]) / f"{row['day']}.md"
    assert "Shipping this week" in document.read_text()
    assert "### Accessibility text" in document.read_text()
    assert "### OCR text" in document.read_text()
    assert "untrusted reference data" in document.read_text()
    if sys.platform != "win32":
        assert document.stat().st_mode & 0o077 == 0


def test_app_grouping_dates_and_paging(tmp_path):
    s = Store(tmp_path)
    first = s.add(capture())
    second = s.add(capture(text="Changed"))
    s.add(capture(app_id="com.example.Browser"))
    assert len(s.apps()) == 2
    assert len(s.list(app_id="com.example.Editor")) == 2
    assert s.list(before=second)[0]["id"] == first
    assert s.markdown("../escape", "2026-01-01") == ""
    assert "/" not in app_slug("../../escape")
    assert s.list(query='" OR *') == []


def test_retention_removes_db_search_and_markdown(tmp_path):
    s = Store(tmp_path)
    old = (datetime.now().astimezone() - timedelta(days=40)).isoformat()
    first = s.add(capture(captured_at=old))
    s.add(capture())  # Identical text on another day is a new daily entry.
    assert len(s.list()) == 2
    s.prune(30)
    assert s.get(first) is None
    assert len(s.list(query="milestone")) == 1
    assert len(list(tmp_path.glob("apps/*/*.md"))) == 1


def test_redaction_and_merge():
    text = "api_key: supersecret\nBearer abc.def.xyz\nsk-abcdefghijklmno123\nKeep ordinary context"
    result = redact(text)
    assert "supersecret" not in result and "abc.def.xyz" not in result and "sk-abc" not in result
    assert "Keep ordinary context" in result
    assert merge_text("Hello world\nOne", "hello   world\nTwo") == "Hello world\nOne\nTwo"
    assert "private data" not in redact("-----BEGIN RSA PRIVATE KEY-----\nprivate data\n-----END RSA PRIVATE KEY-----")
