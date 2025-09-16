#!/usr/bin/env python3
"""
helpers/database.py - Oracle database helper using oracledb driver
"""

import uuid
import traceback
import os
from typing import Dict, Any, List, Optional

try:
    import oracledb
except ImportError:
    raise ImportError("oracledb driver is required. Install with: pip install oracledb")

# Global connection and statement pools
_connections = {}
_statements = {}

def connect(dsn: str, username: str = '', password: str = '', options: Dict = None, db_type: str = '') -> Dict[str, Any]:
    """Connect to Oracle database using oracledb driver"""
    try:
        connection_id = str(uuid.uuid4())

        # Handle Oracle TNS-in-username pattern: "dbi:Oracle:" with "user@TNS_NAME"
        actual_username = username
        if '@' in username:
            actual_username, tns_name = username.split('@', 1)
            # If DSN is minimal, use TNS from username
            if dsn in ['dbi:Oracle:', 'dbi:Oracle', 'dbi:Ora:', 'dbi:Ora']:
                dsn = tns_name

        # Parse Oracle connection details
        connection_params = _parse_oracle_dsn(dsn)

        # Connect to Oracle database
        conn = _connect_oracle(connection_params, actual_username, password, options)
        
        if not conn:
            raise RuntimeError("Failed to establish Oracle database connection")

        # Store connection with metadata
        _connections[connection_id] = {
            'connection': conn,
            'type': 'oracle',
            'dsn': dsn,
            'username': actual_username,
            'autocommit': options.get('AutoCommit', True) if options else True,
            'raise_error': options.get('RaiseError', False) if options else False,
            'print_error': options.get('PrintError', True) if options else True,
        }

        # Configure autocommit
        conn.autocommit = _connections[connection_id]['autocommit']

        return {
            'success': True,
            'connection_id': connection_id,
            'db_type': 'oracle'
        }
        
    except Exception as e:
        return {
            'success': False,
            'error': str(e),
            'traceback': traceback.format_exc()
        }

def _connect_oracle(connection_params: Dict[str, str], username: str, password: str, options: Dict = None) -> Any:
    """Connect to Oracle database using oracledb driver"""

    # Build connection string
    if 'service_name' in connection_params:
        connect_string = f"{connection_params.get('host', 'localhost')}:{connection_params.get('port', 1521)}/{connection_params['service_name']}"
    elif 'sid' in connection_params:
        connect_string = f"{connection_params.get('host', 'localhost')}:{connection_params.get('port', 1521)}/{connection_params['sid']}"
    elif 'tns' in connection_params:
        connect_string = connection_params['tns']
    else:
        # Fallback for minimal connection info
        connect_string = f"localhost:1521/XE"

    conn = oracledb.connect(
        user=username,
        password=password,
        dsn=connect_string
    )

    return conn


def _parse_oracle_dsn(dsn: str) -> Dict[str, str]:
    """Parse Oracle DSN format"""
    params = {}

    if dsn.startswith('dbi:'):
        # Standard DBI DSN format: dbi:Oracle:...
        parts = dsn.split(':', 2)
        if len(parts) >= 3:
            db_info = parts[2]

            # Check if driver is Oracle
            if parts[1].lower() not in ['oracle', 'ora']:
                raise ValueError(f"Only Oracle databases are supported, got: {parts[1]}")

            if ';' in db_info:
                # Key=value format: host=localhost;port=1521;service_name=ORCL
                for param in db_info.split(';'):
                    if '=' in param:
                        key, value = param.split('=', 1)
                        params[key.lower()] = value
            elif ':' in db_info and not db_info.startswith('('):
                # host:port:sid format: localhost:1521:XE
                parts = db_info.split(':')
                if len(parts) >= 3:
                    params['host'] = parts[0]
                    params['port'] = int(parts[1])
                    params['sid'] = parts[2]
            else:
                # TNS name or connection descriptor
                params['tns'] = db_info
    else:
        # Direct connection string (TNS name or host:port/service)
        params['tns'] = dsn

    return params


def prepare(connection_id: str, sql: str) -> Dict[str, Any]:
    """Prepare SQL statement"""
    try:
        if connection_id not in _connections:
            raise ValueError("Invalid connection ID")
        
        statement_id = str(uuid.uuid4())
        conn_info = _connections[connection_id]
        
        # Store statement info (cursor will be created on execute)
        _statements[statement_id] = {
            'connection_id': connection_id,
            'sql': sql,
            'cursor': None,
            'executed': False,
            'finished': False
        }
        
        return {
            'success': True,
            'statement_id': statement_id
        }
        
    except Exception as e:
        return {
            'success': False,
            'error': str(e)
        }

def execute_statement(connection_id: str, statement_id: str, bind_values: List = None, bind_params: Dict = None) -> Dict[str, Any]:
    """Execute prepared statement with enhanced bind parameter support"""
    try:
        if connection_id not in _connections:
            raise ValueError("Invalid connection ID")
        
        if statement_id not in _statements:
            raise ValueError("Invalid statement ID")
        
        conn_info = _connections[connection_id]
        stmt_info = _statements[statement_id]
        conn = conn_info['connection']
        
        cursor = conn.cursor()
        stmt_info['cursor'] = cursor
        
        # Handle different bind parameter formats
        final_bind_values = bind_values or []
        
        # Process named bind parameters for Oracle
        if bind_params:
            # Convert named parameters to positional for Oracle
            sql = stmt_info['sql']
            for param_name, param_info in bind_params.items():
                if isinstance(param_name, str) and param_name.startswith(':'):
                    sql = sql.replace(param_name, '?')
                    final_bind_values.append(param_info['value'])
                elif isinstance(param_name, int):
                    if param_name <= len(final_bind_values):
                        final_bind_values[param_name - 1] = param_info['value']
                    else:
                        final_bind_values.append(param_info['value'])
        
        # Execute with parameters
        if final_bind_values:
            cursor.execute(stmt_info['sql'], final_bind_values)
        else:
            cursor.execute(stmt_info['sql'])
        
        stmt_info['executed'] = True
        
        # Get enhanced column information
        column_info = None
        if hasattr(cursor, 'description') and cursor.description:
            column_info = {
                'count': len(cursor.description),
                'names': [desc[0] for desc in cursor.description],
                'types': [desc[1] if len(desc) > 1 else None for desc in cursor.description]
            }
        
        rows_affected = getattr(cursor, 'rowcount', 0)
        
        return {
            'success': True,
            'rows_affected': rows_affected,
            'column_info': column_info
        }
        
    except Exception as e:
        return {
            'success': False,
            'error': str(e)
        }

def fetch_row(connection_id: str, statement_id: str, format: str = 'array') -> Dict[str, Any]:
    """Fetch single row with enhanced tracking"""
    try:
        if statement_id not in _statements:
            raise ValueError("Invalid statement ID")
        
        stmt_info = _statements[statement_id]
        
        if not stmt_info['executed']:
            raise ValueError("Statement not executed")
        
        if stmt_info['finished']:
            return {'success': False}
        
        cursor = stmt_info['cursor']
        row = cursor.fetchone()
        
        if row is None:
            stmt_info['finished'] = True
            return {'success': False}
        
        if format == 'hash' and hasattr(cursor, 'description'):
            # Convert to dictionary
            columns = [desc[0] for desc in cursor.description]
            row_dict = dict(zip(columns, row))
            return {'success': True, 'row': row_dict}
        else:
            # Return as array
            return {'success': True, 'row': list(row)}
        
    except Exception as e:
        return {
            'success': False,
            'error': str(e)
        }

def fetch_all(connection_id: str, statement_id: str, format: str = 'array') -> Dict[str, Any]:
    """Fetch all remaining rows"""
    try:
        if statement_id not in _statements:
            raise ValueError("Invalid statement ID")
        
        stmt_info = _statements[statement_id]
        cursor = stmt_info['cursor']
        
        if not stmt_info['executed']:
            raise ValueError("Statement not executed")
        
        rows = cursor.fetchall()
        stmt_info['finished'] = True
        
        if format == 'hash' and hasattr(cursor, 'description'):
            columns = [desc[0] for desc in cursor.description]
            result = [dict(zip(columns, row)) for row in rows]
        else:
            result = [list(row) for row in rows]
        
        return {
            'success': True,
            'rows': result
        }
        
    except Exception as e:
        return {
            'success': False,
            'error': str(e)
        }

def execute_immediate(connection_id: str, sql: str, bind_values: List = None) -> Dict[str, Any]:
    """Execute SQL immediately without preparation"""
    try:
        if connection_id not in _connections:
            raise ValueError("Invalid connection ID")
        
        conn_info = _connections[connection_id]
        conn = conn_info['connection']
        cursor = conn.cursor()
        
        if bind_values:
            cursor.execute(sql, bind_values)
        else:
            cursor.execute(sql)
        
        rows_affected = getattr(cursor, 'rowcount', 0)
        
        # Auto-commit if enabled
        if conn_info['autocommit']:
            conn.commit()
        
        cursor.close()
        
        return {
            'success': True,
            'rows_affected': rows_affected
        }
        
    except Exception as e:
        return {
            'success': False,
            'error': str(e)
        }

def begin_transaction(connection_id: str) -> Dict[str, Any]:
    """Begin database transaction"""
    try:
        if connection_id not in _connections:
            raise ValueError("Invalid connection ID")
        
        conn_info = _connections[connection_id]
        conn = conn_info['connection']
        
        # Oracle handles transactions automatically
        
        conn_info['autocommit'] = False
        
        return {'success': True}
        
    except Exception as e:
        return {
            'success': False,
            'error': str(e)
        }

def commit(connection_id: str) -> Dict[str, Any]:
    """Commit current transaction"""
    try:
        if connection_id not in _connections:
            raise ValueError("Invalid connection ID")
        
        conn = _connections[connection_id]['connection']
        conn.commit()
        
        return {'success': True}
        
    except Exception as e:
        return {
            'success': False,
            'error': str(e)
        }

def rollback(connection_id: str) -> Dict[str, Any]:
    """Rollback current transaction"""
    try:
        if connection_id not in _connections:
            raise ValueError("Invalid connection ID")
        
        conn = _connections[connection_id]['connection']
        conn.rollback()
        
        return {'success': True}
        
    except Exception as e:
        return {
            'success': False,
            'error': str(e)
        }

def disconnect(connection_id: str) -> Dict[str, Any]:
    """Close database connection"""
    try:
        if connection_id in _connections:
            conn = _connections[connection_id]['connection']
            conn.close()
            del _connections[connection_id]
        
        # Clean up associated statements
        statements_to_remove = [
            sid for sid, stmt in _statements.items() 
            if stmt['connection_id'] == connection_id
        ]
        for sid in statements_to_remove:
            del _statements[sid]
        
        return {'success': True}
        
    except Exception as e:
        return {
            'success': False,
            'error': str(e)
        }

def finish_statement(connection_id: str, statement_id: str) -> Dict[str, Any]:
    """Finish/close statement handle"""
    try:
        if statement_id in _statements:
            stmt = _statements[statement_id]
            if stmt['cursor']:
                stmt['cursor'].close()
            del _statements[statement_id]
        
        return {'success': True}
        
    except Exception as e:
        return {
            'success': False,
            'error': str(e)
        }