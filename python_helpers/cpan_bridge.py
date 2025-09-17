#!/usr/bin/env python3
"""
cpan_bridge.py - Python bridge for CPAN module replacements

This script receives JSON requests from Perl via stdin and routes them
to appropriate Python helper modules, returning JSON responses.

Fixed version with improved error handling and Windows compatibility.
"""

import json
import sys
import traceback
import importlib
import os
from pathlib import Path
from datetime import datetime  # FIX: Proper datetime import
from typing import Dict, Any, Optional

# Version info
__version__ = "1.0.1"

# Global configuration
DEBUG = int(os.environ.get('CPAN_BRIDGE_DEBUG', '0'))
MAX_REQUEST_SIZE = int(os.environ.get('CPAN_BRIDGE_MAX_SIZE', '10000000'))  # 10MB

def debug_log(message: str, level: int = 1) -> None:
    """Log debug messages if debug level is sufficient"""
    if DEBUG >= level:
        timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        print(f"[{timestamp}] PYTHON DEBUG: {message}", file=sys.stderr)
        sys.stderr.flush()

def setup_python_path() -> None:
    """Set up Python path to find helper modules"""
    # Add the helpers directory to Python path
    script_dir = Path(__file__).parent
    helpers_dir = script_dir / "helpers"
    
    if helpers_dir.exists():
        sys.path.insert(0, str(helpers_dir))
        debug_log(f"Added to Python path: {helpers_dir}")
    
    # Also add the script directory itself
    sys.path.insert(0, str(script_dir))
    debug_log(f"Added to Python path: {script_dir}")

def load_helper_modules() -> Dict[str, Any]:
    """Dynamically load all available helper modules"""
    modules = {}
    
    # List of helper modules to try loading
    helper_modules = [
        'database',     # Database operations (Oracle, Informix, etc.)
        'xml',          # XML parsing and manipulation
        'http',         # HTTP requests and web operations
        'dates',        # Date parsing and manipulation
        'datetime_helper', # DateTime operations (renamed from datetime to avoid conflicts)
        'crypto',       # Cryptography operations
        'email_helper', # Email sending (renamed from email to avoid conflicts)
        'logging_helper', # Logging operations
        'excel',        # Excel file operations
        'sftp',         # SFTP operations
        'test'          # For testing the bridge
    ]
    
    for module_name in helper_modules:
        try:
            # Try importing from helpers subdirectory first
            try:
                module = importlib.import_module(f'helpers.{module_name}')
                debug_log(f"Loaded helper module: helpers.{module_name}")
            except ImportError:
                # Fall back to direct import
                module = importlib.import_module(module_name)
                debug_log(f"Loaded helper module: {module_name}")
            
            modules[module_name] = module
            
        except ImportError as e:
            debug_log(f"Could not load helper module {module_name}: {e}")
            # Continue - not all modules may be available in every environment
    
    debug_log(f"Successfully loaded {len(modules)} helper modules: {list(modules.keys())}")
    return modules

def validate_request(request: Dict[str, Any]) -> bool:
    """Validate incoming request structure and security"""
    required_fields = ['module', 'function']
    
    for field in required_fields:
        if field not in request:
            raise ValueError(f"Missing required field: {field}")
    
    # Basic security check - prevent dangerous function names
    dangerous_patterns = ['__', 'eval', 'import', 'subprocess']
    dangerous_exact = ['exec', 'open', 'file', 'system']  # Exact matches only
    function_name = request['function'].lower()
    module_name = request['module'].lower()

    # Check substring patterns
    for pattern in dangerous_patterns:
        if pattern in function_name or pattern in module_name:
            raise ValueError(f"Potentially dangerous function/module name: {request['module']}.{request['function']}")

    # Check exact matches
    for pattern in dangerous_exact:
        if function_name == pattern or module_name == pattern:
            raise ValueError(f"Potentially dangerous function/module name: {request['module']}.{request['function']}")
    
    # Validate module name format
    if not request['module'].replace('_', '').isalnum():
        raise ValueError(f"Invalid module name format: {request['module']}")
    
    # Validate function name format
    if not request['function'].replace('_', '').isalnum():
        raise ValueError(f"Invalid function name format: {request['function']}")
    
    return True

def call_helper_function(modules: Dict[str, Any], request: Dict[str, Any]) -> Dict[str, Any]:
    """Call the requested helper function and return result"""
    module_name = request['module']
    function_name = request['function']
    params = request.get('params', {})
    
    debug_log(f"Calling {module_name}.{function_name} with params: {params}", level=1)
    
    # Check if module is available
    if module_name not in modules:
        available_modules = list(modules.keys())
        raise ModuleNotFoundError(
            f"Module '{module_name}' not available. "
            f"Available modules: {available_modules}"
        )
    
    module = modules[module_name]
    
    # Check if function exists in module
    if not hasattr(module, function_name):
        available_functions = [name for name in dir(module) if not name.startswith('_')]
        raise AttributeError(
            f"Function '{function_name}' not found in module '{module_name}'. "
            f"Available functions: {available_functions}"
        )
    
    func = getattr(module, function_name)
    
    # Validate that it's actually callable
    if not callable(func):
        raise TypeError(f"{module_name}.{function_name} is not callable")
    
    # Call the function with parameters
    try:
        if isinstance(params, dict):
            # Call with keyword arguments
            result = func(**params)
        elif isinstance(params, list):
            # Call with positional arguments
            result = func(*params)
        else:
            # Call with single argument
            result = func(params)
    except Exception as e:
        # Re-raise with more context
        raise RuntimeError(f"Error in {module_name}.{function_name}: {str(e)}") from e
    
    debug_log(f"Function {module_name}.{function_name} completed successfully, returning: {result}", level=1)
    
    return {
        'success': True,
        'result': result,
        'module': module_name,
        'function': function_name,
        'execution_info': {
            'python_version': sys.version,
            'timestamp': str(datetime.now())  # FIX: Use proper datetime reference
        }
    }

def handle_special_requests(request: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    """Handle special built-in requests that don't require helper modules"""
    module_name = request['module']
    function_name = request['function']
    
    if module_name == 'test':
        if function_name == 'ping':
            # Basic connectivity test
            return {
                'success': True,
                'result': {
                    'message': 'pong',
                    'version': __version__,
                    'python_version': sys.version,
                    'platform': sys.platform,
                    'working_directory': os.getcwd(),
                    'input': request.get('params', {})
                }
            }
        
        elif function_name == 'check_module':
            # Check if a Python module is available
            module_to_check = request.get('params', {}).get('module', '')
            if not module_to_check:
                return {
                    'success': False,
                    'error': 'Module name required for check_module'
                }
            
            try:
                importlib.import_module(module_to_check)
                return {
                    'success': True,
                    'result': True
                }
            except ImportError:
                return {
                    'success': True,
                    'result': False
                }
        
        elif function_name == 'error':
            # Test error handling
            raise RuntimeError("Test error for error handling validation")
        
        elif function_name == 'echo':
            # Echo back the input for testing
            return {
                'success': True,
                'result': request.get('params', {})
            }
    
    elif module_name == 'system':
        if function_name == 'info':
            # System information
            return {
                'success': True,
                'result': {
                    'python_version': sys.version,
                    'python_executable': sys.executable,
                    'platform': sys.platform,
                    'version': __version__,
                    'working_directory': os.getcwd(),
                    'python_path': sys.path[:5],  # First 5 entries only
                    'environment_vars': {
                        k: v for k, v in os.environ.items() 
                        if k.startswith(('CPAN_', 'PYTHON_'))
                    }
                }
            }
        
        elif function_name == 'environment':
            # Return safe environment variables
            safe_env_vars = {}
            safe_prefixes = ['CPAN_', 'PYTHON_', 'PATH', 'HOME', 'USER', 'HOSTNAME']
            
            for key, value in os.environ.items():
                if any(key.startswith(prefix) for prefix in safe_prefixes):
                    safe_env_vars[key] = value
            
            return {
                'success': True,
                'result': safe_env_vars
            }
        
        elif function_name == 'health':
            # Health check
            return {
                'success': True,
                'result': {
                    'status': 'healthy',
                    'version': __version__,
                    'uptime': 'session-based',
                    'memory_usage': 'not tracked'
                }
            }
    
    return None  # Not a special request

def format_error_response(error: Exception, request: Dict[str, Any]) -> Dict[str, Any]:
    """Format error into standard response structure"""
    error_type = type(error).__name__
    error_message = str(error)
    
    # Include traceback in debug mode
    error_traceback = None
    if DEBUG >= 1:
        error_traceback = traceback.format_exc()
        debug_log(f"Error traceback: {error_traceback}")
    
    response = {
        'success': False,
        'error': error_message,
        'error_type': error_type,
        'module': request.get('module', 'unknown'),
        'function': request.get('function', 'unknown'),
        'python_info': {
            'version': sys.version,
            'platform': sys.platform
        }
    }
    
    if error_traceback:
        response['traceback'] = error_traceback
    
    debug_log(f"Error in {request.get('module', 'unknown')}.{request.get('function', 'unknown')}: {error_message}")
    
    return response

def read_request() -> Dict[str, Any]:
    """Read and parse JSON request from stdin"""
    try:
        # Read all input from stdin
        debug_log("Reading input from stdin...")
        input_data = sys.stdin.read()
        
        if not input_data.strip():
            raise ValueError("Empty input received")
        
        # Check size limit
        if len(input_data) > MAX_REQUEST_SIZE:
            raise ValueError(f"Request too large: {len(input_data)} bytes (max: {MAX_REQUEST_SIZE})")
        
        debug_log(f"Received request of {len(input_data)} bytes", level=2)
        debug_log(f"Raw input: {input_data[:200]}{'...' if len(input_data) > 200 else ''}", level=3)
        
        # Parse JSON
        request = json.loads(input_data)
        
        debug_log(f"Parsed request: module={request.get('module')}, function={request.get('function')}")
        
        return request
        
    except json.JSONDecodeError as e:
        raise ValueError(f"Invalid JSON in request: {e}")
    except Exception as e:
        raise ValueError(f"Failed to read request: {e}")

def write_response(response: Dict[str, Any]) -> None:
    """Write JSON response to stdout"""
    try:
        # Ensure response is JSON serializable
        json_response = json.dumps(response, default=str, ensure_ascii=False, separators=(',', ':'))
        
        # Write to stdout and flush immediately
        print(json_response)
        sys.stdout.flush()
        
        debug_log(f"Sent response: success={response.get('success')}", level=2)
        debug_log(f"Response length: {len(json_response)} bytes", level=3)
        
    except Exception as e:
        # Fallback error response if JSON serialization fails
        fallback_response = {
            'success': False,
            'error': f"Failed to serialize response: {e}",
            'error_type': 'SerializationError',
            'python_info': {
                'version': sys.version,
                'platform': sys.platform
            }
        }
        try:
            fallback_json = json.dumps(fallback_response)
            print(fallback_json)
            sys.stdout.flush()
        except:
            # Last resort - plain text error
            print('{"success": false, "error": "Critical serialization failure"}')
            sys.stdout.flush()

def validate_environment() -> None:
    """Validate the Python environment and log important info"""
    debug_log(f"Python version: {sys.version}")
    debug_log(f"Platform: {sys.platform}")
    debug_log(f"Working directory: {os.getcwd()}")
    debug_log(f"Script location: {__file__}")
    
    # Check for important modules
    critical_modules = ['json', 'sys', 'os']
    for module in critical_modules:
        try:
            __import__(module)
            debug_log(f"✓ {module} available")
        except ImportError:
            debug_log(f"✗ {module} NOT available")

def main() -> int:
    """Main entry point for the bridge script"""
    try:
        debug_log(f"Starting CPAN bridge v{__version__}")
        
        # Validate environment
        validate_environment()
        
        # Set up Python path for helper modules
        setup_python_path()
        
        # Read and validate request
        debug_log("Reading request from stdin...")
        request = read_request()
        
        debug_log("Validating request...")
        validate_request(request)
        
        debug_log(f"Processing request: {request.get('module')}.{request.get('function')}")
        
        # Check for special built-in requests first
        response = handle_special_requests(request)
        
        if response is None:
            # Load helper modules and call the requested function
            debug_log("Loading helper modules...")
            modules = load_helper_modules()
            
            debug_log("Calling helper function...")
            response = call_helper_function(modules, request)
        
        # Send successful response
        debug_log("Sending response...")
        write_response(response)
        
        debug_log("Request processed successfully")
        return 0
        
    except Exception as e:
        # Handle any errors
        debug_log(f"Error occurred: {e}")
        
        error_request = {}
        try:
            # Try to get request info for error context
            if 'request' in locals():
                error_request = request
        except:
            pass
        
        error_response = format_error_response(e, error_request)
        write_response(error_response)
        
        debug_log(f"Error response sent")
        return 1

if __name__ == "__main__":
    # Set up error handling for unhandled exceptions
    def handle_exception(exc_type, exc_value, exc_traceback):
        if issubclass(exc_type, KeyboardInterrupt):
            sys.__excepthook__(exc_type, exc_value, exc_traceback)
            return
        
        error_response = {
            'success': False,
            'error': f"Unhandled exception: {exc_value}",
            'error_type': exc_type.__name__,
            'module': 'unknown',
            'function': 'unknown'
        }
        
        if DEBUG >= 1:
            error_response['traceback'] = ''.join(traceback.format_exception(exc_type, exc_value, exc_traceback))
        
        try:
            write_response(error_response)
        except:
            print('{"success": false, "error": "Critical system failure"}')
            sys.stdout.flush()
    
    sys.excepthook = handle_exception
    
    # Run main function and exit with appropriate code
    exit_code = main()
    debug_log(f"Bridge script exiting with code {exit_code}")
    sys.exit(exit_code)