"""Exercise real Streamable HTTP and the configured rootless CMake sandbox."""

import argparse
import asyncio
import os
from pathlib import Path
from uuid import uuid4

import httpx
from mcp import ClientSession
from mcp.client.streamable_http import streamable_http_client


async def acceptance(endpoint: str, token: str) -> None:
    project = f"queue_{uuid4().hex[:8]}"
    fixture = Path(__file__).parent / "fixtures" / "queue"
    async with httpx.AsyncClient(headers={"Authorization": f"Bearer {token}"}, timeout=150) as http:
        async with streamable_http_client(endpoint, http_client=http) as (read, write, _):
            async with ClientSession(read, write) as session:
                await session.initialize()
                tools = await session.list_tools()
                assert {"get_system_info", "create_project", "write_file", "compile_project", "run_tests"} <= {
                    entry.name for entry in tools.tools
                }

                async def call(tool: str, **arguments) -> dict:
                    result = await session.call_tool(tool, arguments)
                    if result.isError:
                        raise RuntimeError(f"{tool}: {result.content}")
                    assert result.structuredContent is not None
                    print(f"{tool}: {result.structuredContent.get('stage', 'ok')}")
                    return result.structuredContent

                await call("get_system_info")
                await call("create_project", name=project)
                await call("write_file", path=f"{project}/CMakeLists.txt",
                           content=(fixture / "CMakeLists.txt").read_text())
                await call("write_file", path=f"{project}/queue_test.cpp",
                           content="int main() { return intentionally_missing_symbol; }\n")
                broken = await call("compile_project", name=project)
                assert broken["ok"] is False and broken["stage"] == "build", broken
                assert "intentionally_missing_symbol" in broken["output"], broken

                await call("write_file", path=f"{project}/queue_test.cpp",
                           content=(fixture / "queue_test.cpp").read_text())
                compiled = await call("compile_project", name=project)
                assert compiled["ok"] and compiled["stage"] == "build", compiled
                tested = await call("run_tests", name=project)
                assert tested["ok"] and tested["stage"] == "test", tested
                assert "producer_consumer_queue" in tested["output"], tested
                print(tested["output"])
                print(f"Acceptance passed in workspace/{project}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("endpoint")
    args = parser.parse_args()
    token = os.environ.get("PIAGENT_TOKEN")
    if not token:
        parser.error("Set PIAGENT_TOKEN in the environment")
    asyncio.run(acceptance(args.endpoint, token))


if __name__ == "__main__":
    main()
