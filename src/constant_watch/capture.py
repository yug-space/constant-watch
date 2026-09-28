import asyncio
import json
import os
import sys
from pathlib import Path


def helper_path() -> Path:
    if getattr(sys, "frozen", False):
        default = Path(sys.executable).parents[3] / "Constant Watch Capture.app/Contents/MacOS/capture"
    else:
        default = Path(__file__).resolve().parents[2] / "build/Constant Watch Capture.app/Contents/MacOS/capture"
    return Path(os.environ.get("CONSTANT_WATCH_HELPER", str(default))).expanduser()


async def native(command: str = "capture", excluded: list[str] | None = None) -> dict:
    if sys.platform == "win32":
        from .windows_capture import capture
        return await capture(command, excluded)
    path = helper_path()
    if not path.exists():
        raise RuntimeError("Capture helper is missing. Run bash scripts/build-native.sh.")
    env = {**os.environ, "CW_EXCLUDED_APPS": "\n".join(excluded or [])}
    proc = await asyncio.create_subprocess_exec(str(path), command, env=env, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE)
    try:
        out, err = await asyncio.wait_for(proc.communicate(), timeout=20)
    except (TimeoutError, asyncio.CancelledError):
        if proc.returncode is None:
            proc.kill()
        await proc.communicate()
        raise
    if proc.returncode:
        raise RuntimeError(f"Capture helper exited {proc.returncode}: {err.decode()[:300]}")
    return json.loads(out)
