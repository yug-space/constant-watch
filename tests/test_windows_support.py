from pathlib import Path
from unittest.mock import AsyncMock
import pytest
from constant_watch import platform_support
from constant_watch.config import Settings


def test_windows_data_uses_local_appdata(monkeypatch, tmp_path):
    # Override only this module's platform view, not pathlib's global platform.
    import types
    monkeypatch.setattr(platform_support, 'sys', types.SimpleNamespace(platform='win32'))
    monkeypatch.setenv('LOCALAPPDATA', str(tmp_path))
    assert platform_support.default_data_dir() == tmp_path / 'Constant Watch'


def test_lock_rejects_second_daemon_and_releases(tmp_path):
    first = platform_support.acquire_lock(tmp_path / 'daemon.lock')
    try:
        with pytest.raises(RuntimeError, match='already running'):
            platform_support.acquire_lock(tmp_path / 'daemon.lock')
    finally:
        first.close()
    platform_support.acquire_lock(tmp_path / 'daemon.lock').close()


def test_windows_password_managers_excluded_by_default():
    settings = Settings()
    assert settings.paused
    assert {'windows:1password.exe','windows:bitwarden.exe','windows:keepassxc.exe'} <= set(settings.excluded_apps)


async def test_windows_dispatch_preserves_exclusions(monkeypatch):
    import types
    from constant_watch import capture, windows_capture
    call = AsyncMock(return_value={'skipped':'Excluded application'})
    monkeypatch.setattr(capture, 'sys', types.SimpleNamespace(platform='win32'))
    monkeypatch.setattr(windows_capture, 'capture', call)
    assert await capture.native(excluded=['windows:private.exe']) == {'skipped':'Excluded application'}
    call.assert_awaited_once_with('capture', ['windows:private.exe'])
