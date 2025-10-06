#!/usr/bin/env python3
"""
helpers/database.py - Oracle database helper using oracledb driver
"""

import uuid
import traceback
import os
import tempfile
import json
import pickle
import time
import threading
from typing import Dict, Any, List, Optional

try:
    import oracledb
except ImportError:
    raise ImportError("oracledb driver is required. Install with: pip install oracledb")

# Global connection and statement pools
_connections = {}
_statements = {}

# Connection cache for connect_cached()
# TODO: Add thread safety with threading.Lock() when needed
_CONNECTION_CACHE = {}
_CACHE_MAX_SIZE = 50  # Maximum cached connections
_CACHE_IDLE_TIMEOUT = 600  # 10 minutes in seconds

# Persistent storage for connections across bridge calls
_PERSISTENCE_DIR = os.path.join(tempfile.gettempdir(), 'cpan_bridge_db')
_CONNECTION_TIMEOUT = 1800  # 30 minutes

# Global Oracle thick client initialization state (for Kerberos)
_ORACLE_THICK_CLIENT_INITIALIZED = False
_ORACLE_THICK_CLIENT_INIT_LOCK = threading.Lock()

def _get_oracle_type_name(oracle_type) -> str:
    """Convert Oracle type object to human-readable type name (Phase 2)"""
    if oracle_type is None:
        return 'UNKNOWN'

    # Map Oracle DB types to names
    type_map = {
        oracledb.DB_TYPE_VARCHAR: 'VARCHAR2',
        oracledb.DB_TYPE_NVARCHAR: 'NVARCHAR2',
        oracledb.DB_TYPE_CHAR: 'CHAR',
        oracledb.DB_TYPE_NCHAR: 'NCHAR',
        oracledb.DB_TYPE_NUMBER: 'NUMBER',
        oracledb.DB_TYPE_BINARY_FLOAT: 'BINARY_FLOAT',
        oracledb.DB_TYPE_BINARY_DOUBLE: 'BINARY_DOUBLE',
        oracledb.DB_TYPE_DATE: 'DATE',
        oracledb.DB_TYPE_TIMESTAMP: 'TIMESTAMP',
        oracledb.DB_TYPE_TIMESTAMP_TZ: 'TIMESTAMP WITH TIME ZONE',
        oracledb.DB_TYPE_TIMESTAMP_LTZ: 'TIMESTAMP WITH LOCAL TIME ZONE',
        oracledb.DB_TYPE_CLOB: 'CLOB',
        oracledb.DB_TYPE_NCLOB: 'NCLOB',
        oracledb.DB_TYPE_BLOB: 'BLOB',
        oracledb.DB_TYPE_RAW: 'RAW',
        oracledb.DB_TYPE_LONG_RAW: 'LONG RAW',
        oracledb.DB_TYPE_ROWID: 'ROWID',
        oracledb.DB_TYPE_INTERVAL_DS: 'INTERVAL DAY TO SECOND',
        oracledb.DB_TYPE_INTERVAL_YM: 'INTERVAL YEAR TO MONTH',
    }

    return type_map.get(oracle_type, str(oracle_type))

def _extract_column_metadata(cursor) -> Optional[Dict[str, Any]]:
    """
    Extract enhanced column metadata from cursor description (Phase 2)

    cursor.description format for oracledb:
    (name, type, display_size, internal_size, precision, scale, null_ok)

    Returns DBI-compatible column information with full type details
    """
    if not hasattr(cursor, 'description') or not cursor.description:
        return None

    columns = []
    for desc in cursor.description:
        col_info = {
            'name': desc[0],  # Column name
            'type': _get_oracle_type_name(desc[1]) if len(desc) > 1 else 'UNKNOWN',  # Type name
            'type_code': desc[1] if len(desc) > 1 else None,  # Oracle type object
            'display_size': desc[2] if len(desc) > 2 else None,  # Display size
            'internal_size': desc[3] if len(desc) > 3 else None,  # Internal size
            'precision': desc[4] if len(desc) > 4 else None,  # Numeric precision
            'scale': desc[5] if len(desc) > 5 else None,  # Numeric scale
            'nullable': desc[6] if len(desc) > 6 else None,  # NULL allowed
        }
        columns.append(col_info)

    return {
        'count': len(columns),
        'names': [col['name'] for col in columns],
        'types': [col['type'] for col in columns],
        'columns': columns  # Full metadata for each column
    }

def _simple_encrypt(text: str) -> str:
    """Simple XOR encryption for password storage (not production-grade)"""
    if not text:
        return ''
    key = "CPAN_BRIDGE_DB_KEY_2024"
    result = ""
    for i, char in enumerate(text):
        result += chr(ord(char) ^ ord(key[i % len(key)]))
    return result.encode('latin1').hex()

def _simple_decrypt(hex_text: str) -> str:
    """Simple XOR decryption for password storage"""
    if not hex_text:
        return ''
    try:
        encrypted = bytes.fromhex(hex_text).decode('latin1')
        key = "CPAN_BRIDGE_DB_KEY_2024"
        result = ""
        for i, char in enumerate(encrypted):
            result += chr(ord(char) ^ ord(key[i % len(key)]))
        return result
    except:
        return ''

def _ensure_persistence_dir():
    """Ensure persistence directory exists"""
    if not os.path.exists(_PERSISTENCE_DIR):
        os.makedirs(_PERSISTENCE_DIR, mode=0o700)

def _ensure_oracle_thick_client() -> Dict[str, Any]:
    """
    Ensure Oracle thick client is initialized (required for Kerberos)

    This should be called once globally before any Kerberos connections.
    Thread-safe initialization.

    Returns:
        Dict with success status
    """
    global _ORACLE_THICK_CLIENT_INITIALIZED

    with _ORACLE_THICK_CLIENT_INIT_LOCK:
        if _ORACLE_THICK_CLIENT_INITIALIZED:
            return {
                'success': True,
                'message': 'Oracle thick client already initialized'
            }

        try:
            # Initialize Oracle thick client (needed for external auth)
            oracledb.init_oracle_client()
            _ORACLE_THICK_CLIENT_INITIALIZED = True

            return {
                'success': True,
                'message': 'Oracle thick client initialized successfully'
            }
        except Exception as e:
            error_msg = str(e)

            # Provide helpful error messages
            if 'cannot be used in thin mode' in error_msg.lower():
                return {
                    'success': False,
                    'error': 'Oracle thick client initialization failed - thick mode required for Kerberos'
                }
            else:
                return {
                    'success': False,
                    'error': f'Oracle thick client initialization failed: {error_msg}'
                }

def _validate_kerberos_environment() -> Dict[str, Any]:
    """
    Validate Kerberos environment variables

    Checks that KRB5_CONFIG and KRB5CCNAME are set and point to existing files.
    This matches the POC validation logic.

    Returns:
        Dict with success status and environment info
    """
    krb5_config = os.getenv("KRB5_CONFIG")
    krb5_ccname = os.getenv("KRB5CCNAME")

    errors = []

    # Validate KRB5_CONFIG
    if not krb5_config:
        errors.append("KRB5_CONFIG environment variable not set")
    elif not os.path.exists(krb5_config):
        errors.append(f"KRB5_CONFIG file does not exist: {krb5_config}")

    # Validate KRB5CCNAME
    if not krb5_ccname:
        errors.append("KRB5CCNAME environment variable not set")
    elif not os.path.exists(krb5_ccname):
        errors.append(f"KRB5CCNAME file does not exist: {krb5_ccname}")

    if errors:
        return {
            'success': False,
            'error': 'Kerberos environment validation failed',
            'details': errors,
            'help': (
                "To use Kerberos authentication:\n"
                "1. Ensure you have a valid Kerberos ticket (run 'kinit')\n"
                "2. Set KRB5_CONFIG to your krb5.conf path\n"
                "3. Set KRB5CCNAME to your credential cache path\n"
                "Example:\n"
                "  export KRB5_CONFIG=/etc/krb5.conf\n"
                "  export KRB5CCNAME=/tmp/krb5cc_1000"
            )
        }

    return {
        'success': True,
        'krb5_config': krb5_config,
        'krb5_ccname': krb5_ccname,
        'message': 'Kerberos environment validated successfully'
    }

def _connect_oracle_kerberos(connection_params: Dict[str, str],
                             username: str = '',
                             options: Dict = None) -> Any:
    """
    Connect to Oracle database using Kerberos authentication

    This matches the POC implementation:
    1. Validates Kerberos environment (KRB5_CONFIG, KRB5CCNAME)
    2. Ensures Oracle thick client is initialized
    3. Connects with externalauth=True

    Args:
        connection_params: Parsed DSN parameters
        username: Optional username (usually not needed for Kerberos)
        options: Connection options

    Returns:
        Oracle connection object

    Raises:
        RuntimeError: If Kerberos setup is invalid or connection fails
    """
    # Step 1: Validate Kerberos environment (from POC)
    env_check = _validate_kerberos_environment()
    if not env_check['success']:
        raise RuntimeError(
            f"{env_check['error']}: {', '.join(env_check['details'])}\n\n"
            f"{env_check['help']}"
        )

    # Step 2: Ensure Oracle thick client is initialized (from POC)
    thick_client_init = _ensure_oracle_thick_client()
    if not thick_client_init['success']:
        raise RuntimeError(
            f"Cannot use Kerberos authentication: {thick_client_init['error']}\n"
            "Kerberos requires Oracle thick client mode."
        )

    # Step 3: Build connection string (same format as POC: host:port/service_name)
    if 'service_name' in connection_params:
        connect_string = f"{connection_params.get('host', 'localhost')}:{connection_params.get('port', 1521)}/{connection_params['service_name']}"
    elif 'sid' in connection_params:
        connect_string = f"{connection_params.get('host', 'localhost')}:{connection_params.get('port', 1521)}/{connection_params['sid']}"
    elif 'tns' in connection_params:
        connect_string = connection_params['tns']
    else:
        raise RuntimeError("Invalid DSN for Kerberos connection - need host:port/service_name format")

    try:
        # Step 4: Connect with externalauth=True (from POC)
        conn = oracledb.connect(
            dsn=connect_string,
            externalauth=True  # This is the key for Kerberos
        )

        return conn

    except Exception as e:
        error_msg = str(e).lower()

        # Provide helpful error messages for common Kerberos issues
        if 'ora-01017' in error_msg or 'invalid username/password' in error_msg:
            raise RuntimeError(
                "Kerberos authentication failed - ORA-01017\n"
                "Possible causes:\n"
                "1. No valid Kerberos ticket (run 'kinit username')\n"
                "2. Ticket expired (run 'kinit -R' to renew)\n"
                "3. Oracle database not configured for Kerberos\n"
                "4. Check 'klist' to verify ticket status"
            )
        elif 'ora-12641' in error_msg:
            raise RuntimeError(
                "Kerberos authentication failed - ORA-12641\n"
                "Authentication service not initialized\n"
                "Check Oracle sqlnet.ora: AUTHENTICATION_SERVICES=(KERBEROS5)"
            )
        elif 'ora-12649' in error_msg:
            raise RuntimeError(
                "Kerberos authentication failed - ORA-12649\n"
                "Unknown encryption/checksum type\n"
                "Kerberos encryption type may not be supported by Oracle"
            )
        else:
            raise RuntimeError(f"Kerberos connection failed: {str(e)}")

def _save_connection_metadata(connection_id: str, metadata: Dict[str, Any], password: str = '', auth_mode: str = 'password'):
    """Save connection metadata to persistent storage"""
    try:
        _ensure_persistence_dir()
        metadata_file = os.path.join(_PERSISTENCE_DIR, f"{connection_id}.json")

        # Store connection metadata including encrypted password (if any)
        persistent_metadata = {
            'connection_id': connection_id,
            'type': metadata.get('type'),
            'dsn': metadata.get('dsn'),
            'username': metadata.get('username'),
            'password': _simple_encrypt(password) if password and auth_mode == 'password' else '',
            'auth_mode': auth_mode,  # Store authentication mode
            'autocommit': metadata.get('autocommit'),
            'raise_error': metadata.get('raise_error'),
            'print_error': metadata.get('print_error'),
            'created_at': time.time(),
            'last_used': time.time()
        }

        with open(metadata_file, 'w') as f:
            json.dump(persistent_metadata, f)

        return True
    except Exception:
        return False

def _load_connection_metadata(connection_id: str) -> Optional[Dict[str, Any]]:
    """Load connection metadata from persistent storage"""
    try:
        metadata_file = os.path.join(_PERSISTENCE_DIR, f"{connection_id}.json")

        if not os.path.exists(metadata_file):
            return None

        with open(metadata_file, 'r') as f:
            metadata = json.load(f)

        # Check if connection has expired
        if time.time() - metadata.get('created_at', 0) > _CONNECTION_TIMEOUT:
            os.unlink(metadata_file)  # Remove expired metadata
            return None

        # Update last used time
        metadata['last_used'] = time.time()
        with open(metadata_file, 'w') as f:
            json.dump(metadata, f)

        return metadata
    except Exception:
        return None

def _remove_connection_metadata(connection_id: str):
    """Remove connection metadata from persistent storage"""
    try:
        metadata_file = os.path.join(_PERSISTENCE_DIR, f"{connection_id}.json")
        if os.path.exists(metadata_file):
            os.unlink(metadata_file)
    except Exception:
        pass

def _restore_connection_from_metadata(metadata: Dict[str, Any]) -> Optional[Any]:
    """Restore Oracle connection from metadata"""
    try:
        # Recreate the Oracle connection using stored metadata
        connection_params = _parse_oracle_dsn(metadata['dsn'])
        auth_mode = metadata.get('auth_mode', 'password')

        # Restore based on authentication mode
        if auth_mode == 'kerberos':
            # For Kerberos, reconnect using current ticket
            # No password needed
            conn = _connect_oracle_kerberos(connection_params, metadata['username'])
        else:  # password (default)
            # Decrypt stored password
            password = _simple_decrypt(metadata.get('password', ''))

            # Re-establish Oracle connection
            options = {
                'AutoCommit': metadata.get('autocommit', True),
                'RaiseError': metadata.get('raise_error', False),
                'PrintError': metadata.get('print_error', True)
            }
            conn = _connect_oracle(connection_params, metadata['username'], password, options)

        return conn

    except Exception as e:
        # If connection restoration fails, the metadata is stale
        return None

def _save_statement_metadata(statement_id: str, metadata: Dict[str, Any]):
    """Save statement metadata to persistent storage"""
    try:
        _ensure_persistence_dir()
        metadata_file = os.path.join(_PERSISTENCE_DIR, f"stmt_{statement_id}.json")

        # Store statement metadata (cursor can't be serialized)
        persistent_metadata = {
            'statement_id': statement_id,
            'connection_id': metadata.get('connection_id'),
            'sql': metadata.get('sql'),
            'executed': metadata.get('executed', False),
            'finished': metadata.get('finished', False),
            'peeked_row': metadata.get('peeked_row'),  # Save peeked row data for cross-process fetch
            'created_at': time.time(),
            'last_used': time.time()
        }

        with open(metadata_file, 'w') as f:
            json.dump(persistent_metadata, f)

        return True
    except Exception:
        return False

def _load_statement_metadata(statement_id: str) -> Optional[Dict[str, Any]]:
    """Load statement metadata from persistent storage"""
    try:
        metadata_file = os.path.join(_PERSISTENCE_DIR, f"stmt_{statement_id}.json")

        if not os.path.exists(metadata_file):
            return None

        with open(metadata_file, 'r') as f:
            metadata = json.load(f)

        # Check if statement has expired
        if time.time() - metadata.get('created_at', 0) > _CONNECTION_TIMEOUT:
            os.unlink(metadata_file)  # Remove expired metadata
            return None

        # Update last used time
        metadata['last_used'] = time.time()
        with open(metadata_file, 'w') as f:
            json.dump(metadata, f)

        return metadata
    except Exception:
        return None

def _remove_statement_metadata(statement_id: str):
    """Remove statement metadata from persistent storage"""
    try:
        metadata_file = os.path.join(_PERSISTENCE_DIR, f"stmt_{statement_id}.json")
        if os.path.exists(metadata_file):
            os.unlink(metadata_file)
    except Exception:
        pass

def _restore_statement_from_metadata(statement_metadata: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    """Restore statement from metadata by recreating cursor"""
    try:
        connection_id = statement_metadata['connection_id']

        # Ensure connection is available (restore if needed)
        if connection_id not in _connections:
            # Load and restore connection first
            conn_metadata = _load_connection_metadata(connection_id)
            if not conn_metadata:
                return None

            conn = _restore_connection_from_metadata(conn_metadata)
            if not conn:
                return None

            # Store restored connection in memory
            _connections[connection_id] = {
                'connection': conn,
                'type': conn_metadata['type'],
                'dsn': conn_metadata['dsn'],
                'username': conn_metadata['username'],
                'autocommit': conn_metadata['autocommit'],
                'raise_error': conn_metadata['raise_error'],
                'print_error': conn_metadata['print_error']
            }

        # Recreate statement info (cursor will be created fresh)
        restored_statement = {
            'connection_id': connection_id,
            'sql': statement_metadata['sql'],
            'cursor': None,  # Will be created on demand
            'executed': False,  # Reset execution state (cursor is fresh)
            'finished': False,
            'peeked_row': statement_metadata.get('peeked_row')  # Restore saved peeked row data
        }

        return restored_statement

    except Exception:
        return None

def _ensure_connection_available(connection_id: str) -> Dict[str, Any]:
    """Helper function to ensure connection is available (restore if needed)"""
    if connection_id not in _connections:
        debug_info = f"Connection {connection_id} not in memory, attempting to restore from persistent storage"

        # Load connection metadata from persistent storage
        metadata = _load_connection_metadata(connection_id)
        if not metadata:
            return {
                'success': False,
                'error': 'Invalid connection ID',
                'debug_info': f'Connection {connection_id} not found in persistent storage'
            }

        # Restore connection from metadata
        conn = _restore_connection_from_metadata(metadata)
        if not conn:
            _remove_connection_metadata(connection_id)  # Remove stale metadata
            return {
                'success': False,
                'error': 'Failed to restore connection - credentials may have changed',
                'debug_info': 'Connection restoration failed'
            }

        # Store restored connection in memory
        _connections[connection_id] = {
            'connection': conn,
            'type': metadata['type'],
            'dsn': metadata['dsn'],
            'username': metadata['username'],
            'autocommit': metadata['autocommit'],
            'raise_error': metadata['raise_error'],
            'print_error': metadata['print_error']
        }

        debug_info += " - Connection successfully restored"
    else:
        debug_info = f"Connection {connection_id} found in memory"

    return {'success': True, 'debug_info': debug_info}

def _make_cache_key(dsn: str, username: str, options: Dict = None) -> str:
    """
    Generate cache key for connection caching

    Cache key is based on DSN, username, and connection attributes.
    Password is NOT part of the cache key (DBI behavior).

    Format: "oracle:{database}:{username}:ac{0|1}_re{0|1}_pe{0|1}"
    Example: "oracle:PROD:user1:ac0_re1_pe0"
    """
    # Parse DSN to get database identifier
    db_info = _parse_oracle_dsn(dsn)
    database = db_info.get('tns') or db_info.get('service_name') or db_info.get('sid', 'unknown')

    # Extract connection attributes (with defaults matching DBI)
    opts = options or {}
    autocommit = 1 if opts.get('AutoCommit', True) else 0
    raise_error = 1 if opts.get('RaiseError', False) else 0
    print_error = 1 if opts.get('PrintError', True) else 0

    # Build attribute signature
    attr_sig = f"ac{autocommit}_re{raise_error}_pe{print_error}"

    # Generate cache key
    cache_key = f"oracle:{database}:{username}:{attr_sig}"

    return cache_key

def _is_connection_alive(conn: Any) -> bool:
    """
    Validate that database connection is still alive

    Uses lightweight query to ping the database.
    Returns True if connection is usable, False otherwise.
    """
    try:
        cursor = conn.cursor()
        cursor.execute("SELECT 1 FROM DUAL")  # Oracle ping query
        cursor.fetchone()
        cursor.close()
        return True
    except Exception:
        # Connection is dead/broken
        return False

def _cleanup_stale_cache_entries():
    """
    Remove stale entries from connection cache

    Removes:
    1. Connections idle longer than _CACHE_IDLE_TIMEOUT
    2. Dead/broken connections

    Enforces _CACHE_MAX_SIZE limit using LRU eviction.
    """
    global _CONNECTION_CACHE

    current_time = time.time()
    keys_to_remove = []

    # Find stale entries
    for cache_key, cache_entry in _CONNECTION_CACHE.items():
        age = current_time - cache_entry['last_used']

        if age > _CACHE_IDLE_TIMEOUT:
            # Idle too long
            keys_to_remove.append(cache_key)
        elif not _is_connection_alive(cache_entry['connection']['connection']):
            # Connection is dead
            keys_to_remove.append(cache_key)

    # Remove stale entries
    for key in keys_to_remove:
        entry = _CONNECTION_CACHE[key]
        try:
            # Try to close the connection gracefully
            entry['connection']['connection'].close()
        except:
            pass

        # Remove from cache
        del _CONNECTION_CACHE[key]

        # Also remove from _connections if present
        if entry['connection_id'] in _connections:
            del _connections[entry['connection_id']]

    # Enforce size limit using LRU eviction
    if len(_CONNECTION_CACHE) > _CACHE_MAX_SIZE:
        # Sort by last_used (oldest first)
        sorted_entries = sorted(
            _CONNECTION_CACHE.items(),
            key=lambda x: x[1]['last_used']
        )

        # Remove oldest entries until we're under the limit
        num_to_remove = len(_CONNECTION_CACHE) - _CACHE_MAX_SIZE
        for i in range(num_to_remove):
            key, entry = sorted_entries[i]

            try:
                entry['connection']['connection'].close()
            except:
                pass

            del _CONNECTION_CACHE[key]

            if entry['connection_id'] in _connections:
                del _connections[entry['connection_id']]

def connect(dsn: str, username: str = '', password: str = '', options: Dict = None, db_type: str = '', auth_mode: str = 'auto') -> Dict[str, Any]:
    """
    Connect to Oracle database using oracledb driver

    Supports two authentication modes:
    - 'password': Traditional username/password
    - 'kerberos': Kerberos ticket-based authentication
    - 'auto': Auto-detect based on environment variables (default)

    Auto-detection logic:
    - If KRB5_CONFIG and KRB5CCNAME are both set -> Kerberos
    - Otherwise -> Password authentication

    For Kerberos, set environment variables:
    - KRB5_CONFIG: Path to krb5.conf
    - KRB5CCNAME: Path to credential cache
    """
    try:
        connection_id = str(uuid.uuid4())

        # Auto-detect authentication mode based on environment variables
        actual_auth_mode = auth_mode
        if auth_mode == 'auto':
            # Check if Kerberos environment variables are set
            krb5_config = os.getenv("KRB5_CONFIG")
            krb5_ccname = os.getenv("KRB5CCNAME")

            if krb5_config and krb5_ccname:
                # Both Kerberos env vars present -> use Kerberos
                actual_auth_mode = 'kerberos'
            else:
                # Kerberos env vars missing -> use password
                actual_auth_mode = 'password'

        # Handle Oracle TNS-in-username pattern: "dbi:Oracle:" with "user@TNS_NAME"
        actual_username = username
        if '@' in username:
            actual_username, tns_name = username.split('@', 1)
            # If DSN is minimal, use TNS from username
            if dsn in ['dbi:Oracle:', 'dbi:Oracle', 'dbi:Ora:', 'dbi:Ora']:
                dsn = tns_name

        # Parse Oracle connection details
        connection_params = _parse_oracle_dsn(dsn)

        # Route to appropriate authentication method
        if actual_auth_mode == 'kerberos':
            conn = _connect_oracle_kerberos(connection_params, actual_username, options)
        else:  # password (default)
            conn = _connect_oracle(connection_params, actual_username, password, options)

        if not conn:
            raise RuntimeError("Failed to establish Oracle database connection")

        # Store connection with metadata
        connection_metadata = {
            'connection': conn,
            'type': 'oracle',
            'dsn': dsn,
            'username': actual_username,
            'auth_mode': actual_auth_mode,  # Track auth mode
            'autocommit': options.get('AutoCommit', True) if options else True,
            'raise_error': options.get('RaiseError', False) if options else False,
            'print_error': options.get('PrintError', True) if options else True,
            'last_error': None  # DBI errstr() compatibility
        }
        _connections[connection_id] = connection_metadata

        # Configure autocommit
        conn.autocommit = connection_metadata['autocommit']

        # Save connection metadata to persistent storage (only save password for password auth)
        _save_connection_metadata(
            connection_id,
            connection_metadata,
            password if actual_auth_mode == 'password' else '',
            actual_auth_mode
        )

        return {
            'success': True,
            'connection_id': connection_id,
            'db_type': 'oracle',
            'auth_mode': actual_auth_mode
        }

    except Exception as e:
        return {
            'success': False,
            'error': str(e),
            'traceback': traceback.format_exc()
        }

def connect_cached(dsn: str, username: str = '', password: str = '', options: Dict = None, db_type: str = '', auth_mode: str = 'auto') -> Dict[str, Any]:
    """
    Connect to Oracle database with connection caching (mimics DBI->connect_cached())

    Returns cached connection if available and valid, otherwise creates new connection.

    Cache key is based on: (dsn, username, AutoCommit, RaiseError, PrintError)
    Password is NOT part of cache key (DBI behavior).

    Parameters same as connect():
    - dsn: Database connection string
    - username: Database username
    - password: Database password (not used for cache lookup)
    - options: Connection options (AutoCommit, RaiseError, PrintError, etc.)
    - db_type: Database type (currently only 'oracle')
    - auth_mode: Authentication mode ('auto', 'password', 'kerberos')

    Returns:
        Dict with success status and connection_id (reused or new)

    Cache Configuration:
    - Max size: 50 connections (_CACHE_MAX_SIZE)
    - Idle timeout: 10 minutes (_CACHE_IDLE_TIMEOUT)
    - Validation: Every call (ensures connection is alive)
    - Eviction: LRU (Least Recently Used)
    """
    global _CONNECTION_CACHE

    try:
        # Step 1: Cleanup stale cache entries before lookup
        _cleanup_stale_cache_entries()

        # Step 2: Generate cache key
        cache_key = _make_cache_key(dsn, username, options)

        # Step 3: Check if connection exists in cache
        if cache_key in _CONNECTION_CACHE:
            cache_entry = _CONNECTION_CACHE[cache_key]

            # Step 4: Validate cached connection is still alive
            if _is_connection_alive(cache_entry['connection']['connection']):
                # Connection is alive - update last_used and return
                cache_entry['last_used'] = time.time()

                return {
                    'success': True,
                    'connection_id': cache_entry['connection_id'],
                    'db_type': 'oracle',
                    'auth_mode': cache_entry['connection']['auth_mode'],
                    'cached': True  # Indicate this was from cache
                }
            else:
                # Connection is dead - remove from cache
                try:
                    cache_entry['connection']['connection'].close()
                except:
                    pass

                del _CONNECTION_CACHE[cache_key]

                if cache_entry['connection_id'] in _connections:
                    del _connections[cache_entry['connection_id']]

                # Fall through to create new connection

        # Step 5: No valid cached connection - create new one
        result = connect(dsn, username, password, options, db_type, auth_mode)

        if not result['success']:
            return result

        # Step 6: Store in cache
        connection_id = result['connection_id']

        _CONNECTION_CACHE[cache_key] = {
            'connection_id': connection_id,
            'connection': _connections[connection_id],
            'created_at': time.time(),
            'last_used': time.time(),
            'dsn': dsn,
            'username': username,
            'options': options,
            'cache_key': cache_key
        }

        # Mark as new (not cached)
        result['cached'] = False

        return result

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


def _convert_placeholders_to_oracle(sql: str) -> str:
    """Convert DBI-style ? placeholders to Oracle-style :1, :2, etc."""
    counter = 1
    result = []
    i = 0
    in_string = False
    string_char = None

    while i < len(sql):
        char = sql[i]

        # Track string literals to avoid replacing ? inside strings
        if char in ("'", '"'):
            if not in_string:
                in_string = True
                string_char = char
            elif char == string_char:
                in_string = False
                string_char = None

        # Replace ? with :N outside of strings
        if char == '?' and not in_string:
            result.append(f':{counter}')
            counter += 1
        else:
            result.append(char)

        i += 1

    return ''.join(result)

def prepare(connection_id: str, sql: str) -> Dict[str, Any]:
    """Prepare SQL statement"""
    try:
        # Try to restore connection if not in memory
        if connection_id not in _connections:
            debug_info = f"Connection {connection_id} not in memory, attempting to restore from persistent storage"

            # Load connection metadata from persistent storage
            metadata = _load_connection_metadata(connection_id)
            if not metadata:
                return {
                    'success': False,
                    'error': 'Invalid connection ID',
                    'debug_info': f'Connection {connection_id} not found in persistent storage'
                }

            # Restore connection from metadata
            conn = _restore_connection_from_metadata(metadata)
            if not conn:
                _remove_connection_metadata(connection_id)  # Remove stale metadata
                return {
                    'success': False,
                    'error': 'Failed to restore connection - credentials may have changed',
                    'debug_info': 'Connection restoration failed'
                }

            # Store restored connection in memory
            _connections[connection_id] = {
                'connection': conn,
                'type': metadata['type'],
                'dsn': metadata['dsn'],
                'username': metadata['username'],
                'autocommit': metadata['autocommit'],
                'raise_error': metadata['raise_error'],
                'print_error': metadata['print_error']
            }

            debug_info += " - Connection successfully restored"
        else:
            debug_info = f"Connection {connection_id} found in memory"

        statement_id = str(uuid.uuid4())
        conn_info = _connections[connection_id]

        # Convert DBI-style ? placeholders to Oracle-style :1, :2, etc.
        oracle_sql = _convert_placeholders_to_oracle(sql)

        # Store statement info (cursor will be created on execute)
        statement_metadata = {
            'connection_id': connection_id,
            'sql': oracle_sql,  # Store converted SQL
            'original_sql': sql,  # Keep original for reference
            'cursor': None,
            'executed': False,
            'finished': False,
            'out_params': {},  # Store OUT/INOUT parameter bindings
            'last_error': None  # DBI errstr() compatibility
        }
        _statements[statement_id] = statement_metadata

        # Save statement metadata to persistent storage for cross-process access
        _save_statement_metadata(statement_id, statement_metadata)
        
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
        # Try to restore connection if not in memory
        if connection_id not in _connections:
            debug_info = f"Connection {connection_id} not in memory, attempting to restore from persistent storage"

            # Load connection metadata from persistent storage
            metadata = _load_connection_metadata(connection_id)
            if not metadata:
                return {
                    'success': False,
                    'error': 'Invalid connection ID',
                    'debug_info': f'Connection {connection_id} not found in persistent storage'
                }

            # Restore connection from metadata
            conn = _restore_connection_from_metadata(metadata)
            if not conn:
                _remove_connection_metadata(connection_id)  # Remove stale metadata
                return {
                    'success': False,
                    'error': 'Failed to restore connection - credentials may have changed',
                    'debug_info': 'Connection restoration failed'
                }

            # Store restored connection in memory
            _connections[connection_id] = {
                'connection': conn,
                'type': metadata['type'],
                'dsn': metadata['dsn'],
                'username': metadata['username'],
                'autocommit': metadata['autocommit'],
                'raise_error': metadata['raise_error'],
                'print_error': metadata['print_error']
            }

            debug_info += " - Connection successfully restored"
        else:
            debug_info = f"Connection {connection_id} found in memory"

        # Try to restore statement if not in memory
        if statement_id not in _statements:
            debug_info += f" - Statement {statement_id} not in memory, attempting to restore from persistent storage"

            # Load statement metadata from persistent storage
            stmt_metadata = _load_statement_metadata(statement_id)
            if not stmt_metadata:
                return {
                    'success': False,
                    'error': 'Invalid statement ID',
                    'debug_info': debug_info + f' - Statement {statement_id} not found in persistent storage'
                }

            # Restore statement from metadata (this also restores connection if needed)
            restored_statement = _restore_statement_from_metadata(stmt_metadata)
            if not restored_statement:
                _remove_statement_metadata(statement_id)  # Remove stale metadata
                return {
                    'success': False,
                    'error': 'Failed to restore statement - connection may have expired',
                    'debug_info': debug_info + ' - Statement restoration failed'
                }

            # Store restored statement in memory
            _statements[statement_id] = restored_statement
            debug_info += " - Statement successfully restored"
        else:
            debug_info += f" - Statement {statement_id} found in memory"
        
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

        # Handle OUT/INOUT parameters
        out_param_vars = {}
        if stmt_info.get('out_params'):
            for param_name, param_info in stmt_info['out_params'].items():
                # Create cursor variable for OUT parameter
                var = cursor.var(
                    param_info['oracle_type'],
                    size=param_info['size']
                )

                # Set initial value for INOUT parameters
                if param_info['initial_value'] is not None:
                    var.setvalue(0, param_info['initial_value'])

                # Store the variable
                out_param_vars[param_name] = var
                param_info['var'] = var

        # Build bind parameters dict for OUT/INOUT
        if out_param_vars:
            # Combine IN and OUT parameters
            all_params = {}

            # Add IN parameters
            if bind_values:
                for i, val in enumerate(bind_values):
                    all_params[f':{i+1}'] = val

            # Add OUT/INOUT parameters
            all_params.update(out_param_vars)

            # Execute with combined parameters
            cursor.execute(stmt_info['sql'], all_params)
        elif final_bind_values:
            # Execute with IN parameters only
            cursor.execute(stmt_info['sql'], final_bind_values)
        else:
            # Execute without parameters
            cursor.execute(stmt_info['sql'])

        # Debug: Log execution details (removed direct stderr output that corrupts JSON)

        stmt_info['executed'] = True

        # Detect SQL statement type for Oracle-specific handling
        sql_upper = stmt_info['sql'].strip().upper()
        is_select = sql_upper.startswith('SELECT')

        # Get enhanced column information with Oracle-specific handling
        column_info = None
        rows_affected = getattr(cursor, 'rowcount', 0)

        if is_select:
            # For SELECT statements, Oracle needs special handling
            # Processing SELECT statement

            if hasattr(cursor, 'description') and cursor.description:
                # Description is already available - use enhanced metadata extractor (Phase 2)
                column_info = _extract_column_metadata(cursor)
                # Column info available immediately
            else:
                # Try to peek at cursor to populate description (Oracle behavior)
                # Column info not available, attempting peek
                try:
                    original_arraysize = getattr(cursor, 'arraysize', 1)
                    cursor.arraysize = 1
                    peek_row = cursor.fetchone()

                    if peek_row is not None and hasattr(cursor, 'description') and cursor.description:
                        # Use enhanced metadata extractor (Phase 2)
                        column_info = _extract_column_metadata(cursor)
                        # Store the peeked row for later retrieval
                        stmt_info['peeked_row'] = peek_row
                        # Peek successful

                        # For SELECT with data, set rows_affected = 1 (indicates data available)
                        rows_affected = 1
                    else:
                        # Peek returned no data
                        rows_affected = 0

                    cursor.arraysize = original_arraysize

                except Exception as peek_error:
                    # Peek failed
                    rows_affected = 0

        else:
            # For non-SELECT statements (INSERT, UPDATE, DELETE, etc.)
            # Processing non-SELECT statement

            # Try to get column info if available (some statements might return data)
            # Use enhanced metadata extractor (Phase 2)
            column_info = _extract_column_metadata(cursor)
            # Non-SELECT statement has column info

            # rows_affected from rowcount is typically reliable for non-SELECT statements

        # Save updated statement metadata including peeked_row to persistent storage
        _save_statement_metadata(statement_id, stmt_info)

        return {
            'success': True,
            'rows_affected': rows_affected,
            'column_info': column_info,
            'debug_info': debug_info
        }
        
    except Exception as e:
        return {
            'success': False,
            'error': str(e)
        }

def fetch_row(connection_id: str, statement_id: str, format: str = 'array') -> Dict[str, Any]:
    """Fetch single row with enhanced tracking"""
    try:
        # Try to restore statement if not in memory
        if statement_id not in _statements:
            debug_info = f"Statement {statement_id} not in memory, attempting to restore from persistent storage"

            # Load statement metadata from persistent storage
            stmt_metadata = _load_statement_metadata(statement_id)
            if not stmt_metadata:
                return {
                    'success': False,
                    'error': 'Invalid statement ID',
                    'debug_info': f'Statement {statement_id} not found in persistent storage'
                }

            # Restore statement from metadata (this also restores connection if needed)
            restored_statement = _restore_statement_from_metadata(stmt_metadata)
            if not restored_statement:
                _remove_statement_metadata(statement_id)  # Remove stale metadata
                return {
                    'success': False,
                    'error': 'Failed to restore statement - connection may have expired',
                    'debug_info': 'Statement restoration failed'
                }

            # Store restored statement in memory
            _statements[statement_id] = restored_statement

            # Automatically re-execute the restored statement for fetch operations
            # This is safe since we have the original SQL and connection
            debug_info += " - Re-executing restored statement for fetch"

            try:
                # Get the connection and create a fresh cursor
                connection_id = restored_statement['connection_id']
                if connection_id not in _connections:
                    return {
                        'success': False,
                        'error': 'Connection lost during statement restoration',
                        'debug_info': debug_info
                    }

                conn = _connections[connection_id]['connection']
                cursor = conn.cursor()

                # Execute the original SQL
                cursor.execute(restored_statement['sql'])

                # Preserve the peeked_row if it was restored from metadata
                preserved_peeked_row = restored_statement.get('peeked_row')

                # Update the statement info
                restored_statement['cursor'] = cursor
                restored_statement['executed'] = True

                # Restore the peeked_row data if it was saved
                if preserved_peeked_row is not None:
                    restored_statement['peeked_row'] = preserved_peeked_row

                _statements[statement_id] = restored_statement

                debug_info += " - Statement re-executed successfully"

            except Exception as e:
                return {
                    'success': False,
                    'error': f'Failed to re-execute restored statement: {str(e)}',
                    'debug_info': debug_info
                }

        else:
            debug_info = f"Statement {statement_id} found in memory"
        
        stmt_info = _statements[statement_id]
        
        if not stmt_info['executed']:
            raise ValueError("Statement not executed")
        
        if stmt_info['finished']:
            return {'success': False}
        
        cursor = stmt_info['cursor']

        # Check if we have a peeked row from execute_statement
        if 'peeked_row' in stmt_info and stmt_info['peeked_row'] is not None:
            row = stmt_info['peeked_row']
            del stmt_info['peeked_row']  # Remove it so it's only returned once
        else:
            # No peeked row available, fetch from cursor
            try:
                row = cursor.fetchone()
            except Exception as fetch_error:
                row = None

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
        # Try to restore statement if not in memory (same logic as fetch_row)
        if statement_id not in _statements:
            debug_info = f"Statement {statement_id} not in memory, attempting to restore from persistent storage"

            # Load statement metadata from persistent storage
            stmt_metadata = _load_statement_metadata(statement_id)
            if not stmt_metadata:
                return {
                    'success': False,
                    'error': 'Invalid statement ID',
                    'debug_info': f'Statement {statement_id} not found in persistent storage'
                }

            # Restore statement from metadata (this also restores connection if needed)
            restored_statement = _restore_statement_from_metadata(stmt_metadata)
            if not restored_statement:
                _remove_statement_metadata(statement_id)  # Remove stale metadata
                return {
                    'success': False,
                    'error': 'Failed to restore statement - connection may have expired',
                    'debug_info': 'Statement restoration failed'
                }

            # Store restored statement in memory
            _statements[statement_id] = restored_statement

            # Automatically re-execute the restored statement for fetch operations
            # This is safe since we have the original SQL and connection
            debug_info += " - Re-executing restored statement for fetch_all"

            try:
                # Get the connection and create a fresh cursor
                connection_id = restored_statement['connection_id']
                if connection_id not in _connections:
                    return {
                        'success': False,
                        'error': 'Connection lost during statement restoration',
                        'debug_info': debug_info
                    }

                conn = _connections[connection_id]['connection']
                cursor = conn.cursor()

                # Execute the original SQL
                cursor.execute(restored_statement['sql'])

                # Update the statement info
                restored_statement['cursor'] = cursor
                restored_statement['executed'] = True
                _statements[statement_id] = restored_statement

                debug_info += " - Statement re-executed successfully for fetch_all"

            except Exception as e:
                return {
                    'success': False,
                    'error': f'Failed to re-execute restored statement: {str(e)}',
                    'debug_info': debug_info
                }

        else:
            debug_info = f"Statement {statement_id} found in memory"

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
    """Execute SQL immediately without preparation

    Enhanced to fetch and return results for SELECT queries while maintaining
    backward compatibility for DML statements (INSERT, UPDATE, DELETE).
    """
    try:
        # Ensure connection is available (restore if needed)
        conn_result = _ensure_connection_available(connection_id)
        if not conn_result['success']:
            return conn_result

        conn_info = _connections[connection_id]
        conn = conn_info['connection']
        cursor = conn.cursor()

        # Execute SQL
        if bind_values:
            cursor.execute(sql, bind_values)
        else:
            cursor.execute(sql)

        # Detect SQL statement type
        sql_upper = sql.strip().upper()
        is_select = sql_upper.startswith('SELECT') or sql_upper.startswith('WITH')

        response = {'success': True}

        if is_select:
            # Fetch results for SELECT queries
            rows = cursor.fetchall()
            result_data = [list(row) for row in rows] if rows else []

            # Get column information with enhanced metadata (Phase 2)
            column_info = _extract_column_metadata(cursor)

            response['rows'] = result_data
            response['rows_affected'] = len(result_data)
            response['column_info'] = column_info
        else:
            # For DML statements (INSERT, UPDATE, DELETE)
            rows_affected = getattr(cursor, 'rowcount', 0)
            response['rows_affected'] = rows_affected

            # Auto-commit if enabled
            if conn_info['autocommit']:
                conn.commit()

        cursor.close()
        return response

    except Exception as e:
        return {
            'success': False,
            'error': str(e)
        }

def do_statement(connection_id: str, sql: str, bind_values: List = None) -> Dict[str, Any]:
    """
    Execute SQL statement immediately (mimics DBI->do())

    This is an alias for execute_immediate() to maintain DBI API compatibility.

    Args:
        connection_id: Database connection ID
        sql: SQL statement to execute
        bind_values: Optional list of bind values

    Returns:
        Dict with success status and rows_affected

    Usage Pattern (from CPS::SQL):
        $dbh->do("ALTER SESSION SET NLS_DATE_FORMAT='MM/DD/YYYY HH:MI:SS AM'");
        $dbh->do("INSERT INTO table VALUES (?, ?)", undef, $val1, $val2);
    """
    return execute_immediate(connection_id, sql, bind_values)

def begin_transaction(connection_id: str) -> Dict[str, Any]:
    """Begin database transaction"""
    try:
        # Ensure connection is available (restore if needed)
        conn_result = _ensure_connection_available(connection_id)
        if not conn_result['success']:
            return conn_result
        
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
        # Ensure connection is available (restore if needed)
        conn_result = _ensure_connection_available(connection_id)
        if not conn_result['success']:
            return conn_result
        
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
        # Ensure connection is available (restore if needed)
        conn_result = _ensure_connection_available(connection_id)
        if not conn_result['success']:
            return conn_result
        
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
        
        # Clean up associated statements (both in memory and persistent storage)
        statements_to_remove = [
            sid for sid, stmt in _statements.items()
            if stmt['connection_id'] == connection_id
        ]
        for sid in statements_to_remove:
            del _statements[sid]
            _remove_statement_metadata(sid)  # Clean up persistent storage

        # Clean up connection from persistent storage
        _remove_connection_metadata(connection_id)
        
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

def bind_param_inout(statement_id: str, param_name: str, initial_value: Any = None,
                     size: int = 4000, param_type: Dict = None) -> Dict[str, Any]:
    """
    Bind input/output parameter for stored procedures (mimics DBI->bind_param_inout())

    Args:
        statement_id: Statement handle ID
        param_name: Parameter name (e.g., ':1', ':param_name', or positional 1, 2, etc.)
        initial_value: Initial value for INOUT parameters (None for OUT only)
        size: Maximum size for output value (default 4000 for strings/CLOBs)
        param_type: Oracle type specification (e.g., {'ora_type': 112} for CLOB)

    Returns:
        Dict with success status

    Usage Pattern (from CPS::SQL):
        $sth->bind_param_inout(':param1', \\$out_var, 4000);
        $sth->bind_param_inout(':clob_param', \\$clob_var, 32000, { ora_type => 112 });
    """
    try:
        if statement_id not in _statements:
            return {
                'success': False,
                'error': f'Invalid statement ID: {statement_id}'
            }

        stmt_info = _statements[statement_id]

        # Determine Oracle data type
        oracle_type = oracledb.DB_TYPE_VARCHAR

        if param_type and isinstance(param_type, dict):
            ora_type = param_type.get('ora_type')
            if ora_type == 112:  # Oracle CLOB type
                oracle_type = oracledb.DB_TYPE_CLOB
            elif ora_type == 113:  # Oracle BLOB type
                oracle_type = oracledb.DB_TYPE_BLOB

        # Normalize parameter name
        if isinstance(param_name, int):
            # Convert positional to Oracle format (:1, :2, etc.)
            normalized_param = f':{param_name}'
        elif isinstance(param_name, str):
            if not param_name.startswith(':'):
                normalized_param = f':{param_name}'
            else:
                normalized_param = param_name
        else:
            normalized_param = str(param_name)

        # Create variable to hold output value
        # The cursor.var() creates a Python variable that Oracle can write to
        out_var = None  # Will be created when cursor is available

        # Store parameter binding info
        stmt_info['out_params'][normalized_param] = {
            'initial_value': initial_value,
            'size': size,
            'oracle_type': oracle_type,
            'var': out_var,  # Will be set during execute
            'param_type': param_type
        }

        return {
            'success': True,
            'message': f'OUT/INOUT parameter {normalized_param} bound successfully'
        }

    except Exception as e:
        return {
            'success': False,
            'error': str(e),
            'traceback': traceback.format_exc()
        }

def get_out_params(statement_id: str) -> Dict[str, Any]:
    """
    Get OUT/INOUT parameter values after statement execution

    Args:
        statement_id: Statement handle ID

    Returns:
        Dict with success status and output parameter values

    Usage:
        After calling execute_statement(), call this to get OUT parameter values
    """
    try:
        if statement_id not in _statements:
            return {
                'success': False,
                'error': f'Invalid statement ID: {statement_id}'
            }

        stmt_info = _statements[statement_id]

        if not stmt_info.get('executed'):
            return {
                'success': False,
                'error': 'Statement not yet executed'
            }

        out_values = {}

        if stmt_info.get('out_params'):
            for param_name, param_info in stmt_info['out_params'].items():
                var = param_info.get('var')
                if var:
                    # Get value from cursor variable
                    value = var.getvalue()

                    # Handle CLOB/BLOB - convert to string
                    if param_info['oracle_type'] == oracledb.DB_TYPE_CLOB:
                        if value is not None:
                            value = value.read() if hasattr(value, 'read') else str(value)
                    elif param_info['oracle_type'] == oracledb.DB_TYPE_BLOB:
                        if value is not None:
                            value = value.read() if hasattr(value, 'read') else bytes(value)

                    # Remove leading : from parameter name for return
                    clean_name = param_name[1:] if param_name.startswith(':') else param_name
                    out_values[clean_name] = value

        return {
            'success': True,
            'out_params': out_values
        }

    except Exception as e:
        return {
            'success': False,
            'error': str(e),
            'traceback': traceback.format_exc()
        }

def get_connection_error(connection_id: str) -> Dict[str, Any]:
    """
    Get last error from database handle (mimics DBI->errstr)

    Args:
        connection_id: Connection handle ID

    Returns:
        Dict with success status and error string

    Usage Pattern (from DbAccess.pm):
        my $dbh = DBI->connect(...) or die $dbh->errstr;
        $error_msg = $dbh->errstr if $dbh;
    """
    try:
        if connection_id not in _connections:
            return {
                'success': False,
                'error': f'Invalid connection ID: {connection_id}'
            }

        conn_info = _connections[connection_id]
        last_error = conn_info.get('last_error')

        return {
            'success': True,
            'errstr': last_error if last_error else ''
        }

    except Exception as e:
        return {
            'success': False,
            'error': str(e),
            'traceback': traceback.format_exc()
        }

def get_statement_error(statement_id: str) -> Dict[str, Any]:
    """
    Get last error from statement handle (mimics DBI->errstr)

    Args:
        statement_id: Statement handle ID

    Returns:
        Dict with success status and error string

    Usage Pattern (from DbAccess.pm):
        my $sth = $dbh->prepare($sql) or die $dbh->errstr;
        $stmt_error_str = $sth->errstr() if ($sth);
    """
    try:
        if statement_id not in _statements:
            return {
                'success': False,
                'error': f'Invalid statement ID: {statement_id}'
            }

        stmt_info = _statements[statement_id]
        last_error = stmt_info.get('last_error')

        return {
            'success': True,
            'errstr': last_error if last_error else ''
        }

    except Exception as e:
        return {
            'success': False,
            'error': str(e),
            'traceback': traceback.format_exc()
        }