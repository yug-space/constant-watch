import json
from unittest.mock import patch
import httpx
import pytest
from constant_watch.config import Settings
from constant_watch.model import LocalModel


async def test_qwen_summary_uses_final_content_and_disables_thinking():
    def respond(request):
        body = json.loads(request.content)
        assert body['model'] == 'qwen3.5:0.8b'
        assert body['think'] is False
        assert body['options']['num_predict'] == 160
        return httpx.Response(200, json={'message': {'content': 'The launch review is Friday at 10 AM.', 'thinking': 'Internal reasoning must not be saved.'}})
    client = httpx.AsyncClient(transport=httpx.MockTransport(respond))
    with patch('constant_watch.model.httpx.AsyncClient', return_value=client):
        result = await LocalModel().summarize('Launch review Friday 10 AM.', 'TextEdit', 'Note', Settings().model)
    assert result == 'The launch review is Friday at 10 AM.'


async def test_empty_final_answer_is_not_replaced_with_reasoning():
    client = httpx.AsyncClient(transport=httpx.MockTransport(lambda _: httpx.Response(200, json={'message': {'content': '', 'thinking': 'unfinished'}})))
    with patch('constant_watch.model.httpx.AsyncClient', return_value=client):
        with pytest.raises(ValueError, match='empty summary'):
            await LocalModel().summarize('Note', 'TextEdit', 'Note', Settings().model)


async def test_model_status_reports_actual_installed_metadata():
    client = httpx.AsyncClient(transport=httpx.MockTransport(lambda _: httpx.Response(200, json={'models': [{'name': 'qwen3.5:0.8b', 'size': 1036034688, 'details': {'parameter_size': '0.8B'}}]})))
    with patch('constant_watch.model.httpx.AsyncClient', return_value=client):
        status = await LocalModel().status(Settings().model)
    assert status['available'] and status['parameter_size'] == '0.8B'
    assert status['download_bytes'] == 1036034688


async def test_prepare_skips_download_when_model_is_installed(tmp_path):
    from unittest.mock import AsyncMock
    from constant_watch.engine import Engine
    engine = Engine(tmp_path)
    engine.model.status = AsyncMock(return_value={'available': True})
    engine.model.pull = AsyncMock(side_effect=AssertionError('Downloaded an installed model'))
    engine.model.ensure_running = AsyncMock()
    engine.setup_model()
    await engine.setup_task
    assert engine.state['download']['fraction'] == 1
    assert not engine.state['download']['running']
    engine.model.pull.assert_not_called()
    engine.model.ensure_running.assert_not_called()


async def test_prepare_reports_real_failure_and_preserves_retry(tmp_path):
    from unittest.mock import AsyncMock
    from constant_watch.engine import Engine
    engine = Engine(tmp_path)
    engine.model.status = AsyncMock(return_value={'available': False})
    engine.model.ensure_running = AsyncMock()
    engine.model.pull = AsyncMock(side_effect=RuntimeError('Not enough disk space'))
    engine.setup_model()
    await engine.setup_task
    assert engine.state['download']['status'] == 'Not enough disk space'
    assert not engine.state['download']['running']
    engine.model.pull = AsyncMock()
    engine.setup_model()
    await engine.setup_task
    assert engine.state['download']['fraction'] == 1


async def test_incomplete_stream_is_not_reported_as_ready():
    client = httpx.AsyncClient(transport=httpx.MockTransport(lambda _: httpx.Response(200, content=b'{"status":"downloading","completed":50,"total":100}\n')))
    with patch('constant_watch.model.httpx.AsyncClient', return_value=client):
        with pytest.raises(RuntimeError, match='stopped before'):
            await LocalModel().pull('test', lambda value: None)


async def test_engine_already_running_is_not_started_again():
    from unittest.mock import AsyncMock
    model = LocalModel()
    model.status = AsyncMock(return_value={'runtime_running': True})
    with patch('constant_watch.model.asyncio.create_subprocess_exec', new_callable=AsyncMock) as start:
        await model.ensure_running()
        start.assert_not_called()


async def test_download_http_error_is_actionable_instead_of_stuck(tmp_path):
    from unittest.mock import AsyncMock
    from constant_watch.engine import Engine
    engine = Engine(tmp_path)
    engine.model.status = AsyncMock(return_value={'available': False})
    engine.model.ensure_running = AsyncMock()
    client = httpx.AsyncClient(transport=httpx.MockTransport(lambda _: httpx.Response(404, json={'error': 'Model not found. Check the model name.'})))
    with patch('constant_watch.model.httpx.AsyncClient', return_value=client):
        engine.setup_model()
        await engine.setup_task
    assert not engine.state['download']['running']
    assert '404' in engine.state['download']['status']
    assert 'Model not found' in engine.state['download']['status']
