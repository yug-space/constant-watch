"""Windows desktop window with an owned, loopback-only service process."""
import ctypes
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import time
import urllib.request
from .config import data_dir
from .platform_support import acquire_lock


def main():
    root = data_dir()
    try:
        lock = acquire_lock(root / 'desktop.lock')
    except RuntimeError:
        ctypes.windll.user32.MessageBoxW(0, 'Constant Watch is already open. Find it in your taskbar.', 'Constant Watch', 64)
        return
    service = Path(sys.executable).with_name('constant-watch-service.exe')
    env = {**os.environ, 'CONSTANT_WATCH_DATA': str(root), 'PYTHONUTF8': '1'}
    env.pop('CONSTANT_WATCH_NATIVE_TOKEN', None)
    env.pop('CONSTANT_WATCH_HELPER', None)
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', 0))
        port = sock.getsockname()[1]
    config = {'mcpServers': {'constant-watch': {'command': str(service), 'args': ['mcp'], 'env': {'CONSTANT_WATCH_DATA': str(root)}}}}
    (root / 'mcp-config.json').write_text(json.dumps(config, indent=2), encoding='utf-8')
    process = None
    try:
        with (root / 'desktop.log').open('a', encoding='utf-8') as log:
            process = subprocess.Popen([str(service), 'serve', '--port', str(port)], env=env,
                stdout=log, stderr=log, creationflags=subprocess.CREATE_NO_WINDOW)
            base = f'http://127.0.0.1:{port}'
            for _ in range(120):
                if process.poll() is not None:
                    raise RuntimeError('The local service could not start. See desktop.log in ' + str(root))
                try:
                    with urllib.request.urlopen(base + '/api/health', timeout=1) as response:
                        if json.load(response).get('application') == 'constant-watch':
                            break
                except OSError:
                    time.sleep(0.25)
            else:
                raise RuntimeError('The local service took too long to start.')
            import webview
            webview.settings['ALLOW_DOWNLOADS'] = True
            webview.settings['ALLOW_FILE_URLS'] = False
            window = webview.create_window('Constant Watch — Screen memory', base + '/journal', width=1200, height=820,
                min_size=(900, 640), background_color='#ffffff', confirm_close=True)
            def loaded():
                log.write('Desktop interface loaded\n'); log.flush()
            window.events.loaded += loaded
            webview.start(gui='edgechromium', private_mode=True)
    except Exception as exc:
        ctypes.windll.user32.MessageBoxW(0, str(exc) + '\n\nWindows 11 requires Microsoft Edge WebView2 Runtime. Install it from Microsoft if the desktop window cannot open.', 'Constant Watch needs attention', 16)
    finally:
        if process and process.poll() is None:
            # TerminateProcess does not run the Python service's finally block on Windows.
            # Finalize WAV files and persist the meeting before stopping the child.
            try:
                request = urllib.request.Request(base + '/api/shutdown-workers', data=b'', method='POST', headers={'X-Constant-Watch': 'local'})
                with urllib.request.urlopen(request, timeout=20):
                    pass
            except OSError:
                pass
            process.terminate()
            try: process.wait(timeout=5)
            except subprocess.TimeoutExpired: process.kill(); process.wait()
        lock.close()
