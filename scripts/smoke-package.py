"""Exercise the packaged service in an isolated data directory, without screen capture."""
import argparse
import asyncio
from datetime import date
import json
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import time
import urllib.request

from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client


async def check_mcp(executable, environment, day):
    server = StdioServerParameters(command=str(executable), args=['mcp'], env=environment)
    with tempfile.TemporaryFile(mode='w+') as errors:
        await check_mcp_session(server, errors, day)
        errors.seek(0)
        messages = errors.read()
        assert 'Traceback' not in messages, messages


async def check_mcp_session(server, errors, day):
    async with stdio_client(server, errlog=errors) as (read, write):
        async with ClientSession(read, write) as session:
            await session.initialize()
            names = {tool.name for tool in (await session.list_tools()).tools}
            assert {'read_day_flow', 'ask_memory', 'read_observation', 'read_review'} <= names
            result = await session.call_tool('read_day_flow', {'day': day})
            assert not result.isError
            review = await session.call_tool('read_review', {'start': day, 'end': day})
            assert not review.isError and 'Context to report' in str(review.content)
            resource = await session.read_resource('watch://apps')
            assert resource.contents
            print(f'MCP: handshake, {len(names)} tools, daily-flow call, apps resource passed')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('app', type=Path)
    args = parser.parse_args()
    app = args.app.resolve()
    executable = app / 'Contents/Helpers/Runtime.app/Contents/MacOS/constant-watch'
    assert executable.is_file()
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    for path in app.rglob('*'):
        if path.is_symlink():
            assert path.resolve().is_relative_to(app), f'External bundle symlink: {path}'
    with tempfile.TemporaryDirectory(prefix='constant-watch-package-') as directory:
        root = Path(directory)
        env = {**os.environ, 'PATH': '/usr/bin:/bin', 'CONSTANT_WATCH_DATA': str(root / 'data')}
        for name in ('PYTHONHOME', 'PYTHONPATH', 'VIRTUAL_ENV', 'CONSTANT_WATCH_NATIVE_TOKEN', 'CONSTANT_WATCH_HELPER'):
            env.pop(name, None)
        subprocess.run([str(executable), '--help'], env=env, cwd=root, check=True, stdout=subprocess.DEVNULL)
        with socket.socket() as sock:
            sock.bind(('127.0.0.1', 0))
            port = sock.getsockname()[1]
        # The native bridge token prevents standalone capture, and fresh settings are paused.
        service_env = {**env, 'CONSTANT_WATCH_NATIVE_TOKEN': 'package-smoke-no-capture'}
        with (root / 'service.log').open('w+') as log:
            process = subprocess.Popen([str(executable), 'serve', '--port', str(port)], cwd=root, env=service_env, stdout=log, stderr=log)
            try:
                base = f'http://127.0.0.1:{port}'
                for _ in range(100):
                    if process.poll() is not None:
                        log.seek(0); raise RuntimeError(log.read())
                    try:
                        with urllib.request.urlopen(base + '/', timeout=1) as response:
                            assert response.status == 200 and b'<html' in response.read().lower()
                        break
                    except OSError:
                        time.sleep(0.1)
                else:
                    raise RuntimeError('Packaged service did not start')
                import re
                html = urllib.request.urlopen(base + '/').read().decode()
                assets = re.findall(r'(?:src|href)="(/[^"#]+\.(?:js|css))"', html)
                assert assets, 'No bundled web assets found'
                for asset in assets:
                    with urllib.request.urlopen(base + asset) as response:
                        assert response.status == 200 and response.read()
                request = urllib.request.Request(base + '/api/settings', data=json.dumps({'paused': True}).encode(), method='PUT', headers={'Content-Type': 'application/json', 'X-Constant-Watch': 'local'})
                with urllib.request.urlopen(request) as response:
                    assert response.status == 200
                review = json.load(urllib.request.urlopen(base + '/api/review?start=2026-09-21&end=2026-09-27'))
                assert review['captures'] == 0 and len(review['days']) == 7
                print('Service: relocated launch, bundled Python, HTTP, web assets, settings write passed')
                asyncio.run(check_mcp(executable, env, date.today().isoformat()))
            finally:
                process.terminate()
                try: process.wait(timeout=10)
                except subprocess.TimeoutExpired: process.kill(); process.wait()
    print('PASS: standalone package smoke test')


if __name__ == '__main__':
    main()
