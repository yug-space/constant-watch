"""Isolated speech worker. Only explicit model setup uses the network."""
import os
from .config import data_dir
from .meetings import MeetingStore, SPEECH_MODEL
from .store import Store


def run(command, meeting_id=''):
    from faster_whisper import WhisperModel
    root = data_dir()
    meetings = MeetingStore(Store(root))
    model_path = meetings.root / 'speech-model'
    if command == 'speech-download':
        from faster_whisper.utils import download_model
        download_model(SPEECH_MODEL, output_dir=str(model_path))
        # Load once to validate the download before advertising readiness.
        WhisperModel(str(model_path), device='cpu', compute_type='int8', cpu_threads=2, local_files_only=True)
        (model_path / 'ready').write_text(SPEECH_MODEL, encoding='utf-8')
        return
    row = meetings.get(meeting_id)
    if not row:
        raise ValueError('Meeting is unavailable')
    try:
        model = WhisperModel(str(model_path), device='cpu', compute_type='int8', cpu_threads=2, local_files_only=True)
        results, languages = [], set()
        for track in row['tracks']:
            if track['file'] not in ('microphone.wav', 'system.wav'):
                raise ValueError('Invalid audio track')
            path = meetings.folder(meeting_id) / track['file']
            if not path.exists():
                raise ValueError('Audio is no longer available for this meeting.')
            segments, info = model.transcribe(str(path), beam_size=3, vad_filter=True,
                condition_on_previous_text=False, vad_parameters={'min_silence_duration_ms': 500})
            languages.add(info.language)
            for s in segments:
                if s.text.strip() and s.no_speech_prob < 0.6:
                    results.append({'start': round(s.start + track.get('offset', 0), 3),
                                    'end': round(s.end + track.get('offset', 0), 3),
                                    'source': track['source'], 'text': s.text.strip()})
        meetings.complete(meeting_id, results, ', '.join(sorted(languages)))
    except Exception as exc:
        # Keep audio for a retry and expose a useful, bounded error without logging transcript content.
        meetings.update(meeting_id, status='failed', error=f'Transcription failed ({type(exc).__name__}). Audio is retained; retry after checking the speech model and free space.')
        raise
