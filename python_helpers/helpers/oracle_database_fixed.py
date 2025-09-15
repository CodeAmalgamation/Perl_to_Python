#!/usr/bin/env python3
"""
helpers/database.py - Oracle-focused database helper
Simplified version focusing on Oracle DB with proper error handling
"""

import uuid
import traceback
import sys
from typing import Dict, Any, List, Optional

# Global connection and statement pools
_connections = {}
_statements = {}

def debug_log(message: str) -> None:
    """Log debug messages to stderr"""
    import datetime
    timestamp = datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    print(f"[{timestamp}] DATABASE DEBUG: {message}", file=sys.stderr, flush=True)

def connect(dsn: str, username: str = '', password: str = '', options: Dict = None, db_type: str = '') -> Dict[str, Any]:
    """Connect to Oracle database"""
    try:
        debug_log(f"Oracle connect: dsn={dsn}, user={username}")
        
        connection_id = str(uuid.uuid4())
        
        # Parse Oracle DSN
        oracle_params = _parse_oracle_dsn(dsn)
        debug_log(f"Parsed Oracle params: {oracle_params}")
        
        # Connect to Oracle
        conn = _connect_oracle(oracle_params, username, password)
        
        if not conn:
            raise RuntimeError("Failed to establish Oracle connection")
        
        # Store connection info
        _connections[connection_id] = {
            'connection': conn,
            'type': 'oracle',
            'dsn': dsn,
            'username': username,
            'autocommit': options.get('AutoCommit', True) if options else True,
            'raise_error': options.get('RaiseError', False) if options else False,
            'print_error': options.get('PrintError', True) if options else True,
        }
        
        debug_log(f"Oracle connection successful: {connection_id}")
        
        return {
            'success': True,
            'connection_id': connection_id,
            'db_type': 'oracle'
        }
        
    except Exception as e:
        debug_log(f"Oracle connection failed: {str(e)}")
        return {
            'success': False,
            'error': str(e),
            'traceback': traceback.format_exc()
        }

def _connect_oracle(params: Dict[str, str], username: str, password: str):
    """Connect to Oracle using oracledb"""
    try:
        import oracledb
        debug_log("Using oracledb driver")
        
        # Build connection string
        if 'service_name' in params:
            host = params.get('host', 'localhost')
            port = params.get('port', '1521')
            service = params['service_name']
            
            # Handle URLs in service_name (clean them)
            if service.startswith('http'):
                debug_log(f"Warning: service_name looks like URL: {service}")
                # Extract just the hostname part if it's a URL
                if '://' in service:
                    service = service.split('://')[1].split('/')[0]
                    debug_log(f"Cleaned service_name: {service}")
            
            connect_string = f"{host}:{port}/{service}"
            
        elif 'sid' in params:
            host = params.get('host', 'localhost')
            port = params.get('port', '1521')
            sid = params['sid']
            connect_string = f"{host}:{port}/{sid}"
            
        elif 'tns' in params:
            connect_string = params['tns']
            
        else:
            raise ValueError("No valid Oracle connection parameters found")
        
        debug_log(f"Oracle connect string: {connect_string}")
        
        # Attempt connection
        conn = oracledb.connect(
            user=username,
            password=password,
            dsn=connect_string
        )
        
        debug_log("oracledb connection successful")
        return conn
        
    except ImportError:
        debug_log("oracledb not available, trying cx_Oracle")
        
        try:
            import cx_Oracle
            
            if 'service_name' in params:
                host = params.get('host', 'localhost')
                port = int(params.get('port', '1521'))
                service = params['service_name']
                
                # Clean URL-like service names
                if service.startswith('http'):
                    if '://' in service:
                        service = service.split('://')[1].split('/')[0]
                
                dsn_string = cx_Oracle.makedsn(host, port, service_name=service)
                
            elif 'sid' in params:
                host = params.get('host', 'localhost')
                port = int(params.get('port', '1521'))
                sid = params['sid']
                dsn_string = cx_Oracle.makedsn(host, port, sid=sid)
                
            else:
                dsn_string = params.get('tns', 'localhost:1521/XE')
            
            debug_log(f"cx_Oracle DSN: {dsn_string}")
            
            conn = cx_Oracle.connect(username, password, dsn_string)
            debug_log("cx_Oracle connection successful")
            return conn
            
        except ImportError:
            raise ImportError("No Oracle driver available. Install oracledb: pip install oracledb")
        except Exception as e:
            debug_log(f"cx_Oracle connection failed: {e}")
            raise

def _parse_oracle_dsn(dsn: str) -> Dict[str, str]:
    """Parse Oracle DSN - handles both DBI format and direct connection strings"""
    debug_log(f"Parsing DSN: {dsn}")
    params = {}
    
    if dsn.startswith('dbi:'):
        # DBI format: dbi:Oracle:host=X092B-SCAN;port=2210;service_name=P_PDEQ_APP.SALEM.PAYMENTECH.COM
        parts = dsn.split(':', 2)
        if len(parts) >= 3:
            db_info = parts[2]
            
            # Parse key=value pairs separated by semicolons
            if ';' in db_info:
                for param in db_info.split(';'):
                    if '=' in param:
                        key, value = param.split('=', 1)
                        params[key.lower().strip()] = value.strip()
            else:
                # Simple format - treat as TNS name
                params['tns'] = db_info
    else:
        # Direct connection string format: X092B-SCAN:2210/P_PDEQ_APP.SALEM.PAYMENTECH.COM
        if ':' in dsn and '/' in dsn:
            # Parse host:port/service_name format
            host_port, service = dsn.split('/', 1)
            if ':' in host_port:
                host, port = host_port.split(':', 1)
                params['host'] = host.strip()
                params['port'] = port.strip()
                params['service_name'] = service.strip()
                debug_log(f"Parsed direct format: host={params['host']}, port={params['port']}, service={params['service_name']}")
            else:
                params['tns'] = dsn
        else:
            # Treat as TNS name
            params['tns'] = dsn
    
    debug_log(f"Parsed params: {params}")
    return params

def prepare(connection_id: str, sql: str) -> Dict[str, Any]:
    """Prepare SQL statement"""
    try:
        if connection_id not in _connections:
            raise ValueError("Invalid connection ID")
        
        statement_id = str(uuid.uuid4())
        
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
    """Execute prepared statement"""
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
        
        # Handle bind parameters
        final_bind_values = bind_values or []
        
        if bind_params:
            for param_name, param_info in bind_params.items():
                if isinstance(param_name, str) and param_name.startswith(':'):
                    # Named parameter - add to bind values
                    final_bind_values.append(param_info['value'])
                elif isinstance(param_name, int):
                    # Positional parameter
                    while len(final_bind_values) <= param_name:
                        final_bind_values.append(None)
                    final_bind_values[param_name - 1] = param_info['value']
        
        # Execute statement
        if final_bind_values:
            cursor.execute(stmt_info['sql'], final_bind_values)
        else:
            cursor.execute(stmt_info['sql'])
        
        stmt_info['executed'] = True
        
        # Get column information
        column_info = None
        if hasattr(cursor, 'description') and cursor.description:
            column_info = {
                'count': len(cursor.description),
                'names': [desc[0] for desc in cursor.description],
                'types': [desc[1] if len(desc) > 1 else None for desc in cursor.description]
            }
        
        rows_affected = cursor.rowcount if hasattr(cursor, 'rowcount') else 0
        
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
    """Fetch single row"""
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
            columns = [desc[0] for desc in cursor.description]
            row_dict = dict(zip(columns, row))
            return {'success': True, 'row': row_dict}
        else:
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
    """Execute SQL immediately"""
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
        
        rows_affected = cursor.rowcount if hasattr(cursor, 'rowcount') else 0
        
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
    """Begin transaction"""
    try:
        if connection_id not in _connections:
            raise ValueError("Invalid connection ID")
        
        conn_info = _connections[connection_id]
        conn_info['autocommit'] = False
        
        return {'success': True}
        
    except Exception as e:
        return {
            'success': False,
            'error': str(e)
        }

def commit(connection_id: str) -> Dict[str, Any]:
    """Commit transaction"""
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
    """Rollback transaction"""
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
    """Close connection"""
    try:
        if connection_id in _connections:
            conn = _connections[connection_id]['connection']
            conn.close()
            del _connections[connection_id]
        
        # Clean up statements
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
    """Finish statement"""
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