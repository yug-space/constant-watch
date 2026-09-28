from datetime import datetime, timedelta
import json
import sqlite3

from fastapi.testclient import TestClient
from constant_watch.context import clean_screen_text, safe_source
from constant_watch.recall import Recall
from constant_watch.server import create_app
from constant_watch.store import Store
from test_store import capture


def test_noise_preserves_numbers_negations_and_originals(tmp_path):
    raw = 'File\nView\nProject Atlas\nReview Friday 10 AM\nReview Friday 10 AM\nBudget -100\nBudget 100\nNot approved'
    clean, removed = clean_screen_text(raw, title='Project Atlas')
    assert removed == 4
    assert 'Budget -100' in clean and 'Budget 100' in clean and 'Not approved' in clean
    store = Store(tmp_path)
    row = store.add(capture(text=raw, ax_text=raw, window_title='Project Atlas'))
    assert store.get(row)['ax_text'] == raw
    assert store.add(capture(text=raw + '\nHelp', window_title='Project Atlas')) is None
    assert store.add(capture(text=raw.replace('10 AM', '11 AM'), window_title='Project Atlas')) is not None


def test_source_links_strip_secrets_and_reject_unsafe_schemes():
    assert safe_source('https://user:pass@example.com/plan?q=atlas&token=secret#private') == 'https://example.com/plan?q=atlas'
    assert safe_source('file:///Users/me/Atlas%20plan.md') == 'file:///Users/me/Atlas%20plan.md'
    for value in ['javascript:alert(1)', 'file:///tmp/script.sh', 'file://remote/path.md', 'https://bad:port/', 'https://example.com/\nsecret']:
        assert safe_source(value) == ''


def test_recall_questions_have_verifiable_quotes_and_filters(tmp_path):
    store = Store(tmp_path); recall = Recall(store)
    first = store.add(capture(window_title='Atlas — Planning', text='Project Atlas\nReview Friday 10 AM\nDecided to keep the prototype local.', source_url='https://example.com/atlas?token=secret'))
    second = store.add(capture(app_id='browser', app_name='Browser', window_title='Atlas — Research', text='Project Atlas\nNext: test the prototype with Mia.'))
    answer = recall.ask('When is the Atlas review?')
    assert answer['found'] and any(s['id'] == first and 'Friday 10 AM' in s['quote'] for s in answer['sources'])
    assert answer['sources'][0]['source_url'] == 'https://example.com/atlas'
    for source in answer['sources']:
        original = recall.observation(source['id'])
        assert all(line in original['clean_text'] for line in source['quote'].splitlines())
        assert source['deep_link'] == f"constantwatch://observation/{source['id']}"
    assert recall.ask('Find decisions I saw')['found']
    assert not recall.ask('Xylophonium quasar')['found']
    assert not recall.ask('Atlas', day='2001-01-01')['found']
    assert [s['id'] for s in recall.ask('Atlas', app_id='browser')['sources']] == [second]
    assert recall.observation(9999) is None


def test_cross_app_topics_paginate_chronologically_and_expire(tmp_path):
    store = Store(tmp_path); recall = Recall(store)
    old = (datetime.now().astimezone() - timedelta(days=45)).isoformat()
    one = store.add(capture(window_title='Atlas — Notes', text='Project Atlas\nFirst draft', captured_at=old))
    two = store.add(capture(window_title='Atlas — Research', text='Project Atlas\nSecond draft', app_id='browser', app_name='Browser'))
    store.add(capture(window_title='Orion — Notes', text='Project Orion\nUnrelated draft'))
    group = next(t for t in recall.topics()['topics'] if t['key'] == 'atlas')
    assert group['captures'] == 2 and group['app_count'] == 2
    page = recall.topic('atlas', limit=1)
    assert [r['id'] for r in page['sources']] == [one] and page['next_offset'] == 1
    assert recall.topic('atlas', offset=1)['sources'][0]['id'] == two
    store.prune(30)
    assert recall.observation(one) is None
    assert recall.topic('atlas')['total'] == 1
    assert not recall.ask('First draft')['found']


def test_old_matches_survive_recent_capture_limit(tmp_path):
    store = Store(tmp_path)
    first = store.add(capture(text='RareNebula review Friday', window_title='RareNebula', captured_at='2026-09-01T10:00:00+05:30'))
    # Populate recent records without repeatedly rewriting all Markdown exports.
    export, export_day = store.export, store.export_day
    store.export = lambda *args: None; store.export_day = lambda *args: None
    for i in range(170):
        store.add(capture(text=f'Unrelated capture {i}', window_title='Inbox'))
    store.export, store.export_day = export, export_day
    assert Recall(store).ask('RareNebula')['sources'][0]['id'] == first


def test_recall_api_validation_and_citations(tmp_path):
    app = create_app(tmp_path, run_capture=False)
    row = app.state.engine.store.add(capture(text='Project Atlas\nReview Friday'))
    with TestClient(app) as client:
        assert client.post('/api/ask', json={'question':'Atlas'}).status_code == 403
        answer = client.post('/api/ask', json={'question':'Atlas'}, headers={'X-Constant-Watch':'local'})
        assert answer.status_code == 200 and answer.json()['sources'][0]['id'] == row
        assert client.post('/api/ask', json={'question':'   '}, headers={'X-Constant-Watch':'local'}).status_code == 422
        assert client.get('/api/topics?day=invalid').status_code == 422
        assert client.get('/api/topics/atlas').json()['total'] == 1
        assert client.get(f'/api/evidence/{row}').json()['ax_text']
        assert client.get('/api/evidence/9999').status_code == 404


def test_migrates_existing_capture_and_rebuilds_missing_index(tmp_path):
    store = Store(tmp_path)
    row = store.add(capture(text='Project Atlas\nReview Friday'))
    # Emulate pre-recall schema, preserving the original observation and old search index.
    with store.connect() as db:
        for trigger in ['recall_insert', 'recall_delete', 'recall_update']:
            db.execute(f'DROP TRIGGER {trigger}')
        db.execute('DROP TABLE recall_index')
        for column in ['source_url', 'document_name', 'clean_text', 'topics', 'noise_removed', 'context_version']:
            db.execute(f'ALTER TABLE observations DROP COLUMN {column}')
    upgraded = Store(tmp_path)
    assert upgraded.get(row)['ax_text'] == capture()['ax_text']
    assert Recall(upgraded).ask('Atlas')['sources'][0]['id'] == row
    assert upgraded.get(row)['source_url'] == ''
    with upgraded.connect() as db:
        db.execute('DROP TABLE recall_index')
    assert Recall(Store(tmp_path)).ask('Atlas')['found']


def test_old_running_writer_is_backfilled_on_next_open(tmp_path):
    store = Store(tmp_path)
    row = store.add(capture(text='Project Atlas\nReview Friday'))
    with store.connect() as db:
        db.execute("UPDATE observations SET clean_text='',topics='[]',context_version=0 WHERE id=?", (row,))
    assert Recall(Store(tmp_path)).ask('Atlas')['found']
