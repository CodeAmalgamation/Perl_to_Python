"""
Net::OpenSSH Replacement - Python SSH/SCP Backend

Provides SSH connectivity and SCP file transfer using paramiko library.
Based on Net::OpenSSH usage analysis from mi_ftp_unix_fw.pl

Required API:
- new(host, user, port, password, key_path, timeout)
- scp_put(connection_id, options, local_file, remote_file)
- get_error(connection_id)
- disconnect(connection_id)
"""

import os
import stat
import uuid
import paramiko
from typing import Dict, Any, Optional

# Global connection storage for daemon mode
SSH_CONNECTIONS = {}


def new(host: str, user: str, port: int = 22, password: Optional[str] = None,
        key_path: Optional[str] = None, timeout: int = 30, **kwargs) -> Dict[str, Any]:
    """
    Create SSH connection (mimics Net::OpenSSH->new())

    Parameters match Net::OpenSSH constructor:
    - host: Remote hostname/IP (required)
    - user: SSH username (required)
    - port: SSH port number (default: 22)
    - password: Password authentication (optional)
    - key_path: Private key file path (optional)
    - timeout: Connection timeout in seconds (default: 30)

    Returns:
    {
        'success': True/False,
        'result': {'connection_id': 'uuid', 'connected': True/False},
        'error': error_message (if any)
    }

    Note: Like Net::OpenSSH, constructor doesn't raise exceptions.
          Connection errors are stored and retrieved via get_error().
    """
    connection_id = str(uuid.uuid4())

    try:
        # Create SSH client
        ssh = paramiko.SSHClient()

        # Auto-add host keys (Net::OpenSSH default behavior)
        ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())

        # Prepare connection parameters
        connect_kwargs = {
            'hostname': host,
            'port': port,
            'username': user,
            'timeout': timeout,
            'look_for_keys': False,  # Only use provided authentication
            'allow_agent': False     # No SSH agent (matches Net::OpenSSH usage)
        }

        # Authentication: password OR key_path
        if key_path and key_path != '0' and key_path != '':
            # Key-based authentication
            if os.path.exists(key_path):
                connect_kwargs['key_filename'] = key_path
            else:
                # Store error but don't raise exception (Net::OpenSSH behavior)
                SSH_CONNECTIONS[connection_id] = {
                    'ssh': None,
                    'sftp': None,
                    'error': f"Key file not found: {key_path}",
                    'host': host,
                    'user': user,
                    'connected': False
                }
                return {
                    'success': True,
                    'result': {
                        'connection_id': connection_id,
                        'connected': False
                    }
                }
        elif password:
            # Password authentication
            connect_kwargs['password'] = password
        else:
            # No authentication provided
            SSH_CONNECTIONS[connection_id] = {
                'ssh': None,
                'sftp': None,
                'error': "No authentication method provided (password or key_path required)",
                'host': host,
                'user': user,
                'connected': False
            }
            return {
                'success': True,
                'result': {
                    'connection_id': connection_id,
                    'connected': False
                }
            }

        # Attempt connection (non-blocking error handling)
        try:
            ssh.connect(**connect_kwargs)

            # Connection successful
            SSH_CONNECTIONS[connection_id] = {
                'ssh': ssh,
                'sftp': None,  # Lazy initialization
                'error': None,
                'host': host,
                'user': user,
                'port': port,
                'connected': True
            }

            return {
                'success': True,
                'result': {
                    'connection_id': connection_id,
                    'connected': True
                }
            }

        except paramiko.AuthenticationException as e:
            # Authentication failed
            SSH_CONNECTIONS[connection_id] = {
                'ssh': None,
                'sftp': None,
                'error': f"Authentication failed: {str(e)}",
                'host': host,
                'user': user,
                'connected': False
            }
            return {
                'success': True,
                'result': {
                    'connection_id': connection_id,
                    'connected': False
                }
            }

        except paramiko.SSHException as e:
            # SSH protocol error
            SSH_CONNECTIONS[connection_id] = {
                'ssh': None,
                'sftp': None,
                'error': f"SSH error: {str(e)}",
                'host': host,
                'user': user,
                'connected': False
            }
            return {
                'success': True,
                'result': {
                    'connection_id': connection_id,
                    'connected': False
                }
            }

        except Exception as e:
            # Connection timeout or network error
            SSH_CONNECTIONS[connection_id] = {
                'ssh': None,
                'sftp': None,
                'error': f"Connection failed: {str(e)}",
                'host': host,
                'user': user,
                'connected': False
            }
            return {
                'success': True,
                'result': {
                    'connection_id': connection_id,
                    'connected': False
                }
            }

    except Exception as e:
        # Unexpected error
        return {
            'success': False,
            'error': f"Failed to create SSH connection: {str(e)}"
        }


def scp_put(connection_id: str, local_file: str, remote_file: str,
            options: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
    """
    Upload file via SCP/SFTP (mimics Net::OpenSSH->scp_put())

    Parameters:
    - connection_id: UUID from new()
    - local_file: Local file path
    - remote_file: Remote file path
    - options: Optional dict with 'perm' (octal permissions) and 'umask'

    Returns:
    {
        'success': True/False,
        'result': True/False (transfer success),
        'error': error_message (if any)
    }
    """
    try:
        if connection_id not in SSH_CONNECTIONS:
            return {
                'success': False,
                'error': f"Invalid connection ID: {connection_id}"
            }

        conn = SSH_CONNECTIONS[connection_id]

        # Check if connected
        if not conn.get('connected', False) or conn.get('ssh') is None:
            conn['error'] = "Not connected to remote host"
            return {
                'success': True,
                'result': False
            }

        # Lazy SFTP initialization
        if conn['sftp'] is None:
            try:
                conn['sftp'] = conn['ssh'].open_sftp()
            except Exception as e:
                conn['error'] = f"Failed to open SFTP channel: {str(e)}"
                return {
                    'success': True,
                    'result': False
                }

        sftp = conn['sftp']

        # Verify local file exists
        if not os.path.exists(local_file):
            conn['error'] = f"Local file not found: {local_file}"
            return {
                'success': True,
                'result': False
            }

        # Upload file
        try:
            sftp.put(local_file, remote_file)

            # Apply permissions if specified
            if options and 'perm' in options:
                try:
                    # options['perm'] is already in octal format from Perl
                    perm = options['perm']
                    if isinstance(perm, str):
                        perm = int(perm, 8)
                    sftp.chmod(remote_file, perm)
                except Exception as e:
                    # Permission setting failed, but upload succeeded
                    conn['error'] = f"File uploaded but chmod failed: {str(e)}"

            # Clear error on success
            conn['error'] = None

            return {
                'success': True,
                'result': True
            }

        except IOError as e:
            conn['error'] = f"Upload failed: {str(e)}"
            return {
                'success': True,
                'result': False
            }
        except Exception as e:
            conn['error'] = f"Transfer error: {str(e)}"
            return {
                'success': True,
                'result': False
            }

    except Exception as e:
        return {
            'success': False,
            'error': f"scp_put failed: {str(e)}"
        }


def get_error(connection_id: str) -> Dict[str, Any]:
    """
    Get last error message (mimics Net::OpenSSH->error())

    Returns:
    {
        'success': True,
        'result': error_string or None
    }
    """
    try:
        if connection_id not in SSH_CONNECTIONS:
            return {
                'success': False,
                'error': f"Invalid connection ID: {connection_id}"
            }

        conn = SSH_CONNECTIONS[connection_id]
        error_msg = conn.get('error', None)

        return {
            'success': True,
            'result': error_msg
        }

    except Exception as e:
        return {
            'success': False,
            'error': f"get_error failed: {str(e)}"
        }


def disconnect(connection_id: str) -> Dict[str, Any]:
    """
    Close SSH connection (mimics Net::OpenSSH->disconnect())

    Returns:
    {
        'success': True,
        'result': True
    }
    """
    try:
        if connection_id not in SSH_CONNECTIONS:
            # Already disconnected or invalid ID
            return {
                'success': True,
                'result': True
            }

        conn = SSH_CONNECTIONS[connection_id]

        # Close SFTP channel
        if conn.get('sftp'):
            try:
                conn['sftp'].close()
            except:
                pass

        # Close SSH connection
        if conn.get('ssh'):
            try:
                conn['ssh'].close()
            except:
                pass

        # Remove from connections
        del SSH_CONNECTIONS[connection_id]

        return {
            'success': True,
            'result': True
        }

    except Exception as e:
        return {
            'success': False,
            'error': f"disconnect failed: {str(e)}"
        }


def cleanup_connection(connection_id: str) -> Dict[str, Any]:
    """
    Cleanup resources (alias for disconnect)
    """
    return disconnect(connection_id)
