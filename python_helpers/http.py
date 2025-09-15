#!/usr/bin/env python3
"""
http.py - HTTP backend for LWP::UserAgent and WWW::Mechanize replacement

Provides HTTP client functionality using only Python standard library modules.
Focused implementation based on actual usage analysis from enterprise Perl scripts.
"""

import urllib.request
import urllib.parse
import urllib.error
import ssl
import time
import re
from typing import Dict, Any, Optional

def lwp_request(method: str, url: str, headers: Dict[str, str] = None, 
               content: str = None, form_encoded_content: str = None,
               timeout: int = 180, verify_ssl: bool = True) -> Dict[str, Any]:
    """
    Make an HTTP request compatible with LWP::UserAgent patterns
    
    Args:
        method: HTTP method (GET, POST, etc.)
        url: Request URL
        headers: Request headers dictionary
        content: Raw request body content
        form_encoded_content: Form-encoded content (for proper handling)
        timeout: Request timeout in seconds (default 180 to match LWP)
        verify_ssl: Whether to verify SSL certificates
    
    Returns:
        Dictionary with response data compatible with LWP::UserAgent
    """
    try:
        # Prepare request headers
        req_headers = headers or {}
        
        # Prepare request body
        request_data = None
        if form_encoded_content:
            # Handle form-encoded content (your main usage pattern)
            request_data = form_encoded_content.encode('utf-8')
        elif content:
            # Handle raw content
            request_data = content.encode('utf-8') if isinstance(content, str) else content
        
        # Create request object
        req = urllib.request.Request(url, data=request_data, headers=req_headers, method=method)
        
        # Configure SSL context (handles PERL_LWP_SSL_VERIFY_HOSTNAME)
        ssl_context = ssl.create_default_context()
        if not verify_ssl:
            ssl_context.check_hostname = False
            ssl_context.verify_mode = ssl.CERT_NONE
        
        # Create URL opener with SSL context
        https_handler = urllib.request.HTTPSHandler(context=ssl_context)
        opener = urllib.request.build_opener(https_handler)
        
        # Make the request
        start_time = time.time()
        
        try:
            response = opener.open(req, timeout=timeout)
            
            # Read response body
            response_body = response.read()
            
            # Handle response encoding
            content_type = response.headers.get('Content-Type', '')
            charset = _extract_charset(content_type)
            
            try:
                content_text = response_body.decode(charset)
            except (UnicodeDecodeError, LookupError):
                content_text = response_body.decode('utf-8', errors='replace')
            
            # Build response compatible with LWP::UserAgent
            result = {
                'success': True,
                'status_code': response.getcode(),
                'reason': _get_reason_phrase(response.getcode()),
                'status_line': f"{response.getcode()} {_get_reason_phrase(response.getcode())}",
                'content': content_text,
                'body': content_text,  # Alias for compatibility
                'headers': dict(response.headers),
                'url': response.geturl(),
                'elapsed': time.time() - start_time,
            }
            
            return result
            
        except urllib.error.HTTPError as e:
            # Handle HTTP errors (4xx, 5xx) - return response for error handling
            error_body = ''
            try:
                error_content = e.read()
                error_body = error_content.decode('utf-8', errors='replace')
            except:
                pass
            
            reason = _get_reason_phrase(e.code)
            
            return {
                'success': False,  # LWP considers HTTP errors as failed requests
                'status_code': e.code,
                'reason': reason,
                'status_line': f"{e.code} {reason}",
                'content': error_body,
                'body': error_body,
                'headers': dict(e.headers) if e.headers else {},
                'url': url,
                'elapsed': time.time() - start_time,
                'error': f'HTTP {e.code}: {reason}',
            }
            
        except urllib.error.URLError as e:
            # Handle connection errors
            error_msg = str(e.reason) if hasattr(e, 'reason') else str(e)
            
            return {
                'success': False,
                'status_code': 500,  # Use 500 for connection errors
                'reason': 'Connection Error',
                'status_line': f"500 {error_msg}",
                'content': '',
                'body': '',
                'headers': {},
                'url': url,
                'elapsed': time.time() - start_time,
                'error': f'Connection failed: {error_msg}',
            }
            
        except Exception as e:
            # Handle other errors (timeouts, etc.)
            error_msg = str(e)
            
            return {
                'success': False,
                'status_code': 500,
                'reason': 'Request Error',
                'status_line': f"500 {error_msg}",
                'content': '',
                'body': '',
                'headers': {},
                'url': url,
                'elapsed': time.time() - start_time,
                'error': f'Request failed: {error_msg}',
            }
            
    except Exception as e:
        # Catch-all error handler
        return {
            'success': False,
            'status_code': 500,
            'reason': 'Internal Error',
            'status_line': f"500 Internal Error",
            'content': '',
            'body': '',
            'headers': {},
            'url': url,
            'elapsed': 0,
            'error': f'Internal error: {str(e)}',
        }

def _extract_charset(content_type: str) -> str:
    """Extract charset from Content-Type header"""
    if not content_type:
        return 'utf-8'
    
    # Look for charset parameter
    charset_match = re.search(r'charset=([^;\s]+)', content_type.lower())
    if charset_match:
        return charset_match.group(1).strip('"\'')
    
    return 'utf-8'

def _get_reason_phrase(status_code: int) -> str:
    """Get HTTP reason phrase for status code (matches LWP behavior)"""
    reason_phrases = {
        # 2xx Success
        200: 'OK',
        201: 'Created',
        202: 'Accepted',
        204: 'No Content',
        
        # 3xx Redirection
        300: 'Multiple Choices',
        301: 'Moved Permanently',
        302: 'Found',
        304: 'Not Modified',
        307: 'Temporary Redirect',
        
        # 4xx Client Error
        400: 'Bad Request',
        401: 'Unauthorized',
        403: 'Forbidden',
        404: 'Not Found',
        405: 'Method Not Allowed',
        408: 'Request Timeout',
        409: 'Conflict',
        410: 'Gone',
        
        # 5xx Server Error
        500: 'Internal Server Error',
        501: 'Not Implemented',
        502: 'Bad Gateway',
        503: 'Service Unavailable',
        504: 'Gateway Timeout',
        505: 'HTTP Version Not Supported',
    }
    
    return reason_phrases.get(status_code, 'Unknown')

# Test functions for bridge validation
def test_lwp_compatibility():
    """Test function to validate LWP compatibility"""
    try:
        result = lwp_request('GET', 'http://httpbin.org/get', timeout=10)
        return {
            'test': 'lwp_compatibility',
            'success': result['success'],
            'status_code': result.get('status_code'),
            'has_content': bool(result.get('content')),
        }
    except Exception as e:
        return {
            'test': 'lwp_compatibility',
            'success': False,
            'error': str(e),
        }

def test_mechanize_pattern():
    """Test function to validate WWW::Mechanize pattern"""
    try:
        # Test the simple get/status pattern
        result = lwp_request('GET', 'http://httpbin.org/status/404', timeout=10)
        status_code = result.get('status_code')
        
        return {
            'test': 'mechanize_pattern',
            'success': True,
            'status_code': status_code,
            'mechanize_logic': {
                'is_404': status_code == 404,
                'is_502': status_code == 502,
                'server_status': 'running' if status_code == 404 else 'down'
            }
        }
    except Exception as e:
        return {
            'test': 'mechanize_pattern',
            'success': False,
            'error': str(e),
        }

def test_form_post():
    """Test function to validate form POST handling"""
    try:
        # Test form-encoded POST
        form_data = "param1=value1&param2=value2&param3=value3"
        result = lwp_request(
            'POST', 
            'http://httpbin.org/post',
            headers={'Content-Type': 'application/x-www-form-urlencoded'},
            form_encoded_content=form_data,
            timeout=10
        )
        
        return {
            'test': 'form_post',
            'success': result['success'],
            'status_code': result.get('status_code'),
            'has_content': bool(result.get('content')),
        }
    except Exception as e:
        return {
            'test': 'form_post',
            'success': False,
            'error': str(e),
        }

def ping():
    """Basic connectivity test"""
    return {
        'message': 'HTTP backend is ready',
        'supported_methods': [
            'lwp_request', 
            'test_lwp_compatibility', 
            'test_mechanize_pattern',
            'test_form_post'
        ],
        'version': '1.0.0',
        'features': [
            'LWP::UserAgent compatibility',
            'WWW::Mechanize simple patterns',
            'HTTP::Request support',
            'SSL verification control',
            'Form-encoded POST handling'
        ]
    }