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
