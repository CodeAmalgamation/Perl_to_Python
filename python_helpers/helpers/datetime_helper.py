#!/usr/bin/env python3
"""
helpers/datetime_helper.py - Minimal DateTime processing for DateTimeHelper.pm

Focused solely on DateTime->now->epoch pattern found in codebase analysis.
Uses Python's built-in time module for timestamp generation.
Renamed from datetime.py to avoid conflict with Python's datetime module.
"""

import time
import traceback
import os
from typing import Dict, Any

def now() -> Dict[str, Any]:
    """
    Get current Unix timestamp - supports DateTime->now->epoch pattern
    
    This is the only DateTime functionality used in your codebase:
    - DateTime->now->epoch for EPV key generation
    - Current timestamp for database operations
    
    Returns:
        Dict containing success status and epoch timestamp
    """
    try:
        # Get current Unix timestamp
        current_timestamp = int(time.time())
        
        return {
            'success': True,
            'result': {
                'epoch': current_timestamp
            }
        }
        
    except Exception as e:
        # Comprehensive error handling for production
        error_details = {
            'success': False,
            'error': f"Failed to get current timestamp: {str(e)}",
            'error_type': type(e).__name__
        }
        
        # Include traceback in debug mode
        if _is_debug_mode():
            error_details['traceback'] = traceback.format_exc()
        
        return error_details

def _is_debug_mode() -> bool:
    """Check if debug mode is enabled via environment variable"""
    return os.environ.get('CPAN_BRIDGE_DEBUG', '0') != '0'

# Test function for development and validation
def _test_basic_functionality():
    """Test the core functionality used in production"""
    print("Testing DateTime->now->epoch pattern...")
    
    # Test multiple calls to ensure consistency
    timestamps = []
    for i in range(3):
        result = now()
        
        if not result['success']:
            print(f"ERROR: Test {i+1} failed: {result['error']}")
            return False
        
        timestamp = result['result']['epoch']
        timestamps.append(timestamp)
        print(f"Test {i+1}: timestamp = {timestamp}")
        
        # Small delay to ensure timestamps are different (need 1+ seconds for int timestamps)
        time.sleep(1.1)
    
    # Validate timestamps are reasonable (within last 24 hours and increasing)
    current_time = int(time.time())
    for i, ts in enumerate(timestamps):
        if abs(ts - current_time) > 86400:  # 24 hours
            print(f"ERROR: Timestamp {i+1} seems unreasonable: {ts}")
            return False
        
        if i > 0 and ts <= timestamps[i-1]:
            print(f"ERROR: Timestamp {i+1} not increasing: {ts} <= {timestamps[i-1]}")
            return False
    
    print("All tests passed - ready for production!")
    return True

if __name__ == "__main__":
    # Run test when called directly
    _test_basic_functionality()