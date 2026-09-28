"""Small OS boundary shared by the service and desktop launchers."""
import os
import sys
from pathlib import Path


def default_data_dir() -> Path:
    if sys.platform == 'win32':
        return Path(os.environ.get('LOCALAPPDATA', str(Path.home() / 'AppData/Local'))) / 'Constant Watch'
    return Path.home() / 'Library/Application Support/Constant Watch'


def acquire_lock(path: Path):
    # Never truncate a lock file another process may hold.
    handle = path.open('a+b')
    try:
        if sys.platform == 'win32':
            import msvcrt
            handle.seek(0, 2)
            if not handle.tell():
                handle.write(b'0'); handle.flush()
            handle.seek(0)
            msvcrt.locking(handle.fileno(), msvcrt.LK_NBLCK, 1)
        else:
            import fcntl
            fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError as exc:
        handle.close()
        raise RuntimeError('Constant Watch is already running for this data directory.') from exc
    return handle
