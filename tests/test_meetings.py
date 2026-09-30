import asyncio
from datetime import datetime, timedelta
from pathlib import Path
from unittest.mock import AsyncMock

from fastapi.testclient import TestClient
import pytest

from constant_watch.engine import Engine
from constant_watch.meetings import MeetingManager, MeetingStore, detect_meeting
from constant_watch.server import create_app
from constant_watch.store import Store
from test_store import capture


def zoom():
    return {**capture(), 'app_id': 'us.zoom.xos', 'app_name': 'Zoom', 'window_title': 'Product review',
            'ax_text': 'Unmute Camera Leave meeting', 'ocr_text': ''}


def transcript(store, title='Planning'):
    row = store.create(title)
    store.update(row['id'], ended_at=row['started_at'], status='recorded')
    store.complete(row['id'], [{'start': 4.5, 'end': 7, 'source': 'Computer audio', 'text': 'Atlas ships on Friday.'}], 'en')
    return store.get(row['id'])


def test_detection_needs_provider_and_active_call_controls():
    assert detect_meeting(zoom())['app_name'] == 'Zoom'
    assert detect_meeting({**zoom(), 'ax_text': 'Join meeting Camera'}) is None
    assert detect_meeting({**zoom(), 'app_id': 'com.apple.Notes'}) is None
    assert detect_meeting({**zoom(), 'app_id': 'browser', 'source_url': 'https://meet.google.com/abc-defg-hij'})
    assert detect_meeting({**zoom(), 'app_id': 'browser', 'source_url': 'https://zoom.us.evil.test'}) is None


async def test_detection_prompts_without_starting_audio_and_respects_pause(tmp_path):
    native = AsyncMock(return_value=zoom())
    engine = Engine(tmp_path, capture_native=native)
    await engine.capture_once()
    assert not native.called
    assert engine.meetings.status()['candidate'] is None
    engine.settings.paused = False
    await engine.capture_once()
    assert engine.meetings.status()['candidate']['title'] == 'Product review'
    assert not engine.meetings.active
    assert native.call_count == 1  # Detecting a call issues no audio command.
    native.return_value = {'skipped': 'Excluded application'}
    engine.meetings.candidate = None
    await engine.capture_once()
    assert engine.meetings.candidate is None


async def test_one_recording_at_a_time_and_native_source_options(tmp_path):
    bridge = AsyncMock(return_value={'recording': True})
    manager = MeetingManager(Store(tmp_path), bridge)
    active = await manager.start('Review', microphone=False, system_audio=True)
    assert bridge.call_args.args == ('meeting-start',)
    assert bridge.call_args.kwargs['payload']['microphone'] is False
    with pytest.raises(ValueError, match='already'):
        await manager.start('Other')
    audio = manager.store.folder(active['id']) / 'system.wav'
    audio.write_bytes(b'fixture')
    bridge.return_value = {'tracks': [{'file': 'system.wav', 'source': 'Computer audio', 'offset': 0}]}
    stopped = await manager.stop()
    assert stopped['status'] == 'recorded'
    assert manager.active is None
    assert audio.exists()  # Retain until transcription succeeds.
    with pytest.raises(ValueError, match='No meeting'):
        await manager.stop()


async def test_denied_permission_does_not_leave_recording_active(tmp_path):
    bridge = AsyncMock(side_effect=[{'error': 'Enable microphone access'}, {'tracks': []}])
    manager = MeetingManager(Store(tmp_path), bridge)
    with pytest.raises(RuntimeError, match='microphone'):
        await manager.start('Review')
    assert not manager.active
    assert manager.store.list()[0]['status'] == 'failed'
    assert bridge.call_args.args == ('meeting-stop',)


async def test_shutdown_finalizes_active_session(tmp_path):
    bridge = AsyncMock(return_value={})
    manager = MeetingManager(Store(tmp_path), bridge)
    row = await manager.start('Review')
    bridge.return_value = {'tracks': [{'file': 'system.wav', 'source': 'Computer audio', 'offset': 0}]}
    await manager.shutdown()
    assert manager.active is None
    assert manager.store.get(row['id'])['ended_at']
    with pytest.raises(ValueError):
        await manager.start('After closing')


def test_transcript_search_day_export_retention_and_path_boundaries(tmp_path):
    store = Store(tmp_path)
    meetings = MeetingStore(store)
    row = transcript(meetings)
    assert meetings.search('Atlas')[0]['text'] == 'Atlas ships on Friday.'
    assert meetings.search('missing') == []
    assert '00:00:04' in meetings.markdown(row['id'])
    assert 'Atlas ships on Friday' in store.day_markdown(row['day'])
    assert 'watch://meeting/' in meetings.search('Atlas')[0]['evidence_uri']
    with pytest.raises(ValueError):
        meetings.get('../../settings')
    with store.connect() as db:
        db.execute('UPDATE meetings SET day=?', ('2001-01-01',))
    meetings.prune(30)
    assert meetings.get(row['id']) is None
    assert not meetings.folder(row['id']).exists()
    with store.connect() as db:
        assert db.execute('SELECT COUNT(*) FROM meeting_segments').fetchone()[0] == 0


@pytest.mark.parametrize('keep_audio', [False, True])
def test_audio_deletion_after_success_only(tmp_path, keep_audio):
    meetings = MeetingStore(Store(tmp_path))
    row = meetings.create('Review', keep_audio=keep_audio)
    audio = meetings.folder(row['id']) / 'system.wav'
    audio.write_bytes(b'fixture')
    meetings.update(row['id'], tracks=[{'file': 'system.wav', 'source': 'Computer audio', 'offset': 0}], status='failed')
    assert audio.exists()
    meetings.complete(row['id'], [], 'en')
    assert audio.exists() == keep_audio
    assert meetings.get(row['id'])['status'] == 'ready'


def test_context_contains_overlapping_observations_only(tmp_path):
    store = Store(tmp_path)
    meetings = MeetingStore(store)
    row = meetings.create('Review')
    stamp = datetime.fromisoformat(row['started_at'])
    in_id = store.add({**capture(), 'captured_at': (stamp + timedelta(seconds=5)).isoformat()})
    store.add({**capture(), 'window_title': 'Unrelated', 'captured_at': (stamp + timedelta(hours=1)).isoformat()})
    meetings.update(row['id'], ended_at=(stamp + timedelta(minutes=2)).isoformat())
    assert [v['id'] for v in meetings.context(row['id'])] == [in_id]
    assert meetings.context(row['id'], offset=1) == []


def test_interrupted_recording_recovers_audio_but_never_restarts_it(tmp_path):
    manager = MeetingManager(Store(tmp_path))
    row = manager.store.create('Interrupted')
    (manager.store.folder(row['id']) / 'microphone.wav').write_bytes(b'x' * 100)
    manager.recover()
    restored = manager.store.get(row['id'])
    assert restored['status'] == 'interrupted'
    assert restored['tracks'][0]['file'] == 'microphone.wav'
    assert not manager.active


def test_api_controls_and_context(tmp_path, monkeypatch):
    monkeypatch.delenv('CONSTANT_WATCH_NATIVE_TOKEN', raising=False)
    app = create_app(tmp_path, run_capture=False)
    manager = app.state.engine.meetings
    manager.bridge = AsyncMock(return_value={})
    headers = {'X-Constant-Watch': 'local'}
    with TestClient(app) as client:
        assert client.get('/meetings').status_code == 200
        assert client.post('/api/meetings/start', json={}).status_code == 403
        assert client.post('/api/meetings/start', json={'microphone': False, 'system_audio': False}, headers=headers).status_code == 409
        active = client.post('/api/meetings/start', json={'title': 'Review'}, headers=headers).json()
        meeting_id = active['id']
        assert client.delete('/api/meetings/' + meeting_id, headers=headers).status_code == 409
        assert client.get('/api/meetings/status').json()['active']['id'] == meeting_id
        assert client.post('/api/meetings/start', json={}, headers=headers).status_code == 409
        assert client.post('/api/meetings/stop', headers=headers).status_code == 200
        assert client.get('/api/meetings/' + meeting_id).json()['status'] == 'failed'
        assert client.get('/api/meetings/not-a-valid-id').status_code == 404
        assert client.post('/api/meetings/' + meeting_id + '/retry', headers=headers).status_code == 409
        assert client.get('/api/meetings?limit=99999').status_code == 422
        assert client.get('/api/meetings?day=not-a-date').status_code == 422
        assert client.get('/api/meetings/' + meeting_id + '/context').json() == []
        assert client.get('/api/meetings/' + meeting_id + '/markdown').status_code == 200
        assert client.delete('/api/meetings/' + meeting_id, headers=headers).status_code == 200
        row = transcript(manager.store)
        answer = client.post('/api/ask', json={'question': 'Atlas'}, headers=headers).json()
        assert answer['meeting_evidence'][0]['id'] == row['id']
        assert answer['found'] and 'Friday' in answer['answer']
        assert client.get('/api/markdown?day=' + row['day']).text.count('Atlas ships on Friday.') == 1


def test_transcript_retry_does_not_duplicate_passages(tmp_path):
    meetings = MeetingStore(Store(tmp_path))
    row = transcript(meetings)
    meetings.complete(row['id'], [{'start': 2, 'end': 4, 'source': 'Microphone', 'text': 'Replaced passage'}], 'en')
    assert len(meetings.get(row['id'])['segments']) == 1
    assert meetings.search('Atlas') == []
    assert meetings.search('Replaced')
