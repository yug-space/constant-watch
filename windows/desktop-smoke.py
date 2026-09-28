"""Verify the frozen WebView2 window loads the local UI on the Windows runner."""
import os
from pathlib import Path
import subprocess
import tempfile
import time
exe = Path('dist/Constant Watch/constant-watch.exe').resolve()
with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    process = subprocess.Popen([str(exe)], env={**os.environ, 'CONSTANT_WATCH_DATA': directory})
    try:
        for _ in range(120):
            if process.poll() is not None:
                raise RuntimeError('Desktop exited before displaying the UI')
            log = root/'desktop.log'
            if log.exists() and 'Desktop interface loaded' in log.read_text(encoding='utf-8',errors='replace'):
                break
            time.sleep(.5)
        else:
            raise RuntimeError(log.read_text(encoding='utf-8',errors='replace') if log.exists() else 'No desktop log')
        assert (root/'mcp-config.json').exists()
        print('Frozen Windows desktop: WebView2 loaded the local journal; MCP config created.')
    finally:
        subprocess.run(['taskkill','/PID',str(process.pid),'/T','/F'],check=False,capture_output=True)
        process.wait(timeout=10)
