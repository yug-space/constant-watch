"""Exercise local speech with synthetic audio. Never records a microphone or system sound.

Usage: PYTHONPATH=src .venv/bin/python scripts/smoke-meetings.py [frozen-service]
Requires the speech model previously downloaded into build/meeting-smoke.
"""
import json
import os
from pathlib import Path
import subprocess
import sys

from constant_watch.meetings import MeetingStore
from constant_watch.store import Store

root = Path('build/meeting-smoke').resolve()
meetings = MeetingStore(Store(root))
row = meetings.create('Synthetic speech verification')
folder = meetings.folder(row['id'])
# macOS synthesizes a fixture directly to disk; no computer audio is played or captured.
subprocess.run(['say', '-v', 'Samantha', '-o', str(folder / 'fixture.aiff'),
                'The project review is complete. We agreed to launch Atlas on Friday. Sarah will prepare the design document.'], check=True)
subprocess.run(['afconvert', str(folder / 'fixture.aiff'), str(folder / 'system.wav'), '-f', 'WAVE', '-d', 'LEI16@16000', '-c', '1'], check=True)
meetings.update(row['id'], ended_at=row['started_at'], status='recorded', tracks=[{'file': 'system.wav', 'source': 'Computer audio', 'offset': 0}])
command = [sys.argv[1]] if len(sys.argv) > 1 else [sys.executable, '-m', 'constant_watch.cli']
subprocess.run([*command, 'speech-transcribe', '--meeting-id', row['id']], env={**os.environ, 'CONSTANT_WATCH_DATA': str(root), 'HF_HUB_OFFLINE': '1'}, check=True)
result = meetings.get(row['id'])
assert result['status'] == 'ready', result['error']
text = ' '.join(s['text'] for s in result['segments'])
assert 'Friday' in text and 'design' in text.lower(), text
assert meetings.search('Friday')[0]['evidence_uri'].startswith('watch://meeting/')
assert not (folder / 'system.wav').exists(), 'Audio should be removed after success'
assert 'Friday' in (folder / 'transcript.md').read_text()
print(json.dumps({'meeting_id': row['id'], 'segments': len(result['segments']), 'transcript': text, 'offline': True, 'audio_removed': True}, indent=2))
