#!/usr/bin/env python3
"""
sftp.py - Complete SFTP backend for Net::SFTP::Foreign replacement

Provides SFTP functionality using paramiko with patterns matching actual enterprise usage.
Based on comprehensive analysis of Net::SFTP::Foreign usage patterns.
"""

import os
import re
import stat
import time
import uuid
from typing import Dict, List, Any, Optional

# Global session storage
SFTP_SESSIONS = {}

def new(host: str, user: str, port: int = 22, timeout: int = 60,
        password: str = None, more: List[str] = None, **kwargs) -> Dict[str, Any]:
    """
    Create new SFTP connection (matches Net::SFTP::Foreign->new())

    Args:
        host: Remote hostname
        user: Username for authentication
        port: SSH port (default 22)
        timeout: Connection timeout in seconds
        password: Password for authentication (optional)
        more: SSH options array like ["-o", "IdentityFile=path"]
        **kwargs: Additional SSH options

    Returns:
        Dictionary with connection result and session ID
    """
    try:
        # Parse SSH options from 'more' parameter
        ssh_options = {}
        if more:
            i = 0
            while i < len(more):
                if more[i] == "-o" and i + 1 < len(more):
                    option = more[i + 1]
                    if "=" in option:
                        key, value = option.split("=", 1)
                        if key == "IdentityFile":
                            ssh_options['identity_file'] = value
                    i += 2
                else:
                    i += 1

        # Try paramiko first (most compatible)
        try:
            import paramiko
            return _connect_paramiko(host, user, port, timeout, password, ssh_options)
        except ImportError:
            # Fall back to subprocess + sftp command
            return _connect_subprocess(host, user, port, timeout, password, ssh_options)

    except Exception as e:
        return {
            'success': False,
            'error': f'SFTP connection failed: {str(e)}',
        }

def _connect_paramiko(host: str, user: str, port: int, timeout: int,
                     password: str = None, ssh_options: Dict[str, str] = None) -> Dict[str, Any]:
    """Connect using paramiko library"""
    import paramiko

    # Create SSH client
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())

    # Prepare connection parameters
    connect_params = {
        'hostname': host,
        'username': user,
        'port': port,
        'timeout': timeout,
    }

    # Handle authentication
    if password and not password.lower().startswith('identityfile'):
        connect_params['password'] = password

    if ssh_options and 'identity_file' in ssh_options:
        identity_file = ssh_options['identity_file']
        if os.path.exists(identity_file):
            connect_params['key_filename'] = identity_file

    # Establish SSH connection
    ssh.connect(**connect_params)

    # Open SFTP session
    sftp = ssh.open_sftp()

    # Get initial directory
    try:
        initial_dir = sftp.getcwd() or '/'
    except:
        initial_dir = '/'

    # Generate session ID and store connection
    session_id = str(uuid.uuid4())
    SFTP_SESSIONS[session_id] = {
        'ssh': ssh,
        'sftp': sftp,
        'host': host,
        'user': user,
        'current_dir': initial_dir,
        'connected_at': time.time(),
        'last_error': None,
    }

    return {
        'success': True,
        'result': {
            'session_id': session_id,
            'initial_dir': initial_dir,
            'connection_type': 'paramiko',
        }
    }

def _connect_subprocess(host: str, user: str, port: int, timeout: int,
                       password: str = None, ssh_options: Dict[str, str] = None) -> Dict[str, Any]:
    """Connect using subprocess + sftp command (fallback)"""
    session_id = str(uuid.uuid4())
    SFTP_SESSIONS[session_id] = {
        'host': host,
        'user': user,
        'port': port,
        'password': password,
        'ssh_options': ssh_options or {},
        'current_dir': '/',
        'connection_type': 'subprocess',
        'connected_at': time.time(),
        'last_error': None,
    }

    return {
        'success': True,
        'result': {
            'session_id': session_id,
            'initial_dir': '/',
            'connection_type': 'subprocess',
        }
    }

def put(session_id: str, local_file: str, remote_file: str) -> Dict[str, Any]:
    """
    Upload file to remote server (matches $sftp->put())

    Args:
        session_id: Active SFTP session ID
        local_file: Local file path
        remote_file: Remote file path (can be relative to current dir)

    Returns:
        Dictionary with operation result
    """
    try:
        if session_id not in SFTP_SESSIONS:
            return {
                'success': False,
                'error': 'SFTP session not found or expired'
            }

        session = SFTP_SESSIONS[session_id]

        # Check if local file exists
        if not os.path.exists(local_file):
            session['last_error'] = f'Local file not found: {local_file}'
            return {
                'success': False,
                'error': session['last_error']
            }

        if session['connection_type'] == 'paramiko':
            return _put_paramiko(session, local_file, remote_file)
        else:
            return _put_subprocess(session, local_file, remote_file)

    except Exception as e:
        error_msg = f'SFTP put operation failed: {str(e)}'
        if session_id in SFTP_SESSIONS:
            SFTP_SESSIONS[session_id]['last_error'] = error_msg
        return {
            'success': False,
            'error': error_msg
        }

def _put_paramiko(session: Dict[str, Any], local_file: str, remote_file: str) -> Dict[str, Any]:
    """Upload file using paramiko"""
    sftp = session['sftp']

    # Handle relative paths - make relative to current working directory
    if not remote_file.startswith('/'):
        remote_file = f"{session['current_dir'].rstrip('/')}/{remote_file}"

    # Create remote directories if needed
    remote_dir = os.path.dirname(remote_file)
    if remote_dir and remote_dir != '/':
        _ensure_remote_directory(sftp, remote_dir)

    # Upload file
    sftp.put(local_file, remote_file)

    # Clear any previous errors
    session['last_error'] = None

    return {
        'success': True,
        'result': {
            'local_file': local_file,
            'remote_file': remote_file,
            'bytes_transferred': os.path.getsize(local_file)
        }
    }

def _put_subprocess(session: Dict[str, Any], local_file: str, remote_file: str) -> Dict[str, Any]:
    """Upload file using subprocess + scp"""
    import subprocess

    host = session['host']
    user = session['user']
    port = session['port']

    # Handle relative paths
    if not remote_file.startswith('/'):
        remote_file = f"{session['current_dir'].rstrip('/')}/{remote_file}"

    cmd = ['scp', '-P', str(port)]

    # Add identity file if specified
    if 'identity_file' in session.get('ssh_options', {}):
        cmd.extend(['-i', session['ssh_options']['identity_file']])

    cmd.extend([local_file, f'{user}@{host}:{remote_file}'])

    # Execute scp command
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=300)

    if result.returncode == 0:
        session['last_error'] = None
        return {
            'success': True,
            'result': {
                'local_file': local_file,
                'remote_file': remote_file,
                'command': ' '.join(cmd[:4]) + ' [file_transfer]'
            }
        }
    else:
        error_msg = f'scp failed: {result.stderr or result.stdout}'
        session['last_error'] = error_msg
        return {
            'success': False,
            'error': error_msg
        }

def ls(session_id: str, remote_dir: str = None, wanted: str = None) -> Dict[str, Any]:
    """
    List directory contents with optional pattern matching (matches $sftp->ls())

    Args:
        session_id: Active SFTP session ID
        remote_dir: Directory to list (default current)
        wanted: Regex pattern to match files (qr/pattern/ equivalent)

    Returns:
        Dictionary with file listing array
    """
    try:
        if session_id not in SFTP_SESSIONS:
            return {
                'success': False,
                'error': 'SFTP session not found or expired'
            }

        session = SFTP_SESSIONS[session_id]

        if session['connection_type'] == 'paramiko':
            return _ls_paramiko(session, remote_dir, wanted)
        else:
            return _ls_subprocess(session, remote_dir, wanted)

    except Exception as e:
        error_msg = f'SFTP ls operation failed: {str(e)}'
        if session_id in SFTP_SESSIONS:
            SFTP_SESSIONS[session_id]['last_error'] = error_msg
        return {
            'success': False,
            'error': error_msg
        }

def _ls_paramiko(session: Dict[str, Any], remote_dir: str, wanted: str) -> Dict[str, Any]:
    """List directory using paramiko"""
    sftp = session['sftp']

    list_dir = remote_dir or session['current_dir']

    # Get directory listing with attributes
    entries = []
    try:
        for entry in sftp.listdir_attr(list_dir):
            # Create entry compatible with Net::SFTP::Foreign format
            entry_info = {
                'filename': entry.filename,
                'longname': _format_longname(entry),
                'size': entry.st_size or 0,
                'mtime': entry.st_mtime or 0,
                'permissions': entry.st_mode or 0,
                'is_dir': stat.S_ISDIR(entry.st_mode) if entry.st_mode else False,
            }

            # Apply pattern filter if specified (wanted => qr/pattern/)
            if wanted:
                try:
                    if re.search(wanted, entry.filename):
                        entries.append(entry_info)
                except re.error:
                    # If regex is invalid, treat as literal string
                    if wanted in entry.filename:
                        entries.append(entry_info)
            else:
                entries.append(entry_info)

    except FileNotFoundError:
        error_msg = f'Directory not found: {list_dir}'
        session['last_error'] = error_msg
        return {
            'success': False,
            'error': error_msg
        }

    # Clear any previous errors
    session['last_error'] = None

    return {
        'success': True,
        'result': entries  # Return as array like Net::SFTP::Foreign
    }

def _ls_subprocess(session: Dict[str, Any], remote_dir: str, wanted: str) -> Dict[str, Any]:
    """List directory using subprocess + ssh/ls"""
    import subprocess

    host = session['host']
    user = session['user']
    port = session['port']

    list_dir = remote_dir or session['current_dir']

    cmd = ['ssh', '-p', str(port)]

    # Add identity file if specified
    if 'identity_file' in session.get('ssh_options', {}):
        cmd.extend(['-i', session['ssh_options']['identity_file']])

    cmd.extend([f'{user}@{host}', f'ls -la "{list_dir}"'])

    result = subprocess.run(cmd, capture_output=True, text=True, timeout=60)

    if result.returncode != 0:
        error_msg = f'ls failed: {result.stderr or result.stdout}'
        session['last_error'] = error_msg
        return {
            'success': False,
            'error': error_msg
        }

    # Parse ls output
    entries = []
    for line in result.stdout.strip().split('\n'):
        if line and not line.startswith('total'):
            entry_info = _parse_ls_line(line)
            if entry_info:
                # Apply pattern filter
                if wanted:
                    try:
                        if re.search(wanted, entry_info['filename']):
                            entries.append(entry_info)
                    except re.error:
                        if wanted in entry_info['filename']:
                            entries.append(entry_info)
                else:
                    entries.append(entry_info)

    session['last_error'] = None
    return {
        'success': True,
        'result': entries
    }

def rename(session_id: str, old_name: str, new_name: str, overwrite: bool = False) -> Dict[str, Any]:
    """
    Rename/move file on remote server (matches $sftp->rename())

    Args:
        session_id: Active SFTP session ID
        old_name: Current file name (relative to current dir)
        new_name: New file name (relative to current dir)
        overwrite: Whether to overwrite existing files

    Returns:
        Dictionary with operation result
    """
    try:
        if session_id not in SFTP_SESSIONS:
            return {
                'success': False,
                'error': 'SFTP session not found or expired'
            }

        session = SFTP_SESSIONS[session_id]

        if session['connection_type'] == 'paramiko':
            return _rename_paramiko(session, old_name, new_name, overwrite)
        else:
            return _rename_subprocess(session, old_name, new_name, overwrite)

    except Exception as e:
        error_msg = f'SFTP rename operation failed: {str(e)}'
        if session_id in SFTP_SESSIONS:
            SFTP_SESSIONS[session_id]['last_error'] = error_msg
        return {
            'success': False,
            'error': error_msg
        }

def _rename_paramiko(session: Dict[str, Any], old_name: str, new_name: str, overwrite: bool) -> Dict[str, Any]:
    """Rename file using paramiko"""
    sftp = session['sftp']

    # Handle relative paths - make relative to current working directory
    if not old_name.startswith('/'):
        old_name = f"{session['current_dir'].rstrip('/')}/{old_name}"
    if not new_name.startswith('/'):
        new_name = f"{session['current_dir'].rstrip('/')}/{new_name}"

    # Check if target exists and handle overwrite
    try:
        sftp.stat(new_name)
        if not overwrite:
            error_msg = f'Target file exists and overwrite not enabled: {new_name}'
            session['last_error'] = error_msg
            return {
                'success': False,
                'error': error_msg
            }
        # Remove existing file if overwrite is enabled
        sftp.remove(new_name)
    except FileNotFoundError:
        # Target doesn't exist, which is fine
        pass

    # Perform rename
    sftp.rename(old_name, new_name)

    # Clear any previous errors
    session['last_error'] = None

    return {
        'success': True,
        'result': {
            'old_name': old_name,
            'new_name': new_name,
            'overwrite': overwrite
        }
    }

def _rename_subprocess(session: Dict[str, Any], old_name: str, new_name: str, overwrite: bool) -> Dict[str, Any]:
    """Rename file using subprocess + ssh/mv"""
    import subprocess

    host = session['host']
    user = session['user']
    port = session['port']

    # Handle relative paths
    if not old_name.startswith('/'):
        old_name = f"{session['current_dir'].rstrip('/')}/{old_name}"
    if not new_name.startswith('/'):
        new_name = f"{session['current_dir'].rstrip('/')}/{new_name}"

    cmd = ['ssh', '-p', str(port)]

    # Add identity file if specified
    if 'identity_file' in session.get('ssh_options', {}):
        cmd.extend(['-i', session['ssh_options']['identity_file']])

    # Build mv command
    if overwrite:
        mv_cmd = f'mv "{old_name}" "{new_name}"'
    else:
        # Check if target exists first
        mv_cmd = f'if [ ! -e "{new_name}" ]; then mv "{old_name}" "{new_name}"; else echo "Target exists"; exit 1; fi'

    cmd.extend([f'{user}@{host}', mv_cmd])

    result = subprocess.run(cmd, capture_output=True, text=True, timeout=60)

    if result.returncode == 0:
        session['last_error'] = None
        return {
            'success': True,
            'result': {
                'old_name': old_name,
                'new_name': new_name,
                'command': ' '.join(cmd[:4]) + ' [ssh_command]'
            }
        }
    else:
        error_msg = f'mv failed: {result.stderr or result.stdout}'
        session['last_error'] = error_msg
        return {
            'success': False,
            'error': error_msg
        }

def setcwd(session_id: str, remote_dir: str) -> Dict[str, Any]:
    """
    Change current working directory (matches $sftp->setcwd())

    Args:
        session_id: Active SFTP session ID
        remote_dir: Directory to change to

    Returns:
        Dictionary with operation result
    """
    try:
        if session_id not in SFTP_SESSIONS:
            return {
                'success': False,
                'error': 'SFTP session not found or expired'
            }

        session = SFTP_SESSIONS[session_id]

        if session['connection_type'] == 'paramiko':
            sftp = session['sftp']
            try:
                # Verify directory exists
                sftp.stat(remote_dir)
                # Change directory
                sftp.chdir(remote_dir)
                session['current_dir'] = sftp.getcwd() or remote_dir
                session['last_error'] = None

                return {
                    'success': True,
                    'result': {
                        'current_dir': session['current_dir']
                    }
                }
            except Exception as e:
                error_msg = f'Failed to change directory to {remote_dir}: {str(e)}'
                session['last_error'] = error_msg
                return {
                    'success': False,
                    'error': error_msg
                }
        else:
            # For subprocess mode, just update the stored current directory
            session['current_dir'] = remote_dir
            session['last_error'] = None
            return {
                'success': True,
                'result': {
                    'current_dir': session['current_dir']
                }
            }

    except Exception as e:
        error_msg = f'SFTP setcwd operation failed: {str(e)}'
        if session_id in SFTP_SESSIONS:
            SFTP_SESSIONS[session_id]['last_error'] = error_msg
        return {
            'success': False,
            'error': error_msg
        }

def cwd(session_id: str) -> Dict[str, Any]:
    """
    Get current working directory (matches $sftp->cwd)

    Args:
        session_id: Active SFTP session ID

    Returns:
        Dictionary with current directory
    """
    try:
        if session_id not in SFTP_SESSIONS:
            return {
                'success': False,
                'error': 'SFTP session not found or expired'
            }

        session = SFTP_SESSIONS[session_id]

        if session['connection_type'] == 'paramiko':
            sftp = session['sftp']
            try:
                current_dir = sftp.getcwd() or session['current_dir']
                session['current_dir'] = current_dir
                return {
                    'success': True,
                    'result': current_dir
                }
            except Exception as e:
                return {
                    'success': True,
                    'result': session['current_dir']  # Fallback to stored value
                }
        else:
            return {
                'success': True,
                'result': session['current_dir']
            }

    except Exception as e:
        return {
            'success': False,
            'error': f'SFTP cwd operation failed: {str(e)}'
        }

def error(session_id: str) -> Dict[str, Any]:
    """
    Get last error message (matches $sftp->error)

    Args:
        session_id: Active SFTP session ID

    Returns:
        Dictionary with error message
    """
    try:
        if session_id not in SFTP_SESSIONS:
            return {
                'success': True,
                'result': 'SFTP session not found or expired'
            }

        session = SFTP_SESSIONS[session_id]
        return {
            'success': True,
            'result': session.get('last_error', '')
        }

    except Exception as e:
        return {
            'success': True,
            'result': f'Error retrieving error message: {str(e)}'
        }

def disconnect(session_id: str) -> Dict[str, Any]:
    """
    Close SFTP connection (automatic cleanup on object destruction)

    Args:
        session_id: Active SFTP session ID

    Returns:
        Dictionary with disconnection result
    """
    try:
        if session_id not in SFTP_SESSIONS:
            return {
                'success': False,
                'error': 'SFTP session not found'
            }

        session = SFTP_SESSIONS[session_id]

        if session['connection_type'] == 'paramiko':
            # Close SFTP and SSH connections
            if 'sftp' in session:
                session['sftp'].close()
            if 'ssh' in session:
                session['ssh'].close()

        # Remove session
        del SFTP_SESSIONS[session_id]

        return {
            'success': True,
            'result': {
                'session_id': session_id,
                'disconnected_at': time.time()
            }
        }

    except Exception as e:
        return {
            'success': False,
            'error': f'SFTP disconnect failed: {str(e)}'
        }

# Helper functions

def _ensure_remote_directory(sftp, remote_dir: str) -> None:
    """Ensure remote directory exists, creating if necessary"""
    try:
        sftp.stat(remote_dir)
    except FileNotFoundError:
        # Directory doesn't exist, create it
        parent_dir = os.path.dirname(remote_dir)
        if parent_dir and parent_dir != '/':
            _ensure_remote_directory(sftp, parent_dir)
        sftp.mkdir(remote_dir)

def _format_longname(entry) -> str:
    """Format file entry in ls -l style (for longname field)"""
    import stat

    # Get file mode
    mode = entry.st_mode or 0

    # File type
    if stat.S_ISDIR(mode):
        type_char = 'd'
    elif stat.S_ISLNK(mode):
        type_char = 'l'
    else:
        type_char = '-'

    # Permissions
    perms = ''
    for i in range(9):
        bit = (mode >> (8 - i)) & 1
        if i % 3 == 0:
            perms += 'r' if bit else '-'
        elif i % 3 == 1:
            perms += 'w' if bit else '-'
        else:
            perms += 'x' if bit else '-'

    # Format like ls -l
    size = entry.st_size or 0
    mtime = time.strftime('%b %d %H:%M', time.localtime(entry.st_mtime or 0))

    return f'{type_char}{perms} 1 user group {size:8d} {mtime} {entry.filename}'

def _parse_ls_line(line: str) -> Optional[Dict[str, Any]]:
    """Parse a line from ls -la output"""
    parts = line.split(None, 8)
    if len(parts) < 9:
        return None

    permissions = parts[0]
    size = int(parts[4]) if parts[4].isdigit() else 0
    filename = parts[8]

    # Skip . and .. entries
    if filename in ['.', '..']:
        return None

    return {
        'filename': filename,
        'longname': line,
        'size': size,
        'mtime': 0,  # Would need more parsing to get accurate mtime
        'permissions': permissions,
        'is_dir': permissions.startswith('d'),
    }

def get(session_id: str, remote_file: str, local_file: str) -> Dict[str, Any]:
    """
    Download file from remote server (matches $sftp->get())

    Args:
        session_id: Active SFTP session ID
        remote_file: Remote file path
        local_file: Local file path

    Returns:
        Dictionary with operation result
    """
    try:
        if session_id not in SFTP_SESSIONS:
            return {
                'success': False,
                'error': 'SFTP session not found or expired'
            }

        session = SFTP_SESSIONS[session_id]

        if session['connection_type'] == 'paramiko':
            return _get_paramiko(session, remote_file, local_file)
        else:
            return _get_subprocess(session, remote_file, local_file)

    except Exception as e:
        error_msg = f'SFTP get operation failed: {str(e)}'
        if session_id in SFTP_SESSIONS:
            SFTP_SESSIONS[session_id]['last_error'] = error_msg
        return {
            'success': False,
            'error': error_msg
        }

def _get_paramiko(session: Dict[str, Any], remote_file: str, local_file: str) -> Dict[str, Any]:
    """Download file using paramiko"""
    sftp = session['sftp']

    # Handle relative paths
    if not remote_file.startswith('/'):
        remote_file = f"{session['current_dir'].rstrip('/')}/{remote_file}"

    try:
        sftp.get(remote_file, local_file)
        return {
            'success': True,
            'result': {
                'remote_file': remote_file,
                'local_file': local_file,
                'transferred_at': time.time()
            }
        }
    except Exception as e:
        error_msg = f'Failed to download {remote_file}: {str(e)}'
        session['last_error'] = error_msg
        return {
            'success': False,
            'error': error_msg
        }

def _get_subprocess(session: Dict[str, Any], remote_file: str, local_file: str) -> Dict[str, Any]:
    """Download file using subprocess (scp)"""
    try:
        # Build scp command
        cmd = ['scp']

        # Add SSH options
        ssh_options = session.get('ssh_options', {})
        if 'identity_file' in ssh_options:
            cmd.extend(['-i', ssh_options['identity_file']])

        # Remote source
        remote_source = f"{session['user']}@{session['host']}:{remote_file}"
        cmd.extend([remote_source, local_file])

        result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)

        if result.returncode == 0:
            return {
                'success': True,
                'result': {
                    'remote_file': remote_file,
                    'local_file': local_file,
                    'transferred_at': time.time()
                }
            }
        else:
            error_msg = f'scp failed: {result.stderr.strip()}'
            session['last_error'] = error_msg
            return {
                'success': False,
                'error': error_msg
            }

    except Exception as e:
        error_msg = f'Failed to download {remote_file}: {str(e)}'
        session['last_error'] = error_msg
        return {
            'success': False,
            'error': error_msg
        }

def mkdir(session_id: str, remote_dir: str) -> Dict[str, Any]:
    """
    Create directory on remote server (matches $sftp->mkdir())

    Args:
        session_id: Active SFTP session ID
        remote_dir: Remote directory path

    Returns:
        Dictionary with operation result
    """
    try:
        if session_id not in SFTP_SESSIONS:
            return {
                'success': False,
                'error': 'SFTP session not found or expired'
            }

        session = SFTP_SESSIONS[session_id]

        if session['connection_type'] == 'paramiko':
            return _mkdir_paramiko(session, remote_dir)
        else:
            return _mkdir_subprocess(session, remote_dir)

    except Exception as e:
        error_msg = f'SFTP mkdir operation failed: {str(e)}'
        if session_id in SFTP_SESSIONS:
            SFTP_SESSIONS[session_id]['last_error'] = error_msg
        return {
            'success': False,
            'error': error_msg
        }

def _mkdir_paramiko(session: Dict[str, Any], remote_dir: str) -> Dict[str, Any]:
    """Create directory using paramiko"""
    sftp = session['sftp']

    # Handle relative paths
    if not remote_dir.startswith('/'):
        remote_dir = f"{session['current_dir'].rstrip('/')}/{remote_dir}"

    try:
        sftp.mkdir(remote_dir)
        return {
            'success': True,
            'result': {
                'remote_dir': remote_dir,
                'created_at': time.time()
            }
        }
    except Exception as e:
        error_msg = f'Failed to create directory {remote_dir}: {str(e)}'
        session['last_error'] = error_msg
        return {
            'success': False,
            'error': error_msg
        }

def _mkdir_subprocess(session: Dict[str, Any], remote_dir: str) -> Dict[str, Any]:
    """Create directory using subprocess (ssh + mkdir)"""
    try:
        # Build ssh command
        cmd = ['ssh']

        # Add SSH options
        ssh_options = session.get('ssh_options', {})
        if 'identity_file' in ssh_options:
            cmd.extend(['-i', ssh_options['identity_file']])

        # Remote target and command
        remote_target = f"{session['user']}@{session['host']}"
        cmd.extend([remote_target, f'mkdir -p "{remote_dir}"'])

        result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)

        if result.returncode == 0:
            return {
                'success': True,
                'result': {
                    'remote_dir': remote_dir,
                    'created_at': time.time()
                }
            }
        else:
            error_msg = f'mkdir failed: {result.stderr.strip()}'
            session['last_error'] = error_msg
            return {
                'success': False,
                'error': error_msg
            }

    except Exception as e:
        error_msg = f'Failed to create directory {remote_dir}: {str(e)}'
        session['last_error'] = error_msg
        return {
            'success': False,
            'error': error_msg
        }

def remove(session_id: str, remote_file: str) -> Dict[str, Any]:
    """
    Remove file from remote server (matches $sftp->remove())

    Args:
        session_id: Active SFTP session ID
        remote_file: Remote file path

    Returns:
        Dictionary with operation result
    """
    try:
        if session_id not in SFTP_SESSIONS:
            return {
                'success': False,
                'error': 'SFTP session not found or expired'
            }

        session = SFTP_SESSIONS[session_id]

        if session['connection_type'] == 'paramiko':
            return _remove_paramiko(session, remote_file)
        else:
            return _remove_subprocess(session, remote_file)

    except Exception as e:
        error_msg = f'SFTP remove operation failed: {str(e)}'
        if session_id in SFTP_SESSIONS:
            SFTP_SESSIONS[session_id]['last_error'] = error_msg
        return {
            'success': False,
            'error': error_msg
        }

def _remove_paramiko(session: Dict[str, Any], remote_file: str) -> Dict[str, Any]:
    """Remove file using paramiko"""
    sftp = session['sftp']

    # Handle relative paths
    if not remote_file.startswith('/'):
        remote_file = f"{session['current_dir'].rstrip('/')}/{remote_file}"

    try:
        sftp.remove(remote_file)
        return {
            'success': True,
            'result': {
                'remote_file': remote_file,
                'removed_at': time.time()
            }
        }
    except Exception as e:
        error_msg = f'Failed to remove {remote_file}: {str(e)}'
        session['last_error'] = error_msg
        return {
            'success': False,
            'error': error_msg
        }

def _remove_subprocess(session: Dict[str, Any], remote_file: str) -> Dict[str, Any]:
    """Remove file using subprocess (ssh + rm)"""
    try:
        # Build ssh command
        cmd = ['ssh']

        # Add SSH options
        ssh_options = session.get('ssh_options', {})
        if 'identity_file' in ssh_options:
            cmd.extend(['-i', ssh_options['identity_file']])

        # Remote target and command
        remote_target = f"{session['user']}@{session['host']}"
        cmd.extend([remote_target, f'rm "{remote_file}"'])

        result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)

        if result.returncode == 0:
            return {
                'success': True,
                'result': {
                    'remote_file': remote_file,
                    'removed_at': time.time()
                }
            }
        else:
            error_msg = f'rm failed: {result.stderr.strip()}'
            session['last_error'] = error_msg
            return {
                'success': False,
                'error': error_msg
            }

    except Exception as e:
        error_msg = f'Failed to remove {remote_file}: {str(e)}'
        session['last_error'] = error_msg
        return {
            'success': False,
            'error': error_msg
        }