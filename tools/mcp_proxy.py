# tools/mcp_proxy.py
# Generic pass-through tools so XiaoZhi can use ANY MCP server (Graphiti, etc.)
# Requires: pip install "mcp[cli]" pydantic

from typing import Any, Dict, List
import asyncio
from pydantic import BaseModel, Field
from mcp import ClientSession
from mcp.types import TextContent
from mcp.client.sse import sse_client
from mcp.client.streamable_http import streamablehttp_client

def _pick_transport(url: str):
    """
    Return an async context manager yielding (read, write, extra) for the given URL.
    Heuristic:
      - URLs ending in /sse  -> SSE transport
      - Otherwise            -> Streamable HTTP transport (/mcp)
    """
    u = url.rstrip("/")
    if u.endswith("/sse"):
        return sse_client(url=u)
    return streamablehttp_client(u)

async def _list_tools(url: str) -> List[Dict[str, Any]]:
    async with _pick_transport(url) as (read, write, *_):
        async with ClientSession(read, write) as session:
            await session.initialize()
            resp = await session.list_tools()
            return [t.model_dump() for t in resp.tools]

async def _call(url: str, tool_name: str, args: Dict[str, Any]):
    async with _pick_transport(url) as (read, write, *_):
        async with ClientSession(read, write) as session:
            await session.initialize()
            res = await session.call_tool(tool_name, arguments=args)
            # Try to return structured content first, otherwise text, otherwise a simple OK.
            if res.structuredContent is not None:
                return res.structuredContent
            if res.content:
                first = res.content[0]
                if isinstance(first, TextContent):
                    return {"text": first.text}
            return {"ok": True}

# FastMCP-style registration
def register_mcp_proxy_tools(mcp):
    @mcp.tool(
        name="mcp_proxy_list_tools",
        description="List tools on an upstream MCP server (Graphiti, etc.)."
    )
    def mcp_proxy_list_tools(server_url: str = Field(..., description="e.g. http://localhost:8001/sse or http://localhost:8001/mcp")) -> Dict[str, Any]:
        return {"tools": asyncio.run(_list_tools(server_url))}

    @mcp.tool(
        name="mcp_proxy_call_tool",
        description="Call a tool on an upstream MCP server (no per-tool wrapper needed)."
    )
    def mcp_proxy_call_tool(
        server_url: str = Field(..., description="Upstream MCP endpoint"),
        tool_name: str = Field(..., description="Exact tool name on the upstream server"),
        args: Dict[str, Any] = Field(default_factory=dict, description="Arguments for that tool")
    ) -> Dict[str, Any]:
        return {"result": asyncio.run(_call(server_url, tool_name, args))}
