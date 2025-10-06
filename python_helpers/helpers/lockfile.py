#!/usr/bin/env python3
"""
lockfile.py - LockFile::Simple replacement using Python file locking

Provides NFS-safe file locking functionality matching LockFile::Simple usage patterns.
Supports stale lock detection, %F token replacement, and non-blocking trylock behavior.
"""

import os
import time
import fcntl
import traceback
from typing import Dict, Any, Optional
from pathlib import Path

# Global state for lock instances
LOCK_INSTANCES = {}
LOCK_MANAGERS = {}

def make(nfs: bool = False, hold: int = 90, max_age: int = None,
         delay: int = 1, max_wait: int = None) -> Dict[str, Any]:
    """
    Create new lock manager instance (matches LockFile::Simple->make())

    Args:
        nfs: Enable NFS-safe locking (default: False)
        hold: Seconds after which lock becomes stale (default: 90)
        max_age: Deprecated, same as hold
        delay: Retry delay in seconds (default: 1)
        max_wait: Maximum wait time for lock (default: None = don't wait)

    Returns:
        Dictionary with lock manager ID and configuration
    """
    try:
        # Process parameters (max_age is deprecated alias for hold)
        if max_age is not None:
            hold = max_age

        # Create lock manager ID
        import uuid
        manager_id = str(uuid.uuid4())

        # Store lock manager configuration
        LOCK_MANAGERS[manager_id] = {
            'nfs': nfs,
            'hold': hold,
            'delay': delay,
            'max_wait': max_wait,
            'created_at': time.time(),
            'locks': {}  # Track locks created by this manager
        }

        return {
            'success': True,
            'result': {
                'manager_id': manager_id,
                'nfs': nfs,
                'hold': hold
            }
        }

    except Exception as e:
        return {
            'success': False,
            'error': f'Lock manager creation failed: {str(e)}',
            'traceback': traceback.format_exc() if _is_debug_mode() else None
        }

def trylock(manager_id: str, filename: str, lockfile_pattern: str = None) -> Dict[str, Any]:
    """
    Attempt to acquire lock (non-blocking, matches $lockmgr->trylock())

    Args:
        manager_id: Lock manager ID from make()
        filename: File to lock (used for %F replacement)
        lockfile_pattern: Lock file pattern (e.g., "/path/%F.lock")

    Returns:
        Dictionary with lock instance ID if successful, or error if failed
    """
    try:
        if manager_id not in LOCK_MANAGERS:
            return {
                'success': False,
                'error': 'Invalid lock manager ID or manager expired'
            }

        manager = LOCK_MANAGERS[manager_id]

        # Determine lock file path
        if lockfile_pattern:
            # Replace %F token with filename
            lockfile_path = lockfile_pattern.replace('%F', filename)
        else:
            # Default: filename + .lock
            lockfile_path = f"{filename}.lock"

        # Expand environment variables
        lockfile_path = os.path.expandvars(lockfile_path)

        # Check for stale locks and clean them up
        if os.path.exists(lockfile_path):
            if _is_stale_lock(lockfile_path, manager['hold']):
                try:
                    os.remove(lockfile_path)
                except OSError:
                    # If we can't remove it, it might be held by another process
                    pass

        # Try to acquire lock
        try:
            # Create directory if it doesn't exist
            lock_dir = os.path.dirname(lockfile_path)
            if lock_dir and not os.path.exists(lock_dir):
                os.makedirs(lock_dir, exist_ok=True)

            # Try to create lock file exclusively
            # Use O_CREAT | O_EXCL for atomic creation (NFS-safe)
            try:
                fd = os.open(lockfile_path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o644)
            except FileExistsError:
                # Lock file exists - check if it's stale
                if _is_stale_lock(lockfile_path, manager['hold']):
                    # Try to remove stale lock
                    try:
                        os.remove(lockfile_path)
                        # Try again
                        fd = os.open(lockfile_path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o644)
                    except (OSError, FileExistsError):
                        # Another process got it first
                        return {
                            'success': False,
                            'error': f'Could not acquire lock on {filename}: Lock file exists'
                        }
                else:
                    # Lock is not stale, can't acquire
                    return {
                        'success': False,
                        'error': f'Could not acquire lock on {filename}: Lock file exists'
                    }

            # Write PID to lock file
            os.write(fd, str(os.getpid()).encode('utf-8'))
            os.close(fd)

            # Create lock instance
            import uuid
            lock_id = str(uuid.uuid4())

            LOCK_INSTANCES[lock_id] = {
                'manager_id': manager_id,
                'filename': filename,
                'lockfile_path': lockfile_path,
                'acquired_at': time.time(),
                'pid': os.getpid()
            }

            # Track lock in manager
            manager['locks'][lock_id] = lockfile_path

            return {
                'success': True,
                'result': {
                    'lock_id': lock_id,
                    'filename': filename,
                    'lockfile': lockfile_path
                }
            }

        except Exception as e:
            return {
                'success': False,
                'error': f'Could not acquire lock on {filename}: {str(e)}'
            }

    except Exception as e:
        return {
            'success': False,
            'error': f'Lock acquisition failed: {str(e)}',
            'traceback': traceback.format_exc() if _is_debug_mode() else None
        }

def release(lock_id: str) -> Dict[str, Any]:
    """
    Release acquired lock (matches $lock->release())

    Args:
        lock_id: Lock instance ID from trylock()

    Returns:
        Dictionary with release result
    """
    try:
        if lock_id not in LOCK_INSTANCES:
            return {
                'success': False,
                'error': 'Invalid lock ID or lock already released'
            }

        lock = LOCK_INSTANCES[lock_id]
        lockfile_path = lock['lockfile_path']

        # Remove lock file
        try:
            if os.path.exists(lockfile_path):
                os.remove(lockfile_path)
        except OSError as e:
            return {
                'success': False,
                'error': f'Failed to release lock: {str(e)}'
            }

        # Remove lock from manager tracking
        if lock['manager_id'] in LOCK_MANAGERS:
            manager = LOCK_MANAGERS[lock['manager_id']]
            if lock_id in manager['locks']:
                del manager['locks'][lock_id]

        # Remove lock instance
        del LOCK_INSTANCES[lock_id]

        return {
            'success': True,
            'result': {
                'lock_id': lock_id,
                'released': True
            }
        }

    except Exception as e:
        return {
            'success': False,
            'error': f'Lock release failed: {str(e)}',
            'traceback': traceback.format_exc() if _is_debug_mode() else None
        }

def cleanup_manager(manager_id: str) -> Dict[str, Any]:
    """
    Clean up lock manager and all its locks

    Args:
        manager_id: Lock manager ID

    Returns:
        Dictionary with cleanup result
    """
    try:
        if manager_id not in LOCK_MANAGERS:
            return {
                'success': True,
                'result': {
                    'manager_id': manager_id,
                    'cleaned_up': True
                }
            }

        manager = LOCK_MANAGERS[manager_id]

        # Release all locks created by this manager
        for lock_id in list(manager['locks'].keys()):
            if lock_id in LOCK_INSTANCES:
                release(lock_id)

        # Remove manager
        del LOCK_MANAGERS[manager_id]

        return {
            'success': True,
            'result': {
                'manager_id': manager_id,
                'cleaned_up': True
            }
        }

    except Exception as e:
        return {
            'success': False,
            'error': f'Manager cleanup failed: {str(e)}'
        }

def _is_stale_lock(lockfile_path: str, hold_time: int) -> bool:
    """
    Check if lock file is stale based on modification time

    Args:
        lockfile_path: Path to lock file
        hold_time: Seconds after which lock is considered stale

    Returns:
        True if lock is stale, False otherwise
    """
    try:
        if not os.path.exists(lockfile_path):
            return False

        # Get file modification time
        mtime = os.path.getmtime(lockfile_path)
        current_time = time.time()

        # Check if lock is older than hold time
        age = current_time - mtime
        return age > hold_time

    except Exception:
        # If we can't determine, assume not stale
        return False

def _is_debug_mode() -> bool:
    """Check if debug mode is enabled"""
    return os.environ.get('CPAN_BRIDGE_DEBUG', '0') != '0'

# Test and utility functions
def test_lockfile_functionality():
    """Test basic lockfile functionality"""
    print("Testing LockFile functionality...")

    try:
        # Create lock manager
        result = make(nfs=True, hold=90)
        if not result['success']:
            print(f"✗ Lock manager creation failed: {result['error']}")
            return False

        manager_id = result['result']['manager_id']
        print(f"✓ Lock manager created: {manager_id}")

        # Test lock acquisition
        test_file = "/tmp/test_lockfile.txt"
        lock_pattern = "/tmp/%F.lock"

        result = trylock(manager_id, test_file, lock_pattern)
        if not result['success']:
            print(f"✗ Lock acquisition failed: {result['error']}")
            return False

        lock_id = result['result']['lock_id']
        print(f"✓ Lock acquired: {lock_id}")
        print(f"  Lock file: {result['result']['lockfile']}")

        # Test double-lock (should fail)
        result = trylock(manager_id, test_file, lock_pattern)
        if result['success']:
            print("✗ Double-lock should have failed but succeeded")
            return False
        else:
            print(f"✓ Double-lock correctly rejected: {result['error']}")

        # Test lock release
        result = release(lock_id)
        if not result['success']:
            print(f"✗ Lock release failed: {result['error']}")
            return False

        print("✓ Lock released successfully")

        # Test re-acquisition after release
        result = trylock(manager_id, test_file, lock_pattern)
        if not result['success']:
            print(f"✗ Re-acquisition failed: {result['error']}")
            return False

        lock_id2 = result['result']['lock_id']
        print(f"✓ Lock re-acquired: {lock_id2}")

        # Cleanup
        result = cleanup_manager(manager_id)
        if not result['success']:
            print(f"✗ Manager cleanup failed: {result['error']}")
            return False

        print("✓ Manager cleaned up")

        # Verify lock file removed
        if os.path.exists("/tmp/test_lockfile.txt.lock"):
            print("✗ Lock file still exists after cleanup")
            return False

        print("✓ All tests PASSED")
        return True

    except Exception as e:
        print(f"✗ Test failed with exception: {e}")
        traceback.print_exc()
        return False

if __name__ == "__main__":
    # Run basic functionality test
    test_lockfile_functionality()
