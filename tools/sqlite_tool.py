# tools/sqlite_tool.py
from __future__ import annotations
import os
import sqlite3
import json
import csv
import io
import re
from typing import Any, Dict, List, Optional, Union, Tuple
from contextlib import contextmanager
from datetime import datetime
import tempfile
import shutil

def register_sqlite_tools(mcp, *, db_path: str | None = None) -> None:
    """
    Register comprehensive SQLite tools on the given FastMCP instance.
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

    def _validate_sql_query(query: str, allowed_operations: List[str] = None) -> bool:
        """Validate SQL query for security and allowed operations"""
        if not query or not query.strip():
            return False
        
        query_lower = query.strip().lower()
        
        # Check for dangerous operations
        dangerous_patterns = [
            r'\b(drop|delete|truncate|alter|create|insert|update)\b',
            r'\b(attach|detach)\b',
            r'\b(pragma)\b',
            r'--',  # SQL comments
            r'/\*.*?\*/',  # Block comments
        ]
        
        if allowed_operations is None:
            allowed_operations = ['select', 'with']
        
        # Check if query starts with allowed operation
        if not any(query_lower.startswith(op) for op in allowed_operations):
            return False
            
        # Check for dangerous patterns
        for pattern in dangerous_patterns:
            if re.search(pattern, query_lower, re.IGNORECASE):
                return False
                
        return True

    # ==================== BASIC OPERATIONS ====================

    @mcp.tool()
    def sqlite_init_demo() -> str:
        """Create demo table and seed two rows."""
        with _connect() as conn:
            cur = conn.cursor()
            cur.execute("""
                CREATE TABLE IF NOT EXISTS items (
                    id INTEGER PRIMARY KEY,
                    name TEXT,
                    price REAL,
                    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
                )
            """)
            cur.executemany(
                "INSERT OR IGNORE INTO items(name, price) VALUES (?, ?)",
                [("widget", 9.99), ("gizmo", 14.95)],
            )
            return "Demo database initialized successfully"

    @mcp.tool()
    def sqlite_list_tables() -> List[str]:
        """List all tables in the SQLite database."""
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
        if not _validate_sql_query(q, ['select', 'with']):
            raise ValueError("Only SELECT/CTE queries are allowed and query must be safe.")
        
        lim = max(1, min(int(limit), 10_000))

        with _connect() as conn:
            cur = conn.cursor()
            cur.execute(q)
            rows = cur.fetchmany(lim)
            return _rows_to_dicts(rows)

    @mcp.tool()
    def sqlite_execute_ddl(query: str) -> str:
        """
        Execute DDL (Data Definition Language) statements like CREATE, DROP, ALTER.
        Use this for table creation, dropping, and schema modifications.
        """
        q = (query or "").strip().rstrip(";")
        if not q:
            raise ValueError("Query cannot be empty")
        
        # Allow DDL operations but still validate for safety
        query_lower = q.lower()
        allowed_ddl = ['create', 'drop', 'alter', 'reindex']
        
        if not any(query_lower.startswith(op) for op in allowed_ddl):
            raise ValueError("Only DDL operations (CREATE, DROP, ALTER, REINDEX) are allowed")
        
        # Block dangerous operations
        dangerous_patterns = [
            r'\b(attach|detach)\b',
            r'\b(pragma)\b',
            r'--',  # SQL comments
            r'/\*.*?\*/',  # Block comments
        ]
        
        for pattern in dangerous_patterns:
            if re.search(pattern, query_lower, re.IGNORECASE):
                raise ValueError("Query contains potentially dangerous operations")
        
        with _connect() as conn:
            cur = conn.cursor()
            cur.execute(q)
            return f"DDL statement executed successfully: {query_lower.split()[0].upper()}"

    # ==================== SCHEMA MANAGEMENT ====================

    @mcp.tool()
    def sqlite_describe_table(table_name: str) -> Dict[str, Any]:
        """Get detailed information about a table's schema."""
        with _connect() as conn:
            cur = conn.cursor()
            
            # Get table info
            cur.execute("PRAGMA table_info(?)", (table_name,))
            columns = _rows_to_dicts(cur.fetchall())
            
            # Get indexes
            cur.execute("PRAGMA index_list(?)", (table_name,))
            indexes = _rows_to_dicts(cur.fetchall())
            
            # Get foreign keys
            cur.execute("PRAGMA foreign_key_list(?)", (table_name,))
            foreign_keys = _rows_to_dicts(cur.fetchall())
            
            # Get table SQL
            cur.execute("SELECT sql FROM sqlite_master WHERE type='table' AND name=?", (table_name,))
            table_sql = cur.fetchone()
            
            return {
                "table_name": table_name,
                "columns": columns,
                "indexes": indexes,
                "foreign_keys": foreign_keys,
                "create_sql": table_sql["sql"] if table_sql else None
            }

    @mcp.tool()
    def sqlite_list_columns(table_name: str) -> List[Dict[str, Any]]:
        """List all columns in a table with their details."""
        with _connect() as conn:
            cur = conn.cursor()
            cur.execute("PRAGMA table_info(?)", (table_name,))
            return _rows_to_dicts(cur.fetchall())

    @mcp.tool()
    def sqlite_list_indexes(table_name: str = None) -> List[Dict[str, Any]]:
        """List all indexes, optionally filtered by table."""
        with _connect() as conn:
            cur = conn.cursor()
            if table_name:
                cur.execute("PRAGMA index_list(?)", (table_name,))
            else:
                cur.execute("SELECT name FROM sqlite_master WHERE type='index' AND name NOT LIKE 'sqlite_%'")
                index_names = [row["name"] for row in cur.fetchall()]
                result = []
                for idx_name in index_names:
                    cur.execute("PRAGMA index_info(?)", (idx_name,))
                    result.extend(_rows_to_dicts(cur.fetchall()))
                return result
            return _rows_to_dicts(cur.fetchall())

    @mcp.tool()
    def sqlite_get_schema() -> Dict[str, Any]:
        """Get complete database schema information."""
        with _connect() as conn:
            cur = conn.cursor()
            
            # Get all tables
            cur.execute("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")
            tables = [row["name"] for row in cur.fetchall()]
            
            schema = {"tables": {}}
            
            for table in tables:
                schema["tables"][table] = sqlite_describe_table(table)
            
            return schema

    # ==================== DATA MANIPULATION ====================

    @mcp.tool()
    def sqlite_insert(table_name: str, data: Dict[str, Any]) -> str:
        """Insert a single row into a table."""
        if not data:
            raise ValueError("Data cannot be empty")
        
        with _connect() as conn:
            cur = conn.cursor()
            columns = list(data.keys())
            placeholders = ", ".join(["?" for _ in columns])
            values = list(data.values())
            
            query = f"INSERT INTO {table_name} ({', '.join(columns)}) VALUES ({placeholders})"
            cur.execute(query, values)
            return f"Inserted row with ID: {cur.lastrowid}"

    @mcp.tool()
    def sqlite_insert_many(table_name: str, data: List[Dict[str, Any]]) -> str:
        """Insert multiple rows into a table."""
        if not data:
            raise ValueError("Data cannot be empty")
        
        with _connect() as conn:
            cur = conn.cursor()
            columns = list(data[0].keys())
            placeholders = ", ".join(["?" for _ in columns])
            
            query = f"INSERT INTO {table_name} ({', '.join(columns)}) VALUES ({placeholders})"
            values = [[row[col] for col in columns] for row in data]
            
            cur.executemany(query, values)
            return f"Inserted {len(data)} rows"

    @mcp.tool()
    def sqlite_update(table_name: str, data: Dict[str, Any], where_clause: str, where_params: List[Any] = None) -> str:
        """Update rows in a table based on a WHERE clause."""
        if not data:
            raise ValueError("Data cannot be empty")
        
        with _connect() as conn:
            cur = conn.cursor()
            set_clause = ", ".join([f"{col} = ?" for col in data.keys()])
            values = list(data.values())
            
            if where_params:
                values.extend(where_params)
            
            query = f"UPDATE {table_name} SET {set_clause} WHERE {where_clause}"
            cur.execute(query, values)
            return f"Updated {cur.rowcount} rows"

    @mcp.tool()
    def sqlite_delete(table_name: str, where_clause: str, where_params: List[Any] = None) -> str:
        """Delete rows from a table based on a WHERE clause."""
        with _connect() as conn:
            cur = conn.cursor()
            query = f"DELETE FROM {table_name} WHERE {where_clause}"
            cur.execute(query, where_params or [])
            return f"Deleted {cur.rowcount} rows"

    @mcp.tool()
    def sqlite_upsert(table_name: str, data: Dict[str, Any], conflict_columns: List[str] = None) -> str:
        """Insert or update a row (UPSERT operation)."""
        if not data:
            raise ValueError("Data cannot be empty")
        
        with _connect() as conn:
            cur = conn.cursor()
            columns = list(data.keys())
            placeholders = ", ".join(["?" for _ in columns])
            values = list(data.values())
            
            if conflict_columns:
                # Use specified conflict resolution columns
                conflict_clause = f"ON CONFLICT ({', '.join(conflict_columns)}) DO UPDATE SET "
                update_clause = ", ".join([f"{col} = excluded.{col}" for col in columns if col not in conflict_columns])
                query = f"INSERT INTO {table_name} ({', '.join(columns)}) VALUES ({placeholders}) {conflict_clause}{update_clause}"
            else:
                # Use REPLACE (SQLite's built-in upsert)
                query = f"INSERT OR REPLACE INTO {table_name} ({', '.join(columns)}) VALUES ({placeholders})"
            
            cur.execute(query, values)
            return f"Upserted row with ID: {cur.lastrowid}"

    # ==================== ADVANCED QUERIES ====================

    @mcp.tool()
    def sqlite_count_rows(table_name: str, where_clause: str = None, where_params: List[Any] = None) -> int:
        """Count rows in a table, optionally with a WHERE clause."""
        with _connect() as conn:
            cur = conn.cursor()
            query = f"SELECT COUNT(*) as count FROM {table_name}"
            if where_clause:
                query += f" WHERE {where_clause}"
                cur.execute(query, where_params or [])
            else:
                cur.execute(query)
            
            return cur.fetchone()["count"]

    @mcp.tool()
    def sqlite_aggregate(table_name: str, column: str, operation: str = "SUM", where_clause: str = None, where_params: List[Any] = None) -> float:
        """Perform aggregation operations (SUM, AVG, MIN, MAX, COUNT) on a column."""
        valid_operations = ["SUM", "AVG", "MIN", "MAX", "COUNT"]
        if operation.upper() not in valid_operations:
            raise ValueError(f"Operation must be one of: {valid_operations}")
        
        with _connect() as conn:
            cur = conn.cursor()
            query = f"SELECT {operation.upper()}({column}) as result FROM {table_name}"
            if where_clause:
                query += f" WHERE {where_clause}"
                cur.execute(query, where_params or [])
            else:
                cur.execute(query)
            
            result = cur.fetchone()["result"]
            return float(result) if result is not None else 0.0

    @mcp.tool()
    def sqlite_join_tables(left_table: str, right_table: str, join_type: str = "INNER", 
                          on_clause: str = None, columns: List[str] = None, limit: int = 100) -> List[Dict[str, Any]]:
        """Perform JOIN operations between tables."""
        valid_joins = ["INNER", "LEFT", "RIGHT", "FULL OUTER"]
        if join_type.upper() not in valid_joins:
            raise ValueError(f"Join type must be one of: {valid_joins}")
        
        if not on_clause:
            raise ValueError("ON clause is required for JOIN operations")
        
        with _connect() as conn:
            cur = conn.cursor()
            
            if columns:
                select_clause = ", ".join(columns)
            else:
                select_clause = "*"
            
            query = f"SELECT {select_clause} FROM {left_table} {join_type.upper()} JOIN {right_table} ON {on_clause} LIMIT {limit}"
            cur.execute(query)
            rows = cur.fetchall()
            return _rows_to_dicts(rows)

    @mcp.tool()
    def sqlite_group_by(table_name: str, group_columns: List[str], aggregate_columns: List[str], 
                       aggregate_functions: List[str] = None, where_clause: str = None, 
                       where_params: List[Any] = None, having_clause: str = None, 
                       having_params: List[Any] = None, limit: int = 100) -> List[Dict[str, Any]]:
        """Perform GROUP BY operations with aggregations."""
        if not group_columns:
            raise ValueError("Group columns cannot be empty")
        
        if not aggregate_functions:
            aggregate_functions = ["COUNT"] * len(aggregate_columns)
        
        if len(aggregate_columns) != len(aggregate_functions):
            raise ValueError("Number of aggregate columns must match number of aggregate functions")
        
        with _connect() as conn:
            cur = conn.cursor()
            
            select_parts = group_columns.copy()
            for col, func in zip(aggregate_columns, aggregate_functions):
                select_parts.append(f"{func.upper()}({col}) as {func.lower()}_{col}")
            
            query = f"SELECT {', '.join(select_parts)} FROM {table_name}"
            
            if where_clause:
                query += f" WHERE {where_clause}"
            
            query += f" GROUP BY {', '.join(group_columns)}"
            
            if having_clause:
                query += f" HAVING {having_clause}"
            
            query += f" LIMIT {limit}"
            
            params = []
            if where_params:
                params.extend(where_params)
            if having_params:
                params.extend(having_params)
            
            cur.execute(query, params)
            rows = cur.fetchall()
            return _rows_to_dicts(rows)

    # ==================== DATABASE OPERATIONS ====================

    @mcp.tool()
    def sqlite_backup(backup_path: str = None) -> str:
        """Create a backup of the database."""
        if not backup_path:
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            backup_path = f"{DB}.backup_{timestamp}"
        
        with _connect() as conn:
            backup_conn = sqlite3.connect(backup_path)
            conn.backup(backup_conn)
            backup_conn.close()
        
        return f"Database backed up to: {backup_path}"

    @mcp.tool()
    def sqlite_restore(backup_path: str) -> str:
        """Restore database from a backup file."""
        if not os.path.exists(backup_path):
            raise ValueError(f"Backup file not found: {backup_path}")
        
        # Create a temporary backup of current database
        temp_backup = f"{DB}.temp_backup_{datetime.now().strftime('%Y%m%d_%H%M%S')}"
        sqlite_backup(temp_backup)
        
        try:
            # Close any existing connections and copy backup
            shutil.copy2(backup_path, DB)
            return f"Database restored from: {backup_path}"
        except Exception as e:
            # Restore from temp backup if something goes wrong
            shutil.copy2(temp_backup, DB)
            raise Exception(f"Restore failed, original database preserved: {e}")
        finally:
            # Clean up temp backup
            if os.path.exists(temp_backup):
                os.remove(temp_backup)

    @mcp.tool()
    def sqlite_vacuum() -> str:
        """Vacuum the database to reclaim space and optimize."""
        with _connect() as conn:
            conn.execute("VACUUM")
            return "Database vacuumed successfully"

    @mcp.tool()
    def sqlite_analyze() -> str:
        """Analyze the database to update query optimizer statistics."""
        with _connect() as conn:
            conn.execute("ANALYZE")
            return "Database analyzed successfully"

    @mcp.tool()
    def sqlite_get_database_info() -> Dict[str, Any]:
        """Get comprehensive database information."""
        with _connect() as conn:
            cur = conn.cursor()
            
            # Get database file info
            cur.execute("PRAGMA database_list")
            databases = _rows_to_dicts(cur.fetchall())
            
            # Get page count and size
            cur.execute("PRAGMA page_count")
            page_count = cur.fetchone()["page_count"]
            
            cur.execute("PRAGMA page_size")
            page_size = cur.fetchone()["page_size"]
            
            # Get version info
            cur.execute("SELECT sqlite_version() as version")
            version = cur.fetchone()["version"]
            
            # Get table count
            cur.execute("SELECT COUNT(*) as count FROM sqlite_master WHERE type='table'")
            table_count = cur.fetchone()["count"]
            
            return {
                "database_path": DB,
                "sqlite_version": version,
                "page_count": page_count,
                "page_size": page_size,
                "database_size_bytes": page_count * page_size,
                "table_count": table_count,
                "databases": databases
            }

    # ==================== IMPORT/EXPORT ====================

    @mcp.tool()
    def sqlite_export_to_csv(table_name: str, file_path: str = None, where_clause: str = None, 
                           where_params: List[Any] = None) -> str:
        """Export table data to CSV file."""
        if not file_path:
            file_path = f"{table_name}_export_{datetime.now().strftime('%Y%m%d_%H%M%S')}.csv"
        
        with _connect() as conn:
            cur = conn.cursor()
            query = f"SELECT * FROM {table_name}"
            if where_clause:
                query += f" WHERE {where_clause}"
                cur.execute(query, where_params or [])
            else:
                cur.execute(query)
            
            rows = cur.fetchall()
            if not rows:
                return f"No data found in table {table_name}"
            
            # Get column names
            columns = [description[0] for description in cur.description]
            
            with open(file_path, 'w', newline='', encoding='utf-8') as csvfile:
                writer = csv.writer(csvfile)
                writer.writerow(columns)
                writer.writerows(rows)
            
            return f"Exported {len(rows)} rows to {file_path}"

    @mcp.tool()
    def sqlite_import_from_csv(table_name: str, file_path: str, has_header: bool = True, 
                             columns: List[str] = None) -> str:
        """Import data from CSV file into a table."""
        if not os.path.exists(file_path):
            raise ValueError(f"CSV file not found: {file_path}")
        
        with _connect() as conn:
            cur = conn.cursor()
            
            with open(file_path, 'r', encoding='utf-8') as csvfile:
                reader = csv.reader(csvfile)
                
                if has_header:
                    header = next(reader)
                    if columns:
                        # Use provided column mapping
                        column_mapping = {header[i]: col for i, col in enumerate(columns)}
                        insert_columns = columns
                    else:
                        insert_columns = header
                else:
                    if not columns:
                        raise ValueError("Columns must be specified when CSV has no header")
                    insert_columns = columns
                
                placeholders = ", ".join(["?" for _ in insert_columns])
                query = f"INSERT INTO {table_name} ({', '.join(insert_columns)}) VALUES ({placeholders})"
                
                rows_imported = 0
                for row in reader:
                    if has_header and columns:
                        # Map columns according to provided mapping
                        mapped_row = [row[header.index(col)] for col in columns if col in header]
                    else:
                        mapped_row = row
                    
                    cur.execute(query, mapped_row)
                    rows_imported += 1
            
            return f"Imported {rows_imported} rows from {file_path}"

    @mcp.tool()
    def sqlite_export_to_json(table_name: str, file_path: str = None, where_clause: str = None, 
                            where_params: List[Any] = None) -> str:
        """Export table data to JSON file."""
        if not file_path:
            file_path = f"{table_name}_export_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
        
        with _connect() as conn:
            cur = conn.cursor()
            query = f"SELECT * FROM {table_name}"
            if where_clause:
                query += f" WHERE {where_clause}"
                cur.execute(query, where_params or [])
            else:
                cur.execute(query)
            
            rows = cur.fetchall()
            data = _rows_to_dicts(rows)
            
            with open(file_path, 'w', encoding='utf-8') as jsonfile:
                json.dump(data, jsonfile, indent=2, ensure_ascii=False, default=str)
            
            return f"Exported {len(data)} rows to {file_path}"

    # ==================== TRANSACTION MANAGEMENT ====================

    @mcp.tool()
    def sqlite_execute_transaction(operations: List[Dict[str, Any]]) -> str:
        """Execute multiple operations in a single transaction."""
        if not operations:
            raise ValueError("Operations list cannot be empty")
        
        with _connect() as conn:
            cur = conn.cursor()
            results = []
            
            for op in operations:
                op_type = op.get("type", "").upper()
                table = op.get("table")
                data = op.get("data", {})
                where_clause = op.get("where_clause")
                where_params = op.get("where_params", [])
                
                if op_type == "INSERT":
                    columns = list(data.keys())
                    placeholders = ", ".join(["?" for _ in columns])
                    query = f"INSERT INTO {table} ({', '.join(columns)}) VALUES ({placeholders})"
                    cur.execute(query, list(data.values()))
                    results.append(f"Inserted row with ID: {cur.lastrowid}")
                
                elif op_type == "UPDATE":
                    set_clause = ", ".join([f"{col} = ?" for col in data.keys()])
                    values = list(data.values())
                    if where_params:
                        values.extend(where_params)
                    query = f"UPDATE {table} SET {set_clause} WHERE {where_clause}"
                    cur.execute(query, values)
                    results.append(f"Updated {cur.rowcount} rows")
                
                elif op_type == "DELETE":
                    query = f"DELETE FROM {table} WHERE {where_clause}"
                    cur.execute(query, where_params)
                    results.append(f"Deleted {cur.rowcount} rows")
                
                else:
                    raise ValueError(f"Unsupported operation type: {op_type}")
            
            return f"Transaction completed successfully. Results: {'; '.join(results)}"

    # ==================== PERFORMANCE MONITORING ====================

    @mcp.tool()
    def sqlite_explain_query(query: str) -> List[Dict[str, Any]]:
        """Explain the query execution plan."""
        if not _validate_sql_query(query, ['select', 'with']):
            raise ValueError("Only SELECT/CTE queries are allowed for explanation.")
        
        with _connect() as conn:
            cur = conn.cursor()
            cur.execute(f"EXPLAIN QUERY PLAN {query}")
            return _rows_to_dicts(cur.fetchall())

    @mcp.tool()
    def sqlite_get_table_stats(table_name: str) -> Dict[str, Any]:
        """Get statistics about a table."""
        with _connect() as conn:
            cur = conn.cursor()
            
            # Get row count
            cur.execute(f"SELECT COUNT(*) as row_count FROM {table_name}")
            row_count = cur.fetchone()["row_count"]
            
            # Get table size info
            cur.execute("PRAGMA table_info(?)", (table_name,))
            columns = _rows_to_dicts(cur.fetchall())
            
            # Get index info
            cur.execute("PRAGMA index_list(?)", (table_name,))
            indexes = _rows_to_dicts(cur.fetchall())
            
            return {
                "table_name": table_name,
                "row_count": row_count,
                "column_count": len(columns),
                "index_count": len(indexes),
                "columns": columns,
                "indexes": indexes
            }

    @mcp.tool()
    def sqlite_optimize_database() -> str:
        """Run database optimization operations."""
        with _connect() as conn:
            cur = conn.cursor()
            
            # Analyze all tables
            cur.execute("ANALYZE")
            
            # Vacuum to reclaim space
            cur.execute("VACUUM")
            
            return "Database optimization completed (ANALYZE + VACUUM)"

    # ==================== TABLE MANAGEMENT ====================

    @mcp.tool()
    def sqlite_create_table(table_name: str, columns: List[Dict[str, Any]], 
                           primary_key: List[str] = None, foreign_keys: List[Dict[str, Any]] = None,
                           indexes: List[Dict[str, Any]] = None, if_not_exists: bool = True) -> str:
        """Create a new table with specified columns, constraints, and indexes."""
        if not columns:
            raise ValueError("Columns list cannot be empty")
        
        with _connect() as conn:
            cur = conn.cursor()
            
            # Build column definitions
            column_defs = []
            for col in columns:
                col_def = f"{col['name']} {col['type']}"
                
                # Add constraints
                if col.get('not_null', False):
                    col_def += " NOT NULL"
                if col.get('unique', False):
                    col_def += " UNIQUE"
                if col.get('default') is not None:
                    col_def += f" DEFAULT {col['default']}"
                if col.get('check'):
                    col_def += f" CHECK ({col['check']})"
                
                column_defs.append(col_def)
            
            # Add primary key constraint
            if primary_key:
                column_defs.append(f"PRIMARY KEY ({', '.join(primary_key)})")
            
            # Add foreign key constraints
            if foreign_keys:
                for fk in foreign_keys:
                    fk_def = f"FOREIGN KEY ({fk['column']}) REFERENCES {fk['ref_table']}({fk['ref_column']})"
                    if fk.get('on_delete'):
                        fk_def += f" ON DELETE {fk['on_delete']}"
                    if fk.get('on_update'):
                        fk_def += f" ON UPDATE {fk['on_update']}"
                    column_defs.append(fk_def)
            
            # Build CREATE TABLE statement
            if_exists_clause = "IF NOT EXISTS" if if_not_exists else ""
            create_sql = f"CREATE TABLE {if_exists_clause} {table_name} ({', '.join(column_defs)})"
            
            cur.execute(create_sql)
            
            # Create indexes if specified
            if indexes:
                for idx in indexes:
                    idx_name = idx.get('name', f"idx_{table_name}_{'_'.join(idx['columns'])}")
                    unique = "UNIQUE " if idx.get('unique', False) else ""
                    idx_sql = f"CREATE {unique}INDEX {idx_name} ON {table_name} ({', '.join(idx['columns'])})"
                    cur.execute(idx_sql)
            
            return f"Table '{table_name}' created successfully"

    @mcp.tool()
    def sqlite_drop_table(table_name: str, if_exists: bool = True) -> str:
        """Drop a table from the database."""
        with _connect() as conn:
            cur = conn.cursor()
            
            if_exists_clause = "IF EXISTS" if if_exists else ""
            drop_sql = f"DROP TABLE {if_exists_clause} {table_name}"
            
            cur.execute(drop_sql)
            return f"Table '{table_name}' dropped successfully"

    @mcp.tool()
    def sqlite_alter_table_add_column(table_name: str, column_name: str, column_type: str, 
                                    not_null: bool = False, default_value: Any = None) -> str:
        """Add a new column to an existing table."""
        with _connect() as conn:
            cur = conn.cursor()
            
            col_def = f"{column_name} {column_type}"
            if not_null:
                col_def += " NOT NULL"
            if default_value is not None:
                col_def += f" DEFAULT {default_value}"
            
            alter_sql = f"ALTER TABLE {table_name} ADD COLUMN {col_def}"
            cur.execute(alter_sql)
            
            return f"Column '{column_name}' added to table '{table_name}' successfully"

    @mcp.tool()
    def sqlite_alter_table_rename_column(table_name: str, old_column_name: str, new_column_name: str) -> str:
        """Rename a column in an existing table (SQLite 3.25+)."""
        with _connect() as conn:
            cur = conn.cursor()
            
            # Check SQLite version
            cur.execute("SELECT sqlite_version()")
            version = cur.fetchone()[0]
            major, minor, patch = map(int, version.split('.'))
            
            if major < 3 or (major == 3 and minor < 25):
                raise ValueError(f"Column renaming requires SQLite 3.25+, current version: {version}")
            
            alter_sql = f"ALTER TABLE {table_name} RENAME COLUMN {old_column_name} TO {new_column_name}"
            cur.execute(alter_sql)
            
            return f"Column '{old_column_name}' renamed to '{new_column_name}' in table '{table_name}'"

    @mcp.tool()
    def sqlite_alter_table_drop_column(table_name: str, column_name: str) -> str:
        """Drop a column from an existing table (SQLite 3.35+)."""
        with _connect() as conn:
            cur = conn.cursor()
            
            # Check SQLite version
            cur.execute("SELECT sqlite_version()")
            version = cur.fetchone()[0]
            major, minor, patch = map(int, version.split('.'))
            
            if major < 3 or (major == 3 and minor < 35):
                raise ValueError(f"Column dropping requires SQLite 3.35+, current version: {version}")
            
            alter_sql = f"ALTER TABLE {table_name} DROP COLUMN {column_name}"
            cur.execute(alter_sql)
            
            return f"Column '{column_name}' dropped from table '{table_name}'"

    @mcp.tool()
    def sqlite_rename_table(old_table_name: str, new_table_name: str) -> str:
        """Rename a table."""
        with _connect() as conn:
            cur = conn.cursor()
            
            rename_sql = f"ALTER TABLE {old_table_name} RENAME TO {new_table_name}"
            cur.execute(rename_sql)
            
            return f"Table '{old_table_name}' renamed to '{new_table_name}'"

    # ==================== INDEX MANAGEMENT ====================

    @mcp.tool()
    def sqlite_create_index(index_name: str, table_name: str, columns: List[str], 
                          unique: bool = False, if_not_exists: bool = True) -> str:
        """Create an index on specified columns."""
        if not columns:
            raise ValueError("Columns list cannot be empty")
        
        with _connect() as conn:
            cur = conn.cursor()
            
            unique_clause = "UNIQUE " if unique else ""
            if_exists_clause = "IF NOT EXISTS" if if_not_exists else ""
            
            create_sql = f"CREATE {unique_clause}INDEX {if_exists_clause} {index_name} ON {table_name} ({', '.join(columns)})"
            cur.execute(create_sql)
            
            return f"Index '{index_name}' created successfully on table '{table_name}'"

    @mcp.tool()
    def sqlite_drop_index(index_name: str, if_exists: bool = True) -> str:
        """Drop an index."""
        with _connect() as conn:
            cur = conn.cursor()
            
            if_exists_clause = "IF EXISTS" if if_exists else ""
            drop_sql = f"DROP INDEX {if_exists_clause} {index_name}"
            
            cur.execute(drop_sql)
            return f"Index '{index_name}' dropped successfully"

    @mcp.tool()
    def sqlite_reindex(index_name: str = None) -> str:
        """Rebuild an index or all indexes."""
        with _connect() as conn:
            cur = conn.cursor()
            
            if index_name:
                reindex_sql = f"REINDEX {index_name}"
                cur.execute(reindex_sql)
                return f"Index '{index_name}' rebuilt successfully"
            else:
                cur.execute("REINDEX")
                return "All indexes rebuilt successfully"

    # ==================== VIEW MANAGEMENT ====================

    @mcp.tool()
    def sqlite_create_view(view_name: str, query: str, if_not_exists: bool = True) -> str:
        """Create a view from a SELECT query."""
        if not _validate_sql_query(query, ['select', 'with']):
            raise ValueError("Only SELECT/CTE queries are allowed for views.")
        
        with _connect() as conn:
            cur = conn.cursor()
            
            if_exists_clause = "IF NOT EXISTS" if if_not_exists else ""
            create_sql = f"CREATE VIEW {if_exists_clause} {view_name} AS {query}"
            
            cur.execute(create_sql)
            return f"View '{view_name}' created successfully"

    @mcp.tool()
    def sqlite_drop_view(view_name: str, if_exists: bool = True) -> str:
        """Drop a view."""
        with _connect() as conn:
            cur = conn.cursor()
            
            if_exists_clause = "IF EXISTS" if if_exists else ""
            drop_sql = f"DROP VIEW {if_exists_clause} {view_name}"
            
            cur.execute(drop_sql)
            return f"View '{view_name}' dropped successfully"

    @mcp.tool()
    def sqlite_list_views() -> List[str]:
        """List all views in the database."""
        with _connect() as conn:
            cur = conn.cursor()
            cur.execute("SELECT name FROM sqlite_master WHERE type='view' ORDER BY 1")
            return [row["name"] for row in cur.fetchall()]

    # ==================== TRIGGER MANAGEMENT ====================

    @mcp.tool()
    def sqlite_create_trigger(trigger_name: str, table_name: str, trigger_event: str, 
                            trigger_timing: str, trigger_action: str) -> str:
        """Create a trigger on a table."""
        valid_events = ["INSERT", "UPDATE", "DELETE"]
        valid_timings = ["BEFORE", "AFTER", "INSTEAD OF"]
        
        if trigger_event.upper() not in valid_events:
            raise ValueError(f"Trigger event must be one of: {valid_events}")
        if trigger_timing.upper() not in valid_timings:
            raise ValueError(f"Trigger timing must be one of: {valid_timings}")
        
        with _connect() as conn:
            cur = conn.cursor()
            
            create_sql = f"""CREATE TRIGGER {trigger_name}
                           {trigger_timing.upper()} {trigger_event.upper()} ON {table_name}
                           BEGIN
                               {trigger_action}
                           END"""
            
            cur.execute(create_sql)
            return f"Trigger '{trigger_name}' created successfully on table '{table_name}'"

    @mcp.tool()
    def sqlite_drop_trigger(trigger_name: str, if_exists: bool = True) -> str:
        """Drop a trigger."""
        with _connect() as conn:
            cur = conn.cursor()
            
            if_exists_clause = "IF EXISTS" if if_exists else ""
            drop_sql = f"DROP TRIGGER {if_exists_clause} {trigger_name}"
            
            cur.execute(drop_sql)
            return f"Trigger '{trigger_name}' dropped successfully"

    @mcp.tool()
    def sqlite_list_triggers() -> List[Dict[str, Any]]:
        """List all triggers in the database."""
        with _connect() as conn:
            cur = conn.cursor()
            cur.execute("SELECT name, tbl_name, sql FROM sqlite_master WHERE type='trigger' ORDER BY name")
            return _rows_to_dicts(cur.fetchall())

    # ==================== UTILITY FUNCTIONS ====================

    @mcp.tool()
    def sqlite_search_tables(search_term: str) -> List[Dict[str, Any]]:
        """Search for tables and columns containing a specific term."""
        with _connect() as conn:
            cur = conn.cursor()
            
            # Get all tables
            cur.execute("SELECT name FROM sqlite_master WHERE type='table'")
            tables = [row["name"] for row in cur.fetchall()]
            
            results = []
            for table in tables:
                # Check table name
                if search_term.lower() in table.lower():
                    results.append({
                        "type": "table",
                        "name": table,
                        "match": "table_name"
                    })
                
                # Check column names
                cur.execute("PRAGMA table_info(?)", (table,))
                columns = _rows_to_dicts(cur.fetchall())
                
                for col in columns:
                    if search_term.lower() in col["name"].lower():
                        results.append({
                            "type": "column",
                            "table": table,
                            "name": col["name"],
                            "match": "column_name"
                        })
            
            return results

    @mcp.tool()
    def sqlite_validate_database() -> Dict[str, Any]:
        """Validate database integrity and return any issues."""
        with _connect() as conn:
            cur = conn.cursor()
            
            # Check integrity
            cur.execute("PRAGMA integrity_check")
            integrity_result = cur.fetchone()["integrity_check"]
            
            # Check foreign key constraints
            cur.execute("PRAGMA foreign_key_check")
            fk_issues = _rows_to_dicts(cur.fetchall())
            
            return {
                "integrity_check": integrity_result,
                "foreign_key_issues": fk_issues,
                "is_valid": integrity_result == "ok" and len(fk_issues) == 0
            }
