import pytest
from fastapi.testclient import TestClient
from constant_watch.review import review
from constant_watch.server import create_app
from constant_watch.store import Store
from test_store import capture


def add(store, day, text, **kwargs):
    return store.add(capture(captured_at=f'{day}T12:00:00+05:30', text=text, **kwargs))


def test_range_counts_sources_and_cross_app_projects(tmp_path):
    store = Store(tmp_path)
    old = add(store, '2026-09-20', 'Project Atlas\nOld note')
    a = add(store, '2026-09-21', 'Project Atlas\nNext: verify the budget', window_title='Atlas Notes')
    b = add(store, '2026-09-27', 'Project Atlas\nBudget not approved', app_id='browser', app_name='Browser', window_title='Budget')
    add(store, '2026-09-28', 'Project Atlas\nOutside date range')
    result = review(store, '2026-09-21', '2026-09-27')
    assert result['captures'] == 2 and result['app_count'] == 2
    assert result['days_with_captures'] == 2 and len(result['days']) == 7
    assert result['days'][1]['captures'] == 0
    assert len(result['highlights']) == 1
    sources = result['highlights'][0]['sources']
    assert {s['id'] for s in sources} == {a, b}
    assert old not in {s['id'] for s in sources}
    assert 'Budget not approved' in result['draft']
    assert f'constantwatch://observation/{b}' in result['draft']
    assert '[Add confirmed outcomes' in result['draft']
    for source in sources:
        assert all(line in store.get(source['id'])['clean_text'] for line in source['quote'].splitlines())


def test_same_window_title_does_not_merge_unrelated_apps(tmp_path):
    store = Store(tmp_path)
    add(store, '2026-09-21', 'First document', window_title='Notes')
    add(store, '2026-09-21', 'Second document', window_title='Notes', app_id='browser', app_name='Browser')
    assert review(store, '2026-09-21', '2026-09-21')['total_groups'] == 2


def test_empty_validation_and_retention(tmp_path):
    store = Store(tmp_path)
    for start, end in [('invalid', '2026-09-21'), ('2026-09-22','2026-09-21'), ('2026-01-01','2026-03-01')]:
        with pytest.raises(ValueError): review(store, start, end)
    add(store, '2000-01-01', 'Expired evidence')
    store.prune(30)
    result = review(store, '2000-01-01', '2000-01-01')
    assert result['captures'] == 0 and result['highlights'] == []
    assert 'No captured evidence' in result['draft']


def test_review_has_full_counts_even_when_highlights_are_limited(tmp_path):
    store = Store(tmp_path)
    store.export = lambda *args: None
    store.export_day = lambda *args: None
    for i in range(205):
        add(store, '2026-09-21', f'Unique content {i}', window_title=f'Document {i}')
    result = review(store, '2026-09-21', '2026-09-21')
    assert result['captures'] == 205 and result['total_groups'] == 205
    assert len(result['highlights']) == 12
    assert result['apps'][0]['captures'] == 205


def test_review_api(tmp_path):
    app = create_app(tmp_path, run_capture=False)
    add(app.state.engine.store, '2026-09-21', 'Project Atlas\nReview Friday')
    with TestClient(app) as client:
        assert client.get('/api/review?start=2026-09-21&end=2026-09-27').json()['captures'] == 1
        assert client.get('/api/review?start=bad&end=2026-09-27').status_code == 422
        assert client.get('/api/review?start=2026-09-28&end=2026-09-27').status_code == 422
