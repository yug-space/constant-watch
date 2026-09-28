"""Run the bounded Windows UI Automation / Windows OCR helper in isolation."""
import asyncio
import json
import os
from pathlib import Path
import subprocess


async def capture(command='capture', excluded=None):
    script = Path(__file__).with_name('windows_capture.ps1')
    powershell = Path(os.environ.get('SystemRoot', r'C:\Windows')) / 'System32/WindowsPowerShell/v1.0/powershell.exe'
    process = await asyncio.create_subprocess_exec(
        str(powershell), '-NoLogo', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
        '-File', str(script), '-Command', command,
        env={**os.environ, 'CW_EXCLUDED_APPS': '\n'.join(excluded or [])},
        stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE,
        creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0),
    )
    try:
        out, err = await asyncio.wait_for(process.communicate(), timeout=25)
    except (TimeoutError, asyncio.CancelledError):
        if process.returncode is None:
            process.kill()
        await process.communicate()
        raise
    if process.returncode:
        raise RuntimeError('Windows capture failed: ' + err.decode('utf-8', errors='replace')[:300])
    return json.loads(out.decode('utf-8-sig'))
