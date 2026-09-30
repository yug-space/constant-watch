"""Run macOS capture in the long-lived Swift app that owns its TCC permissions."""
import asyncio
import secrets


class NativeBridge:
    def __init__(self, timeout: float = 30):
        self.timeout = timeout
        self.pending = {}
        self.jobs = {}
        self.ready = asyncio.Event()

    async def call(self, command="capture", excluded=None, payload=None):
        if len(self.pending) >= 32:
            raise RuntimeError("Native capture is busy. Reopen Constant Watch.")
        job_id = secrets.token_hex(16)
        future = asyncio.get_running_loop().create_future()
        self.pending[job_id] = future
        self.jobs[job_id] = {"id": job_id, "command": command, "excluded": excluded or [], "payload": payload or {}}
        self.ready.set()
        try:
            return await asyncio.wait_for(future, self.timeout)
        except TimeoutError as exc:
            raise RuntimeError("The native app is not responding. Reopen Constant Watch.") from exc
        finally:
            self.pending.pop(job_id, None)
            self.jobs.pop(job_id, None)

    async def next(self):
        while not self.jobs:
            self.ready.clear()
            try:
                await asyncio.wait_for(self.ready.wait(), 15)
            except TimeoutError:
                return {}
        return self.jobs.pop(next(iter(self.jobs)))

    def complete(self, job_id, result):
        future = self.pending.get(job_id)
        if future is None or future.done() or job_id in self.jobs:
            return False
        future.set_result(result)
        return True

    def close(self):
        for future in self.pending.values():
            if not future.done():
                future.cancel()
