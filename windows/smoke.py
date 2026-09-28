"""Exercise the actual frozen Windows executable with an isolated journal."""
import asyncio
from datetime import date
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import time
import urllib.request
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
import importlib.util
spec = importlib.util.spec_from_file_location('package_smoke', Path(__file__).resolve().parents[1] / 'scripts/smoke-package.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
exe = Path(sys.argv[1] if len(sys.argv)>1 else 'dist/Constant Watch/constant-watch-service.exe').resolve()
with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    env = {**os.environ, 'CONSTANT_WATCH_DATA': directory, 'PYTHONUTF8': '1'}
    env.pop('CONSTANT_WATCH_NATIVE_TOKEN', None)
    subprocess.run([str(exe), '--help'], env=env, check=True)
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', 0)); port = sock.getsockname()[1]
    process = subprocess.Popen([str(exe), 'serve', '--port', str(port)], env=env)
    try:
        base = f'http://127.0.0.1:{port}'
        for _ in range(120):
            if process.poll() is not None: raise RuntimeError('Frozen service exited')
            try:
                with urllib.request.urlopen(base + '/api/health', timeout=1) as response:
                    assert json.load(response)['application'] == 'constant-watch'
                    break
            except OSError: time.sleep(.25)
        else: raise RuntimeError('Frozen service startup timed out')
        with urllib.request.urlopen(base + '/api/status', timeout=30) as response:
            status = json.load(response)
            assert status['settings']['paused']
            assert status['platform'] == 'win32'
            assert 'error' not in status['permissions'], status['permissions']
        with urllib.request.urlopen(base + '/journal') as response:
            assert 'welcome-dialog' in response.read().decode()
        asyncio.run(module.check_mcp(exe, env, date.today().isoformat()))
        print('Windows frozen service, capture status, bundled UI and MCP verified.')
    finally:
        process.terminate(); process.wait(timeout=10)
