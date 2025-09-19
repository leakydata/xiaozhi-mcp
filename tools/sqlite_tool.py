# tools/sqlite_tool.py
from __future__ import annotations
import os
import sqlite3
from typing import Any, Dict, List
from contextlib import contextmanager

def register_sqlite_tools(mcp, *, db_path: str | None = None) -> None:
    """
    Register three SQLite tools on the given FastMCP instance.
    Each tool uses a brand-new SQLite connection that is closed on exit.
    DB path comes from arg `db_path` or env var SQLITE_DB (default: demo.db).
    """
    DB = db_path or os.getenv("SQLITE_DB", "demo.db")

    @contextmanager
    def _connect():
        # Fresh connection every time
        conn = sqlite3.connect(DB, timeout=30)
        try:
            # sensible defaults per-connection
            conn.row_factory = sqlite3.Row
            conn.execute("PRAGMA foreign_keys=ON")
            conn.execute("PRAGMA busy_timeout=30000")
            # WAL helps if anything else might read concurrently
            try:
                conn.execute("PRAGMA journal_mode=WAL")
                conn.execute("PRAGMA synchronous=NORMAL")
            except Exception:
                # not fatal if the FS/SQLite build doesn't support it
                pass
            yield conn
            # commit if there were writes (no-op for read-only)
            conn.commit()
        except Exception:
            # rollback on error to avoid lingering write locks
            try:
                conn.rollback()
            except Exception:
                pass
            raise
        finally:
            try:
                conn.close()
            except Exception:
                pass

    def _rows_to_dicts(rows: List[sqlite3.Row]) -> List[Dict[str, Any]]:
        return [dict(r) for r in rows]

    @mcp.tool()
    def sqlite_init_demo() -> str:
        """Create demo table and seed two rows."""
        with _connect() as conn:
            cur = conn.cursor()
            cur.execute("""
                CREATE TABLE IF NOT EXISTS items (
                    id INTEGER PRIMARY KEY,
                    name TEXT,
                    price REAL
                )
            """)
            cur.executemany(
                "INSERT INTO items(name, price) VALUES (?, ?)",
                [("widget", 9.99), ("gizmo", 14.95)],
            )
            return "ok"

    @mcp.tool()
    def sqlite_list_tables() -> List[str]:
        """List tables in the SQLite database."""
        with _connect() as conn:
            cur = conn.cursor()
            cur.execute("SELECT name FROM sqlite_master WHERE type='table' ORDER BY 1")
            return [row["name"] for row in cur.fetchall()]

    @mcp.tool()
    def sqlite_run_sql(query: str, limit: int = 100) -> List[Dict[str, Any]]:
        """
        Run a SELECT (or WITH … SELECT) query; return up to `limit` rows as JSON.
        Opens and closes a fresh connection for every call.
        """
        q = (query or "").strip().rstrip(";")
        ql = q.lower()
        #if not (ql.startswith("select") or ql.startswith("with")):
        #    raise ValueError("Only SELECT/CTE queries are allowed.")
        lim = max(1, min(int(limit), 10_000))

        with _connect() as conn:
            cur = conn.cursor()
            cur.execute(q)
            rows = cur.fetchmany(lim)
            return _rows_to_dicts(rows)


