"""Windows WASAPI audio sources, captured to disk in bounded blocks."""
import threading
import time
import wave
import ctypes
from contextlib import contextmanager


@contextmanager
def com_thread():
    # WASAPI device enumeration and capture each run on their own worker thread.
    hr = ctypes.windll.ole32.CoInitializeEx(None, 0)
    if hr not in (0, 1, -2147417850):
        raise RuntimeError('Windows audio initialization failed.')
    try:
        yield
    finally:
        if hr in (0, 1):
            ctypes.windll.ole32.CoUninitialize()


class WindowsRecorder:
    def __init__(self, folder, microphone, system_audio):
        self.folder = folder
        self.microphone = microphone
        self.system_audio = system_audio
        self.done = threading.Event()
        self.threads = []
        self.errors = []
        self.tracks = []
        self.started = time.monotonic()

    def start(self):
        with com_thread():
            self._start()

    def _start(self):
        import soundcard as sc
        sources = []
        if self.microphone:
            device = sc.default_microphone()
            if device is None:
                raise RuntimeError('No microphone is available. Connect one or record computer audio only.')
            sources.append((device, 'microphone.wav', 'Microphone'))
        if self.system_audio:
            speaker = sc.default_speaker()
            if speaker is None:
                raise RuntimeError('No audio output is available. Connect headphones or speakers.')
            device = sc.get_microphone(id=speaker.id, include_loopback=True)
            sources.append((device, 'system.wav', 'Computer audio'))
        ready = []
        for device, filename, label in sources:
            event = threading.Event()
            thread = threading.Thread(target=self._record, args=(device, filename, label, event), daemon=True)
            self.threads.append(thread)
            ready.append(event)
            thread.start()
        for event in ready:
            if not event.wait(8):
                self.errors.append('Audio device did not respond. Check Windows microphone privacy settings.')
        if self.errors:
            self.stop()
            raise RuntimeError('; '.join(self.errors))

    def _record(self, device, filename, label, ready):
        with com_thread():
            self._record_initialized(device, filename, label, ready)

    def _record_initialized(self, device, filename, label, ready):
        import numpy as np
        try:
            # Record all device channels. WASAPI has a known mono-channel capture issue.
            with device.recorder(samplerate=16000, blocksize=1600) as recorder:
                with wave.open(str(self.folder / filename), 'wb') as output:
                    output.setnchannels(1)
                    output.setsampwidth(2)
                    output.setframerate(16000)
                    self.tracks.append({'file': filename, 'source': label, 'offset': time.monotonic() - self.started})
                    ready.set()
                    while not self.done.is_set():
                        data = recorder.record(numframes=1600)
                        mono = np.clip(data.mean(axis=1), -1, 1)
                        output.writeframes((mono * 32767).astype('<i2').tobytes())
        except Exception:
            self.errors.append(f'{label} capture stopped. Check device access and microphone privacy settings.')
            self.done.set()
        finally:
            ready.set()

    def status(self):
        return {'recording': bool(self.threads) and not self.done.is_set(), 'error': '; '.join(self.errors)}

    def stop(self):
        self.done.set()
        for thread in self.threads:
            thread.join(timeout=4)
        if any(t.is_alive() for t in self.threads):
            self.errors.append('An audio device stopped responding; its partial recording may be unavailable.')
        tracks = [t for t in self.tracks if (self.folder / t['file']).exists() and (self.folder / t['file']).stat().st_size > 44]
        return {'tracks': tracks, 'warning': '; '.join(self.errors)}
