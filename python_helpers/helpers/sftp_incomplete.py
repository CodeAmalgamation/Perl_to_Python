#!/usr/bin/env python3
"""
sftp.py - SFTP backend for Net::SFTP::Foreign replacement

Provides SFTP functionality using paramiko or built-in SFTP capabilities.
Focused implementation based on actual usage analysis from enterprise Perl scripts.
"""

import os
import re
import stat
import time
import uuid
from typing import Dict, List, Any, Optional

# Global session storage
SFTP_SESSIONS = {}

def connect(host: str, user: str, port: int = 22, timeout: int = 60,
           password: str = None, ssh_options: Dict[str, str] = None) -> Dict[str, Any]:
    """
    Establish SFTP connection
    
    Args:
        host: Remote hostname
        user: Username for authentication
        port: SSH port (default 22)
        timeout: Connection timeout in seconds
        password: Password for authentication (optional)
        ssh_options: SSH options dict (identity_file, etc.)
    
    Returns:
        Dictionary with connection result and session ID
    """
    try:
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
    if password:
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
    initial_dir = sftp.getcwd() or '/'
    
    # Generate session ID and store connection
    session_id = str(uuid.uuid4())
    SFTP_SESSIONS[session_id] = {
        'ssh': ssh,
        'sftp': sftp,
        'host': host,
        'user': user,
        'current_dir': initial_dir,
        'connected_at': time.time(),
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
    # For environments where paramiko is not available
    # This is a simplified implementation - you may need to enhance based on your environment
    
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
    }
    
    return {
        'success': True,
        'result': {
            'session_id': session_id,
            'initial_dir': '/',
            'connection_type': 'subprocess',
        }
    }

def put(session_id: str, local_file: str, remote_file: str, current_dir: str = None) -> Dict[str, Any]:
    """
    Upload file to remote server
    
    Args:
        session_id: Active SFTP session ID
        local_file: Local file path
        remote_file: Remote file path
        current_dir: Current working directory context
    
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
            return {
                'success': False,
                'error': f'Local file not found: {local_file}'
            }
        
        if session['connection_type'] == 'paramiko':
            return _put_paramiko(session, local_file, remote_file, current_dir)
        else:
            return _put_subprocess(session, local_file, remote_file, current_dir)
            
    except Exception as e:
        return {
            'success': False,
            'error': f'SFTP put operation failed: {str(e)}'
        }

def _put_paramiko(session: Dict[str, Any], local_file: str, remote_file: str, current_dir: str) -> Dict[str, Any]:
    """Upload file using paramiko"""
    sftp = session['sftp']
    
    # Handle relative paths
    if not remote_file.startswith('/') and current_dir:
        remote_file = f"{current_dir.rstrip('/')}/{remote_file}"
    
    # Create remote directories if needed
    remote_dir = os.path.dirname(remote_file)
    if remote_dir and remote_dir != '/':
        _ensure_remote_directory(sftp, remote_dir)
    
    # Upload file
    sftp.put(local_file, remote_file)
    
    return {
        'success': True,
        'result': {
            'local_file': local_file,
            'remote_file': remote_file,
            'bytes_transferred': os.path.getsize(local_file)
        }
    }

def _put_subprocess(session: Dict[str, Any], local_file: str, remote_file: str, current_dir: str) -> Dict[str, Any]:
    """Upload file using subprocess + scp/sftp commands"""
    import subprocess
    
    # Build scp command
    host = session['host']
    user = session['user']
    port = session['port']
    
    # Handle relative paths
    if not remote_file.startswith('/') and current_dir:
        remote_file = f"{current_dir.rstrip('/')}/{remote_file}"
    
    cmd = ['scp', '-P', str(port)]
    
    # Add identity file if specified
    if 'identity_file' in session.get('ssh_options', {}):
        cmd.extend(['-i', session['ssh_options']['identity_file']])
    
    cmd.extend([local_file, f'{user}@{host}:{remote_file}'])
    
    # Execute scp command
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=300)
    
    if result.returncode == 0:
        return {
            'success': True,
            'result': {
                'local_file': local_file,
                'remote_file': remote_file,
                'command': ' '.join(cmd)
            }
        }
    else:
        return {
            'success': False,
            'error': f'scp failed: {result.stderr or result.stdout}'
        }

def ls(session_id: str, remote_dir: str = None, wanted_pattern: str = None) -> Dict[str, Any]:
    """
    List directory contents with optional pattern matching
    
    Args:
        session_id: Active SFTP session ID
        remote_dir: Directory to list (default current)
        wanted_pattern: Regex pattern to match files
    
    Returns:
        Dictionary with file listing
    """
    try:
        if session_id not in SFTP_SESSIONS:
            return {
                'success': False,
                'error': 'SFTP session not found or expired'
            }
        
        session = SFTP_SESSIONS[session_id]
        
        if session['connection_type'] == 'paramiko':
            return _ls_paramiko(session, remote_dir, wanted_pattern)
        else:
            return _ls_subprocess(session, remote_dir, wanted_pattern)
            
    except Exception as e:
        return {
            'success': False,
            'error': f'SFTP ls operation failed: {str(e)}'
        }

def _ls_paramiko(session: Dict[str, Any], remote_dir: str, wanted_pattern: str) -> Dict[str, Any]:
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
            
            # Apply pattern filter if specified
            if wanted_pattern:
                try:
                    if re.search(wanted_pattern, entry.filename):
                        entries.append(entry_info)
                except re.error:
                    # If regex is invalid, treat as literal string
                    if wanted_pattern in entry.filename:
                        entries.append(entry_info)
            else:
                entries.append(entry_info)
                
    except FileNotFoundError:
        return {
            'success': False,
            'error': f'Directory not found: {list_dir}'
        }
    
    return {
        'success': True,
        'result': {
            'entries': entries,
            'directory': list_dir,
            'pattern': wanted_pattern,
            'count': len(entries)
        }
    }

def _ls_subprocess(session: Dict[str, Any], remote_dir: str, wanted_pattern: str) -> Dict[str, Any]:
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
        return {
            'success': False,
            'error': f'ls failed: {result.stderr or result.stdout}'
        }
    
    # Parse ls output
    entries = []
    for line in result.stdout.strip().split('\n'):
        if line and not line.startswith('total'):
            entry_info = _parse_ls_line(line)
            if entry_info:
                # Apply pattern filter
                if wanted_pattern:
                    try:
                        if re.search(wanted_pattern, entry_info['filename']):
                            entries.append(entry_info)
                    except re.error:
                        if wanted_pattern in entry_info['filename']:
                            entries.append(entry_info)
                else:
                    entries.append(entry_info)
    
    return {
        'success': True,
        'result': {
            'entries': entries,
            'directory': list_dir,
            'pattern': wanted_pattern,
            'count': len(entries)
        }
    }

def rename(session_id: str, old_name: str, new_name: str, current_dir: str = None, overwrite: bool = False) -> Dict[str, Any]:
    """
    Rename/move file on remote server
    
    Args:
        session_id: Active SFTP session ID
        old_name: Current file name
        new_name: New file name
        current_dir: Current working directory context
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
        
        session