import sys
from pathlib import Path
from constant_watch.capture import helper_path


def test_frozen_helper_is_resolved_relative_to_app(monkeypatch):
    monkeypatch.delenv('CONSTANT_WATCH_HELPER', raising=False)
    monkeypatch.setattr(sys, 'frozen', True, raising=False)
    monkeypatch.setattr(sys, 'executable', '/Applications/Constant Watch.app/Contents/Helpers/Runtime.app/Contents/MacOS/constant-watch')
    assert helper_path() == Path('/Applications/Constant Watch.app/Contents/Helpers/Constant Watch Capture.app/Contents/MacOS/capture')


def test_helper_override_is_preserved_in_frozen_app(monkeypatch):
    monkeypatch.setattr(sys, 'frozen', True, raising=False)
    monkeypatch.setenv('CONSTANT_WATCH_HELPER', '/tmp/test-helper')
    assert helper_path() == Path('/tmp/test-helper')
