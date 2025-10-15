"""
FTP Helper Module for CPAN Bridge
Provides Net::FTP replacement using Python ftplib

This module implements connection pooling for FTP sessions to maintain
state across multiple Perl -> Python bridge calls.

Key Features:
- Connection pooling with unique connection IDs
- Thread-safe connection management
- Transfer mode tracking (binary/ascii)
- Error message compatibility with Net::FTP
- Automatic connection cleanup after 5 minutes of inactivity
- Support for all Net::FTP methods used in production code

Architecture:
1. new() creates FTP connection and returns unique connection_id
2. Connection state maintained in _ftp_connections pool
3. All methods use connection_id to identify their connection
4. Connections auto-cleanup after 300 seconds (5 minutes) of inactivity
5. quit() explicitly removes connection from pool

Supported Methods:
- new(host, debug, timeout)
- login(connection_id, user, password)
- cwd(connection_id, directory)
- pwd(connection_id)
- dir(connection_id, path)
- binary(connection_id)
- ascii(connection_id)
- get(connection_id, remote_file, local_file)
- put(connection_id, local_file, remote_file)
- delete(connection_id, remote_file)
- rename(connection_id, old_name, new_name)
- message(connection_id)
- quit(connection_id)
"""

import ftplib
import threading
import time
import uuid
import os
from typing import Dict, Any, Optional, List

# Connection pool storage
_ftp_connections: Dict[str, Dict[str, Any]] = {}
_connections_lock = threading.Lock()

# Configuration
CONNECTION_CLEANUP_TIMEOUT = 300  # 5 minutes in seconds
DEFAULT_TIMEOUT = 60  # Default timeout in seconds

# Transfer modes
MODE_BINARY = 'binary'
MODE_ASCII = 'ascii'

# Connection states
STATE_CONNECTED = 'connected'
STATE_LOGGED_IN = 'logged_in'
STATE_CLOSED = 'closed'


def new(host: str, debug: int = 0, timeout: int = DEFAULT_TIMEOUT) -> Dict[str, Any]:
    """
    Create a new FTP connection.

    Args:
        host: FTP server hostname or IP address
        debug: Debug level (0=off, 1=on, 2=verbose)
        timeout: Connection timeout in seconds (default: 60)

    Returns:
        Dict with success status and connection_id, or error message
        {
            'success': True,
            'connection_id': 'ftp_1234567890_abcd1234'
        }
        or
        {
            'success': False,
            'error': 'Connection failed: ...'
        }
    """
    try:
        # Create FTP connection
        ftp = ftplib.FTP(timeout=timeout)

        # Set debug level
        if debug > 0:
            ftp.set_debuglevel(2 if debug > 1 else 1)

        # Connect to server
        ftp.connect(host)

        # Generate unique connection ID
        connection_id = f"ftp_{int(time.time())}_{uuid.uuid4().hex[:8]}"

        # Store connection in pool
        with _connections_lock:
            _ftp_connections[connection_id] = {
                'client': ftp,
                'host': host,
                'state': STATE_CONNECTED,
                'transfer_mode': MODE_BINARY,  # Default to binary mode
                'last_message': '',
                'created_at': time.time(),
                'last_used': time.time(),
                'lock': threading.Lock()
            }

        return {
            'success': True,
            'connection_id': connection_id
        }

    except ftplib.all_errors as e:
        error_msg = f"Connection failed: {str(e)}"
        return {
            'success': False,
            'error': error_msg
        }
    except Exception as e:
        error_msg = f"Unexpected error creating FTP connection: {str(e)}"
        return {
            'success': False,
            'error': error_msg
        }


def login(connection_id: str, user: str, password: str) -> Dict[str, Any]:
    """
    Authenticate with FTP server.

    Args:
        connection_id: Connection ID from new()
        user: Username for authentication
        password: Password for authentication

    Returns:
        Dict with success status or error message
    """
    conn = _get_connection(connection_id)
    if not conn:
        return {
            'success': False,
            'error': f"Invalid connection ID: {connection_id}"
        }

    try:
        with conn['lock']:
            ftp = conn['client']

            # Perform login
            ftp.login(user, password)

            # Update connection state
            conn['state'] = STATE_LOGGED_IN
            conn['last_used'] = time.time()
            conn['last_message'] = ftp.lastresp

            return {
                'success': True,
                'message': ftp.lastresp
            }

    except ftplib.error_perm as e:
        error_msg = str(e)
        conn['last_message'] = error_msg
        return {
            'success': False,
            'error': f"Login failed: {error_msg}"
        }
    except ftplib.all_errors as e:
        error_msg = str(e)
        conn['last_message'] = error_msg
        return {
            'success': False,
            'error': f"Login error: {error_msg}"
        }


def cwd(connection_id: str, directory: str) -> Dict[str, Any]:
    """
    Change working directory on FTP server.

    Args:
        connection_id: Connection ID from new()
        directory: Directory path to change to

    Returns:
        Dict with success status or error message
    """
    conn = _get_connection(connection_id)
    if not conn:
        return {
            'success': False,
            'error': f"Invalid connection ID: {connection_id}"
        }

    try:
        with conn['lock']:
            ftp = conn['client']

            # Change directory
            ftp.cwd(directory)

            # Update connection state
            conn['last_used'] = time.time()
            conn['last_message'] = ftp.lastresp

            return {
                'success': True,
                'message': ftp.lastresp
            }

    except ftplib.error_perm as e:
        error_msg = str(e)
        conn['last_message'] = error_msg
        return {
            'success': False,
            'error': f"Directory change failed: {error_msg}"
        }
    except ftplib.all_errors as e:
        error_msg = str(e)
        conn['last_message'] = error_msg
        return {
            'success': False,
            'error': f"CWD error: {error_msg}"
        }


def pwd(connection_id: str) -> Dict[str, Any]:
    """
    Get current working directory on FTP server.

    Args:
        connection_id: Connection ID from new()

    Returns:
        Dict with success status and directory path, or error message
    """
    conn = _get_connection(connection_id)
    if not conn:
        return {
            'success': False,
            'error': f"Invalid connection ID: {connection_id}"
        }

    try:
        with conn['lock']:
            ftp = conn['client']

            # Get current directory
            current_dir = ftp.pwd()

            # Update connection state
            conn['last_used'] = time.time()
            conn['last_message'] = ftp.lastresp

            return {
                'success': True,
                'directory': current_dir,
                'message': ftp.lastresp
            }

    except ftplib.all_errors as e:
        error_msg = str(e)
        conn['last_message'] = error_msg
        return {
            'success': False,
            'error': f"PWD error: {error_msg}"
        }


def dir(connection_id: str, path: str = "") -> Dict[str, Any]:
    """
    Get directory listing from FTP server.

    Args:
        connection_id: Connection ID from new()
        path: Optional path to list (default: current directory)

    Returns:
        Dict with success status and file list, or error message
    """
    conn = _get_connection(connection_id)
    if not conn:
        return {
            'success': False,
            'error': f"Invalid connection ID: {connection_id}"
        }

    try:
        with conn['lock']:
            ftp = conn['client']

            # Get directory listing
            listing = []

            def collect_lines(line):
                listing.append(line)

            if path:
                ftp.retrlines(f'LIST {path}', collect_lines)
            else:
                ftp.retrlines('LIST', collect_lines)

            # Update connection state
            conn['last_used'] = time.time()
            conn['last_message'] = ftp.lastresp

            return {
                'success': True,
                'listing': listing,
                'message': ftp.lastresp
            }

    except ftplib.error_perm as e:
        error_msg = str(e)
        conn['last_message'] = error_msg
        return {
            'success': False,
            'error': f"Directory listing failed: {error_msg}"
        }
    except ftplib.all_errors as e:
        error_msg = str(e)
        conn['last_message'] = error_msg
        return {
            'success': False,
            'error': f"DIR error: {error_msg}"
        }


def binary(connection_id: str) -> Dict[str, Any]:
    """
    Set transfer mode to binary.

    Args:
        connection_id: Connection ID from new()

    Returns:
        Dict with success status or error message
    """
    conn = _get_connection(connection_id)
    if not conn:
        return {
            'success': False,
            'error': f"Invalid connection ID: {connection_id}"
        }

    try:
        with conn['lock']:
            ftp = conn['client']

            # Set binary mode (TYPE I)
            ftp.voidcmd('TYPE I')

            # Update connection state
            conn['transfer_mode'] = MODE_BINARY
            conn['last_used'] = time.time()
            conn['last_message'] = ftp.lastresp

            return {
                'success': True,
                'message': ftp.lastresp
            }

    except ftplib.all_errors as e:
        error_msg = str(e)
        conn['last_message'] = error_msg
        return {
            'success': False,
            'error': f"Binary mode error: {error_msg}"
        }


def ascii(connection_id: str) -> Dict[str, Any]:
    """
    Set transfer mode to ASCII.

    Args:
        connection_id: Connection ID from new()

    Returns:
        Dict with success status or error message
    """
    conn = _get_connection(connection_id)
    if not conn:
        return {
            'success': False,
            'error': f"Invalid connection ID: {connection_id}"
        }

    try:
        with conn['lock']:
            ftp = conn['client']

            # Set ASCII mode (TYPE A)
            ftp.voidcmd('TYPE A')

            # Update connection state
            conn['transfer_mode'] = MODE_ASCII
            conn['last_used'] = time.time()
            conn['last_message'] = ftp.lastresp

            return {
                'success': True,
                'message': ftp.lastresp
            }

    except ftplib.all_errors as e:
        error_msg = str(e)
        conn['last_message'] = error_msg
        return {
            'success': False,
            'error': f"ASCII mode error: {error_msg}"
        }


def get(connection_id: str, remote_file: str, local_file: Optional[str] = None) -> Dict[str, Any]:
    """
    Download a file from FTP server.

    Args:
        connection_id: Connection ID from new()
        remote_file: Remote file path
        local_file: Local file path (default: same as remote_file basename)

    Returns:
        Dict with success status or error message
    """
    conn = _get_connection(connection_id)
    if not conn:
        return {
            'success': False,
            'error': f"Invalid connection ID: {connection_id}"
        }

    # Default local file name to remote file basename
    if local_file is None:
        local_file = os.path.basename(remote_file)

    try:
        with conn['lock']:
            ftp = conn['client']
            transfer_mode = conn['transfer_mode']

            # Download file
            with open(local_file, 'wb' if transfer_mode == MODE_BINARY else 'w') as f:
                if transfer_mode == MODE_BINARY:
                    ftp.retrbinary(f'RETR {remote_file}', f.write)
                else:
                    ftp.retrlines(f'RETR {remote_file}', lambda line: f.write(line + '\n'))

            # Update connection state
            conn['last_used'] = time.time()
            conn['last_message'] = ftp.lastresp

            return {
                'success': True,
                'message': ftp.lastresp,
                'local_file': local_file
            }

    except ftplib.error_perm as e:
        error_msg = str(e)
        conn['last_message'] = error_msg

        # Remove partial file if download failed
        try:
            if os.path.exists(local_file):
                os.remove(local_file)
        except:
            pass

        return {
            'success': False,
            'error': f"Download failed: {error_msg}"
        }
    except ftplib.all_errors as e:
        error_msg = str(e)
        conn['last_message'] = error_msg

        # Remove partial file if download failed
        try:
            if os.path.exists(local_file):
                os.remove(local_file)
        except:
            pass

        return {
            'success': False,
            'error': f"GET error: {error_msg}"
        }
    except IOError as e:
        error_msg = str(e)
        conn['last_message'] = error_msg
        return {
            'success': False,
            'error': f"Local file error: {error_msg}"
        }


def put(connection_id: str, local_file: str, remote_file: Optional[str] = None) -> Dict[str, Any]:
    """
    Upload a file to FTP server.

    Args:
        connection_id: Connection ID from new()
        local_file: Local file path
        remote_file: Remote file path (default: same as local_file basename)

    Returns:
        Dict with success status or error message
    """
    conn = _get_connection(connection_id)
    if not conn:
        return {
            'success': False,
            'error': f"Invalid connection ID: {connection_id}"
        }

    # Check if local file exists
    if not os.path.exists(local_file):
        return {
            'success': False,
            'error': f"Local file not found: {local_file}"
        }

    # Default remote file name to local file basename
    if remote_file is None:
        remote_file = os.path.basename(local_file)

    try:
        with conn['lock']:
            ftp = conn['client']
            transfer_mode = conn['transfer_mode']

            # Upload file
            with open(local_file, 'rb' if transfer_mode == MODE_BINARY else 'r') as f:
                if transfer_mode == MODE_BINARY:
                    ftp.storbinary(f'STOR {remote_file}', f)
                else:
                    ftp.storlines(f'STOR {remote_file}', f)

            # Update connection state
            conn['last_used'] = time.time()
            conn['last_message'] = ftp.lastresp

            return {
                'success': True,
                'message': ftp.lastresp,
                'remote_file': remote_file
            }

    except ftplib.error_perm as e:
        error_msg = str(e)
        conn['last_message'] = error_msg
        return {
            'success': False,
            'error': f"Upload failed: {error_msg}"
        }
    except ftplib.all_errors as e:
        error_msg = str(e)
        conn['last_message'] = error_msg
        return {
            'success': False,
            'error': f"PUT error: {error_msg}"
        }
    except IOError as e:
        error_msg = str(e)
        conn['last_message'] = error_msg
        return {
            'success': False,
            'error': f"Local file error: {error_msg}"
        }


def delete(connection_id: str, remote_file: str) -> Dict[str, Any]:
    """
    Delete a file on FTP server.

    Args:
        connection_id: Connection ID from new()
        remote_file: Remote file path to delete

    Returns:
        Dict with success status or error message
    """
    conn = _get_connection(connection_id)
    if not conn:
        return {
            'success': False,
            'error': f"Invalid connection ID: {connection_id}"
        }

    try:
        with conn['lock']:
            ftp = conn['client']

            # Delete file
            ftp.delete(remote_file)

            # Update connection state
            conn['last_used'] = time.time()
            conn['last_message'] = ftp.lastresp

            return {
                'success': True,
                'message': ftp.lastresp
            }

    except ftplib.error_perm as e:
        error_msg = str(e)
        conn['last_message'] = error_msg
        return {
            'success': False,
            'error': f"Delete failed: {error_msg}"
        }
    except ftplib.all_errors as e:
        error_msg = str(e)
        conn['last_message'] = error_msg
        return {
            'success': False,
            'error': f"DELETE error: {error_msg}"
        }


def rename(connection_id: str, old_name: str, new_name: str) -> Dict[str, Any]:
    """
    Rename a file on FTP server.

    Args:
        connection_id: Connection ID from new()
        old_name: Current file name
        new_name: New file name

    Returns:
        Dict with success status or error message
    """
    conn = _get_connection(connection_id)
    if not conn:
        return {
            'success': False,
            'error': f"Invalid connection ID: {connection_id}"
        }

    try:
        with conn['lock']:
            ftp = conn['client']

            # Rename file
            ftp.rename(old_name, new_name)

            # Update connection state
            conn['last_used'] = time.time()
            conn['last_message'] = ftp.lastresp

            return {
                'success': True,
                'message': ftp.lastresp
            }

    except ftplib.error_perm as e:
        error_msg = str(e)
        conn['last_message'] = error_msg
        return {
            'success': False,
            'error': f"Rename failed: {error_msg}"
        }
    except ftplib.all_errors as e:
        error_msg = str(e)
        conn['last_message'] = error_msg
        return {
            'success': False,
            'error': f"RENAME error: {error_msg}"
        }


def message(connection_id: str) -> Dict[str, Any]:
    """
    Get last FTP server response message.

    Args:
        connection_id: Connection ID from new()

    Returns:
        Dict with success status and message
    """
    conn = _get_connection(connection_id)
    if not conn:
        return {
            'success': False,
            'error': f"Invalid connection ID: {connection_id}"
        }

    try:
        with conn['lock']:
            last_msg = conn.get('last_message', '')

            return {
                'success': True,
                'message': last_msg
            }

    except Exception as e:
        return {
            'success': False,
            'error': f"Error retrieving message: {str(e)}"
        }


def quit(connection_id: str) -> Dict[str, Any]:
    """
    Close FTP connection and remove from pool.

    Args:
        connection_id: Connection ID from new()

    Returns:
        Dict with success status
    """
    with _connections_lock:
        conn = _ftp_connections.get(connection_id)

        if not conn:
            # Connection already closed or invalid - return success (idempotent)
            return {'success': True}

        try:
            with conn['lock']:
                ftp = conn['client']

                # Close FTP connection
                try:
                    ftp.quit()
                except:
                    # Ignore errors during quit
                    try:
                        ftp.close()
                    except:
                        pass

                # Update state
                conn['state'] = STATE_CLOSED

            # Remove from pool
            del _ftp_connections[connection_id]

            return {'success': True}

        except Exception as e:
            # Remove from pool even if quit failed
            if connection_id in _ftp_connections:
                del _ftp_connections[connection_id]

            # quit() should always succeed even on errors (idempotent)
            return {'success': True}


def get_connection_info(connection_id: str) -> Dict[str, Any]:
    """
    Get information about a specific connection.

    Args:
        connection_id: Connection ID from new()

    Returns:
        Dict with connection information
    """
    conn = _get_connection(connection_id)
    if not conn:
        return {
            'success': False,
            'error': f"Invalid connection ID: {connection_id}"
        }

    with conn['lock']:
        return {
            'success': True,
            'connection_id': connection_id,
            'host': conn['host'],
            'state': conn['state'],
            'transfer_mode': conn['transfer_mode'],
            'created_at': conn['created_at'],
            'last_used': conn['last_used'],
            'age': time.time() - conn['created_at'],
            'idle_time': time.time() - conn['last_used']
        }


def get_pool_stats() -> Dict[str, Any]:
    """
    Get statistics about the FTP connection pool.

    Returns:
        Dict with pool statistics
    """
    with _connections_lock:
        total = len(_ftp_connections)
        connected = sum(1 for c in _ftp_connections.values() if c['state'] == STATE_CONNECTED)
        logged_in = sum(1 for c in _ftp_connections.values() if c['state'] == STATE_LOGGED_IN)

        return {
            'success': True,
            'total_connections': total,
            'connected': connected,
            'logged_in': logged_in,
            'connection_ids': list(_ftp_connections.keys())
        }


def cleanup_stale_connections() -> Dict[str, Any]:
    """
    Manually trigger cleanup of stale connections.

    Returns:
        Dict with cleanup statistics
    """
    removed = _cleanup_stale_connections()
    return {
        'success': True,
        'removed': removed
    }


def cleanup_stale_resources():
    """
    Cleanup function called by daemon's periodic cleanup thread.

    This is the standard interface that the CPAN daemon expects from helper modules.
    It delegates to _cleanup_stale_connections() for actual cleanup work.
    """
    _cleanup_stale_connections()


# Internal helper functions

def _get_connection(connection_id: str) -> Optional[Dict[str, Any]]:
    """
    Get connection from pool.

    Args:
        connection_id: Connection ID

    Returns:
        Connection dict or None if not found
    """
    with _connections_lock:
        return _ftp_connections.get(connection_id)


def _cleanup_stale_connections() -> int:
    """
    Remove connections that have been idle for too long.

    Returns:
        Number of connections removed
    """
    removed = 0
    current_time = time.time()

    with _connections_lock:
        # Find stale connections
        stale_ids = []
        for conn_id, conn in _ftp_connections.items():
            idle_time = current_time - conn['last_used']
            if idle_time > CONNECTION_CLEANUP_TIMEOUT:
                stale_ids.append(conn_id)

        # Remove stale connections
        for conn_id in stale_ids:
            try:
                conn = _ftp_connections[conn_id]
                with conn['lock']:
                    ftp = conn['client']
                    try:
                        ftp.quit()
                    except:
                        try:
                            ftp.close()
                        except:
                            pass

                del _ftp_connections[conn_id]
                removed += 1
            except:
                # Best effort cleanup
                if conn_id in _ftp_connections:
                    del _ftp_connections[conn_id]
                    removed += 1

    return removed
