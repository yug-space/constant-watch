import os
from pathlib import Path
import sys
from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client
from constant_watch.store import Store
from test_store import capture


async def test_stdio_mcp_handshake_tools_and_resources(tmp_path):
    store = Store(tmp_path)
    row_id = store.add(capture())
    day = store.get(row_id)["day"]
    server = StdioServerParameters(command=sys.executable, args=["-m","constant_watch.cli","mcp"], env={**os.environ,"CONSTANT_WATCH_DATA":str(tmp_path)})
    async with stdio_client(server) as (read, write):
        async with ClientSession(read, write) as session:
            await session.initialize()
            tools = await session.list_tools()
            assert {t.name for t in tools.tools} == {"list_apps","search_screen_memory","recent_activity","read_app_day","read_day_flow","day_sessions","ask_memory","list_topics","read_topic","read_observation","read_review","list_meetings","read_meeting","search_meetings","meeting_context"}
            result = await session.call_tool("search_screen_memory", {"query":"alpha"})
            assert not result.isError
            assert "Milestone alpha" in str(result.content)
            result = await session.call_tool("read_app_day", {"app_id":"com.example.Editor","day":day})
            assert "Accessibility text" in str(result.content)
            resources = await session.list_resources()
            assert str(resources.resources[0].uri) == "watch://apps"
            result = await session.read_resource("watch://apps")
            assert "com.example.Editor" in str(result.contents)
            result = await session.call_tool("read_day_flow", {"day":day})
            assert not result.isError and "Daily flow" in str(result.content)
            result = await session.call_tool("read_review", {"start":day,"end":day})
            assert not result.isError and "Context to report" in str(result.content)
            result = await session.call_tool("day_sessions", {"day":day})
            assert not result.isError and "total_sessions" in str(result.content)
            result = await session.read_resource(f"watch://day/{day}")
            assert "Daily flow" in str(result.contents)

            answer = await session.call_tool("ask_memory", {"question":"When does alpha ship?"})
            assert not answer.isError and "Friday" in str(answer.content)
            cited = await session.call_tool("read_observation", {"observation_id": row_id})
            assert not cited.isError and "ax_text" in str(cited.content)
            evidence = await session.read_resource(f"watch://observation/{row_id}")
            assert "Milestone alpha" in str(evidence.contents)
            topics = await session.call_tool("list_topics", {})
            assert not topics.isError and "planning" in str(topics.content)
            topic = await session.call_tool("read_topic", {"key":"planning"})
            assert not topic.isError and "sources" in str(topic.content)
