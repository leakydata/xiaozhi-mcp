# tools/graphiti_simple.py
from __future__ import annotations

import asyncio
import json
import os
from typing import Any, Dict, List, Optional
from contextlib import asynccontextmanager

from dotenv import load_dotenv

# Graphiti v3 SDK
from graphiti_core import Graphiti                    # core client
from graphiti_core.nodes import EpisodeType           # enums
from graphiti_core.search.search_config_recipes import NODE_HYBRID_SEARCH_RRF

# Notes:
# - We call Graphiti directly, not via its own MCP server, to avoid "MCP-in-MCP".
# - Each tool opens/closes its own Graphiti connection cleanly.
# - Tools are sync-entrypoints that run an async function via asyncio.run()
#   so FastMCP can call them like normal functions.

def register_graphiti_simple_tools(mcp) -> None:
    """
    Register Graphiti tools into the AggregateMCP server.

    Env vars (see Graphiti docs):
      OPENAI_API_KEY, MODEL_NAME
      NEO4J_URI, NEO4J_USER, NEO4J_PASSWORD
      GRAPHITI_GROUP_ID (optional)
    """

    load_dotenv()

    NEO4J_URI = os.environ.get("NEO4J_URI", "bolt://localhost:7687")
    NEO4J_USER = os.environ.get("NEO4J_USER", "neo4j")
    NEO4J_PASSWORD = os.environ.get("NEO4J_PASSWORD")
    MODEL_NAME = os.environ.get("MODEL_NAME", "gpt-4o-mini")
    GROUP_ID = os.environ.get("GRAPHITI_GROUP_ID", "default")

    # very light validation up-front
    if not NEO4J_PASSWORD:
        # Don’t crash import; surface error on first call instead
        pass

    @asynccontextmanager
    async def _client():
        if not (NEO4J_URI and NEO4J_USER and NEO4J_PASSWORD):
            raise RuntimeError("Graphiti not configured: set NEO4J_URI, NEO4J_USER, NEO4J_PASSWORD")

        client = Graphiti(NEO4J_URI, NEO4J_USER, NEO4J_PASSWORD, model_name=MODEL_NAME, group_id=GROUP_ID)
        try:
            yield client
        finally:
            # Graphiti client is async; always close cleanly
            try:
                await client.close()
            except Exception:
                pass

    # ------------- helpers -------------

    def _run(coro):
        # Run a one-shot async function safely
        return asyncio.run(coro)

    # ------------- tools -------------

    @mcp.tool()
    def graphiti_init(build_indices: bool = True) -> str:
        """
        Initialize Graphiti: optionally build indices/constraints (idempotent).
        """
        async def _go():
            async with _client() as g:
                if build_indices:
                    # Per docs: build indices & constraints once; safe to re-run. 
                    await g.build_indices_and_constraints()
            return "ok"
        return _run(_go())

    @mcp.tool()
    def graphiti_add_episode(
        content: str,
        description: str = "episode",
        reference_time_utc_iso: Optional[str] = None
    ) -> Dict[str, Any]:
        """
        Add a TEXT episode to the graph (entities & facts will be extracted).
        """
        from datetime import datetime, timezone

        async def _go():
            async with _client() as g:
                ref_time = None
                if reference_time_utc_iso:
                    # forgiving parse
                    ref_time = datetime.fromisoformat(reference_time_utc_iso.replace("Z", "+00:00"))
                else:
                    ref_time = datetime.now(timezone.utc)

                ep_uuid = await g.add_episode(
                    name=f"episode:{description}",
                    episode_body=content,
                    source=EpisodeType.text,
                    source_description=description,
                    reference_time=ref_time,
                )
                return {"episode_uuid": ep_uuid}
        return _run(_go())

    @mcp.tool()
    def graphiti_add_json(
        json_body: Dict[str, Any],
        description: str = "json-episode",
        reference_time_utc_iso: Optional[str] = None
    ) -> Dict[str, Any]:
        """
        Add a JSON episode to the graph.
        """
        from datetime import datetime, timezone

        async def _go():
            async with _client() as g:
                ref_time = None
                if reference_time_utc_iso:
                    ref_time = datetime.fromisoformat(reference_time_utc_iso.replace("Z", "+00:00"))
                else:
                    ref_time = datetime.now(timezone.utc)

                ep_uuid = await g.add_episode(
                    name=f"episode:{description}",
                    episode_body=json.dumps(json_body),
                    source=EpisodeType.json,
                    source_description=description,
                    reference_time=ref_time,
                )
                return {"episode_uuid": ep_uuid}
        return _run(_go())

    @mcp.tool()
    def graphiti_search_facts(query: str, center_node_uuid: Optional[str] = None, limit: int = 10) -> List[Dict[str, Any]]:
        """
        Hybrid search for facts/edges (same behavior as `graphiti.search(...)`).
        Optionally rerank using a center node UUID.
        """
        async def _go():
            async with _client() as g:
                results = await g.search(query, center_node_uuid=center_node_uuid)
                out: List[Dict[str, Any]] = []
                for r in results[: max(1, min(100, int(limit)))]:
                    out.append({
                        "uuid": getattr(r, "uuid", None),
                        "fact": getattr(r, "fact", None),
                        "valid_at": getattr(r, "valid_at", None),
                        "invalid_at": getattr(r, "invalid_at", None),
                        "source_node_uuid": getattr(r, "source_node_uuid", None),
                        "target_node_uuid": getattr(r, "target_node_uuid", None),
                    })
                return out
        return _run(_go())

    @mcp.tool()
    def graphiti_search_nodes(query: str, limit: int = 5) -> List[Dict[str, Any]]:
        """
        Node search using the standard RRF recipe (NODE_HYBRID_SEARCH_RRF).
        Returns node UUID, name, summary, labels, created_at, and attributes.
        """
        async def _go():
            async with _client() as g:
                cfg = NODE_HYBRID_SEARCH_RRF.model_copy(deep=True)
                cfg.limit = max(1, min(50, int(limit)))
                res = await g._search(query=query, config=cfg)
                out: List[Dict[str, Any]] = []
                for n in getattr(res, "nodes", []):
                    out.append({
                        "uuid": getattr(n, "uuid", None),
                        "name": getattr(n, "name", None),
                        "summary": getattr(n, "summary", None),
                        "labels": list(getattr(n, "labels", []) or []),
                        "created_at": getattr(n, "created_at", None),
                        "attributes": dict(getattr(n, "attributes", {}) or {}),
                    })
                return out
        return _run(_go())

    @mcp.tool()
    def graphiti_clear(really: bool = False) -> str:
        """
        Clear the entire knowledge graph for the current group_id. DANGEROUS.
        """
        async def _go():
            if not really:
                return "refused: set really=true to clear"
            async with _client() as g:
                await g.clear()
            return "cleared"
        return _run(_go())
