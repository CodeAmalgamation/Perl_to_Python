#!/usr/bin/env python3
"""
helpers/smtp_helper.py - Net::SMTP replacement for RHEL 9 migration

Provides drop-in compatibility with Net::SMTP module using Python's smtplib.
Maintains connection state across multiple method calls via connection pooling.

Usage Pattern (from 30165CbiWasCtl.pl):
    my $smtp = Net::SMTP->new('sslmsmtp', Timeout => 30, Debug => 0);
    $smtp->mail("sender@domain.com");
    $smtp->to("recipient@domain.com");
    $smtp->data();
    $smtp->datasend("To: recipient@domain.com\n");
    $smtp->datasend("From: sender@domain.com\n");
    $smtp->datasend("Subject: Test\n");
    $smtp->datasend("\n");
    $smtp->datasend("Body content");
    $smtp->datasend();  # Flush and send
    $smtp->quit();

Key Features:
- Connection pooling with unique IDs
- State tracking (connected, data_mode, closed)
- Data buffering for multiple datasend() calls
- 5-minute auto-cleanup for stale connections
- Full error handling matching Net::SMTP behavior
"""

import smtplib
import time
import uuid
import threading
import traceback
from typing import Dict, Any, Optional, List

# Connection pool - stores active SMTP connections
_smtp_connections: Dict[str, Dict[str, Any]] = {}
_connections_lock = threading.Lock()

# Configuration
CONNECTION_CLEANUP_TIMEOUT = 300  # 5 minutes in seconds

# Connection states
STATE_CONNECTED = "connected"
STATE_DATA_MODE = "data_mode"
STATE_CLOSED = "closed"


def new(host: str, port: int = 25, timeout: int = 30, debug: int = 0,
        localhost: Optional[str] = None) -> Dict[str, Any]:
    """
    Create new SMTP connection (Net::SMTP->new() equivalent)

    Args:
        host: SMTP server hostname
        port: SMTP port (default 25)
        timeout: Connection timeout in seconds (default 30)
        debug: Debug level 0-2 (default 0)
        localhost: Local hostname for HELO/EHLO (optional)

    Returns:
        Dict with connection_id or error

    Example:
        Net::SMTP->new('sslmsmtp', Timeout => 30, Debug => 0)
    """
    try:
        # Generate unique connection ID
        connection_id = f"smtp_{int(time.time())}_{uuid.uuid4().hex[:8]}"

        # Create SMTP connection
        smtp = smtplib.SMTP(host, port=port, timeout=timeout,
                           local_hostname=localhost)

        # Set debug level if requested
        if debug > 0:
            smtp.set_debuglevel(debug)

        # Store connection in pool with state
        with _connections_lock:
            _smtp_connections[connection_id] = {
                'smtp': smtp,
                'state': STATE_CONNECTED,
                'data_buffer': [],
                'created_at': time.time(),
                'last_used': time.time(),
                'host': host,
                'port': port,
                'sender': None,
                'recipients': []
            }

        return {
            'success': True,
            'connection_id': connection_id
        }

    except smtplib.SMTPException as e:
        return {
            'success': False,
            'error': f"SMTP connection failed: {str(e)}"
        }
    except Exception as e:
        return {
            'success': False,
            'error': f"Connection error: {str(e)}"
        }


def mail(connection_id: str, sender: str) -> Dict[str, Any]:
    """
    Set sender address (Net::SMTP->mail() equivalent)

    Args:
        connection_id: Connection ID from new()
        sender: Sender email address

    Returns:
        Dict with success status

    Example:
        $smtp->mail("sender@domain.com")
    """
    try:
        conn = _get_connection(connection_id)

        # Validate state
        if conn['state'] not in [STATE_CONNECTED]:
            return {
                'success': False,
                'error': f"Cannot call mail() in state: {conn['state']}"
            }

        # Call SMTP MAIL command
        smtp = conn['smtp']
        code, message = smtp.mail(sender)

        # Check response code (250 = success)
        if code != 250:
            return {
                'success': False,
                'error': f"MAIL command failed: {code} {message.decode()}"
            }

        # Store sender for reference
        conn['sender'] = sender
        conn['last_used'] = time.time()

        return {
            'success': True
        }

    except KeyError:
        return {
            'success': False,
            'error': f"Invalid connection ID: {connection_id}"
        }
    except smtplib.SMTPException as e:
        _cleanup_connection(connection_id)
        return {
            'success': False,
            'error': f"SMTP error in mail(): {str(e)}"
        }
    except Exception as e:
        _cleanup_connection(connection_id)
        return {
            'success': False,
            'error': f"Error in mail(): {str(e)}"
        }


def to(connection_id: str, recipient: str) -> Dict[str, Any]:
    """
    Add recipient address (Net::SMTP->to() equivalent)

    Args:
        connection_id: Connection ID from new()
        recipient: Recipient email address

    Returns:
        Dict with success status

    Example:
        $smtp->to("recipient@domain.com")
    """
    try:
        conn = _get_connection(connection_id)

        # Validate state
        if conn['state'] not in [STATE_CONNECTED]:
            return {
                'success': False,
                'error': f"Cannot call to() in state: {conn['state']}"
            }

        # Call SMTP RCPT command
        smtp = conn['smtp']
        code, message = smtp.rcpt(recipient)

        # Check response code (250 or 251 = success)
        if code not in [250, 251]:
            return {
                'success': False,
                'error': f"RCPT command failed: {code} {message.decode()}"
            }

        # Store recipient for reference
        conn['recipients'].append(recipient)
        conn['last_used'] = time.time()

        return {
            'success': True
        }

    except KeyError:
        return {
            'success': False,
            'error': f"Invalid connection ID: {connection_id}"
        }
    except smtplib.SMTPException as e:
        _cleanup_connection(connection_id)
        return {
            'success': False,
            'error': f"SMTP error in to(): {str(e)}"
        }
    except Exception as e:
        _cleanup_connection(connection_id)
        return {
            'success': False,
            'error': f"Error in to(): {str(e)}"
        }


def data(connection_id: str) -> Dict[str, Any]:
    """
    Start message data mode (Net::SMTP->data() equivalent)

    Args:
        connection_id: Connection ID from new()

    Returns:
        Dict with success status

    Example:
        $smtp->data()
    """
    try:
        conn = _get_connection(connection_id)

        # Validate state
        if conn['state'] != STATE_CONNECTED:
            return {
                'success': False,
                'error': f"Cannot call data() in state: {conn['state']}"
            }

        # Validate sender and recipients set
        if not conn['sender']:
            return {
                'success': False,
                'error': "Must call mail() before data()"
            }

        if not conn['recipients']:
            return {
                'success': False,
                'error': "Must call to() before data()"
            }

        # Call SMTP DATA command
        smtp = conn['smtp']
        code, message = smtp.docmd('DATA')

        # Check response code (354 = ready for data)
        if code != 354:
            return {
                'success': False,
                'error': f"DATA command failed: {code} {message.decode()}"
            }

        # Enter data mode and clear buffer
        conn['state'] = STATE_DATA_MODE
        conn['data_buffer'] = []
        conn['last_used'] = time.time()

        return {
            'success': True
        }

    except KeyError:
        return {
            'success': False,
            'error': f"Invalid connection ID: {connection_id}"
        }
    except smtplib.SMTPException as e:
        _cleanup_connection(connection_id)
        return {
            'success': False,
            'error': f"SMTP error in data(): {str(e)}"
        }
    except Exception as e:
        _cleanup_connection(connection_id)
        return {
            'success': False,
            'error': f"Error in data(): {str(e)}"
        }


def datasend(connection_id: str, data: Optional[str] = None) -> Dict[str, Any]:
    """
    Send message data or flush buffer (Net::SMTP->datasend() equivalent)

    Args:
        connection_id: Connection ID from new()
        data: Data to send (None = flush and complete message)

    Returns:
        Dict with success status

    Example:
        $smtp->datasend("To: recipient@domain.com\n")
        $smtp->datasend("Subject: Test\n")
        $smtp->datasend("\n")
        $smtp->datasend("Body")
        $smtp->datasend()  # Flush
    """
    try:
        conn = _get_connection(connection_id)

        # Validate state
        if conn['state'] != STATE_DATA_MODE:
            return {
                'success': False,
                'error': f"Cannot call datasend() in state: {conn['state']}. Must call data() first."
            }

        smtp = conn['smtp']

        # If data provided, buffer it
        if data is not None:
            conn['data_buffer'].append(data)
            conn['last_used'] = time.time()
            return {
                'success': True
            }

        # No data = flush buffer and send
        if not conn['data_buffer']:
            return {
                'success': False,
                'error': "No data to send (buffer empty)"
            }

        # Combine buffered data
        message = ''.join(conn['data_buffer'])

        # Send message and end data mode
        smtp.send(message.encode())
        code, response = smtp.getreply()

        # Check response code (250 = message accepted)
        if code != 250:
            return {
                'success': False,
                'error': f"Message send failed: {code} {response.decode()}"
            }

        # Clear buffer and return to connected state
        conn['data_buffer'] = []
        conn['state'] = STATE_CONNECTED
        conn['last_used'] = time.time()

        return {
            'success': True
        }

    except KeyError:
        return {
            'success': False,
            'error': f"Invalid connection ID: {connection_id}"
        }
    except smtplib.SMTPException as e:
        _cleanup_connection(connection_id)
        return {
            'success': False,
            'error': f"SMTP error in datasend(): {str(e)}"
        }
    except Exception as e:
        _cleanup_connection(connection_id)
        return {
            'success': False,
            'error': f"Error in datasend(): {str(e)}"
        }


def quit(connection_id: str) -> Dict[str, Any]:
    """
    Close SMTP connection (Net::SMTP->quit() equivalent)

    Args:
        connection_id: Connection ID from new()

    Returns:
        Dict with success status

    Example:
        $smtp->quit()
    """
    try:
        conn = _get_connection(connection_id)

        # Close SMTP connection
        smtp = conn['smtp']
        try:
            smtp.quit()
        except Exception:
            # Ignore errors on quit, just cleanup
            pass

        # Remove from pool
        _cleanup_connection(connection_id)

        return {
            'success': True
        }

    except KeyError:
        # Already cleaned up or invalid ID - not an error
        return {
            'success': True
        }
    except Exception as e:
        # Ensure cleanup even on error
        _cleanup_connection(connection_id)
        return {
            'success': True,
            'warning': f"Error during quit (connection cleaned up): {str(e)}"
        }


def cleanup_stale_connections() -> Dict[str, Any]:
    """
    Clean up connections older than 5 minutes (300 seconds)

    Called periodically by daemon or manually for testing

    Returns:
        Dict with cleanup statistics
    """
    try:
        current_time = time.time()
        stale_connections = []

        with _connections_lock:
            for conn_id, conn in list(_smtp_connections.items()):
                age = current_time - conn['last_used']
                if age > CONNECTION_CLEANUP_TIMEOUT:
                    stale_connections.append(conn_id)

        # Clean up stale connections
        cleaned = 0
        for conn_id in stale_connections:
            try:
                conn = _smtp_connections.get(conn_id)
                if conn:
                    conn['smtp'].quit()
            except Exception:
                pass
            _cleanup_connection(conn_id)
            cleaned += 1

        return {
            'success': True,
            'cleaned': cleaned,
            'active_connections': len(_smtp_connections)
        }

    except Exception as e:
        return {
            'success': False,
            'error': f"Error during cleanup: {str(e)}"
        }


def get_connection_info(connection_id: str) -> Dict[str, Any]:
    """
    Get connection information for debugging

    Args:
        connection_id: Connection ID

    Returns:
        Dict with connection details
    """
    try:
        conn = _get_connection(connection_id)

        return {
            'success': True,
            'connection': {
                'id': connection_id,
                'host': conn['host'],
                'port': conn['port'],
                'state': conn['state'],
                'sender': conn['sender'],
                'recipients': conn['recipients'],
                'buffer_size': len(conn['data_buffer']),
                'age': time.time() - conn['created_at'],
                'idle': time.time() - conn['last_used']
            }
        }

    except KeyError:
        return {
            'success': False,
            'error': f"Invalid connection ID: {connection_id}"
        }


def get_pool_stats() -> Dict[str, Any]:
    """
    Get connection pool statistics

    Returns:
        Dict with pool statistics
    """
    try:
        with _connections_lock:
            active = len(_smtp_connections)
            states = {}
            for conn in _smtp_connections.values():
                state = conn['state']
                states[state] = states.get(state, 0) + 1

        return {
            'success': True,
            'stats': {
                'active_connections': active,
                'states': states,
                'cleanup_timeout': CONNECTION_CLEANUP_TIMEOUT
            }
        }

    except Exception as e:
        return {
            'success': False,
            'error': f"Error getting stats: {str(e)}"
        }


# Internal helper functions

def _get_connection(connection_id: str) -> Dict[str, Any]:
    """
    Get connection from pool (raises KeyError if not found)

    Args:
        connection_id: Connection ID

    Returns:
        Connection dict
    """
    with _connections_lock:
        return _smtp_connections[connection_id]


def _cleanup_connection(connection_id: str) -> None:
    """
    Remove connection from pool

    Args:
        connection_id: Connection ID to remove
    """
    with _connections_lock:
        if connection_id in _smtp_connections:
            del _smtp_connections[connection_id]


# Module initialization
if __name__ == "__main__":
    print("SMTP Helper Module")
    print("=" * 60)
    print(f"Connection cleanup timeout: {CONNECTION_CLEANUP_TIMEOUT}s")
    print(f"Supported methods: new, mail, to, data, datasend, quit")
    print(f"State transitions: {STATE_CONNECTED} -> {STATE_DATA_MODE} -> {STATE_CONNECTED}")
