#!/usr/bin/env python3
"""
cpan_daemon.py - CPAN Bridge Daemon

Long-running Python daemon that maintains persistent connections and state
for CPAN module replacements, eliminating process startup overhead.

Features:
- Unix domain socket server for Perl communication
- Persistent state management for all helper modules
- Health monitoring and automatic cleanup
- Graceful shutdown and error handling
- Thread-safe operations for concurrent requests
"""

import os
import sys
import json
import socket
import threading
import signal
import time
import traceback
import importlib
import logging
from typing import Dict, Any, Optional
from pathlib import Path

# Version and configuration
__version__ = "1.0.0"
DAEMON_VERSION = "1.0.0"
MIN_CLIENT_VERSION = "1.0.0"

# Configuration from environment
SOCKET_PATH = os.environ.get('CPAN_BRIDGE_SOCKET', '/tmp/cpan_bridge.sock')
DEBUG_LEVEL = int(os.environ.get('CPAN_BRIDGE_DEBUG', '0'))
MAX_CONNECTIONS = int(os.environ.get('CPAN_BRIDGE_MAX_CONNECTIONS', '100'))
MAX_REQUEST_SIZE = int(os.environ.get('CPAN_BRIDGE_MAX_REQUEST_SIZE', '10485760'))  # 10MB
CONNECTION_TIMEOUT = int(os.environ.get('CPAN_BRIDGE_TIMEOUT', '1800'))  # 30 minutes
CLEANUP_INTERVAL = int(os.environ.get('CPAN_BRIDGE_CLEANUP_INTERVAL', '300'))  # 5 minutes

# Set up logging
logging.basicConfig(
    level=logging.DEBUG if DEBUG_LEVEL > 0 else logging.INFO,
    format='%(asctime)s [%(levelname)s] %(name)s: %(message)s',
    handlers=[
        logging.StreamHandler(sys.stderr),
        logging.FileHandler('/tmp/cpan_daemon.log', mode='a')
    ]
)
logger = logging.getLogger('CPANDaemon')


class CPANBridgeDaemon:
    """Main daemon class for CPAN Bridge operations"""

    def __init__(self):
        """Initialize the daemon"""
        self.running = True
        self.server_socket = None
        self.helper_modules = {}
        self.active_connections = []
        self.stats = {
            'requests_processed': 0,
            'requests_failed': 0,
            'start_time': time.time(),
            'last_cleanup': time.time()
        }

        # Thread management
        self.threads = []
        self.cleanup_thread = None
        self.health_thread = None

        # Setup signal handlers
        signal.signal(signal.SIGTERM, self._signal_handler)
        signal.signal(signal.SIGINT, self._signal_handler)

        logger.info(f"CPAN Bridge Daemon v{__version__} initializing...")

    def _signal_handler(self, signum, frame):
        """Handle shutdown signals gracefully"""
        logger.info(f"Received signal {signum}, initiating graceful shutdown...")
        self.running = False

    def _setup_python_path(self):
        """Set up Python path to find helper modules"""
        script_dir = Path(__file__).parent
        helpers_dir = script_dir / "helpers"

        if helpers_dir.exists():
            sys.path.insert(0, str(helpers_dir))
            logger.debug(f"Added to Python path: {helpers_dir}")

        sys.path.insert(0, str(script_dir))
        logger.debug(f"Added to Python path: {script_dir}")

    def _load_helper_modules(self) -> Dict[str, Any]:
        """Dynamically load all available helper modules"""
        modules = {}

        # List of helper modules to try loading
        helper_modules = [
            'database',         # Database operations (Oracle, Informix, etc.)
            'xml_helper',      # XML parsing and manipulation
            'xpath',           # XPath processing with lxml
            'http',            # HTTP requests and web operations
            'datetime_helper', # DateTime operations
            'crypto',          # Cryptography operations
            'email_helper',    # Email sending
            'logging_helper',  # Logging operations
            'excel',           # Excel file operations
            'sftp',            # SFTP operations
            'test'             # For testing the bridge
        ]

        for module_name in helper_modules:
            try:
                # Try importing from helpers subdirectory first
                try:
                    module = importlib.import_module(f'helpers.{module_name}')
                    logger.debug(f"Loaded helper module: helpers.{module_name}")
                except ImportError:
                    # Fall back to direct import
                    module = importlib.import_module(module_name)
                    logger.debug(f"Loaded helper module: {module_name}")

                modules[module_name] = module

            except ImportError as e:
                logger.warning(f"Could not load helper module {module_name}: {e}")
                # Continue - not all modules may be available in every environment

        logger.info(f"Successfully loaded {len(modules)} helper modules: {list(modules.keys())}")
        return modules

    def _validate_request(self, request: Dict[str, Any]) -> bool:
        """Validate incoming request structure and security"""
        required_fields = ['module', 'function']

        for field in required_fields:
            if field not in request:
                raise ValueError(f"Missing required field: {field}")

        # Basic security check - prevent dangerous function names
        dangerous_patterns = ['__', 'eval', 'import', 'subprocess']
        dangerous_exact = ['exec', 'open', 'file', 'system']
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

    def _route_request(self, request: Dict[str, Any]) -> Dict[str, Any]:
        """Route request to appropriate helper module"""
        module_name = request.get('module')
        function_name = request.get('function')
        params = request.get('params', {})

        logger.debug(f"Routing {module_name}.{function_name} with params: {params}")

        # Handle special built-in requests
        if module_name == 'test':
            return self._handle_test_request(function_name, params)

        if module_name == 'system':
            return self._handle_system_request(function_name, params)

        # Check if module is available
        if module_name not in self.helper_modules:
            available_modules = list(self.helper_modules.keys())
            raise ModuleNotFoundError(
                f"Module '{module_name}' not available. "
                f"Available modules: {available_modules}"
            )

        module = self.helper_modules[module_name]

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

        logger.debug(f"Function {module_name}.{function_name} completed successfully")

        return {
            'success': True,
            'result': result,
            'module': module_name,
            'function': function_name,
            'execution_info': {
                'daemon_version': __version__,
                'python_version': sys.version,
                'timestamp': str(time.time())
            }
        }

    def _handle_test_request(self, function_name: str, params: Dict[str, Any]) -> Dict[str, Any]:
        """Handle special test requests"""
        if function_name == 'ping':
            return {
                'success': True,
                'result': {
                    'message': 'pong',
                    'daemon_version': __version__,
                    'python_version': sys.version,
                    'platform': sys.platform,
                    'uptime': time.time() - self.stats['start_time'],
                    'stats': self.stats.copy(),
                    'input': params
                }
            }

        elif function_name == 'health':
            return {
                'success': True,
                'result': {
                    'status': 'healthy',
                    'daemon_version': __version__,
                    'uptime': time.time() - self.stats['start_time'],
                    'active_connections': len(self.active_connections),
                    'loaded_modules': list(self.helper_modules.keys()),
                    'stats': self.stats.copy()
                }
            }

        elif function_name == 'stats':
            return {
                'success': True,
                'result': self.stats.copy()
            }

        else:
            raise ValueError(f"Unknown test function: {function_name}")

    def _handle_system_request(self, function_name: str, params: Dict[str, Any]) -> Dict[str, Any]:
        """Handle system-level requests"""
        if function_name == 'info':
            return {
                'success': True,
                'result': {
                    'daemon_version': __version__,
                    'python_version': sys.version,
                    'python_executable': sys.executable,
                    'platform': sys.platform,
                    'working_directory': os.getcwd(),
                    'socket_path': SOCKET_PATH,
                    'uptime': time.time() - self.stats['start_time'],
                    'configuration': {
                        'max_connections': MAX_CONNECTIONS,
                        'max_request_size': MAX_REQUEST_SIZE,
                        'connection_timeout': CONNECTION_TIMEOUT,
                        'cleanup_interval': CLEANUP_INTERVAL
                    }
                }
            }

        elif function_name == 'shutdown':
            logger.info("Shutdown requested via system call")
            self.running = False
            return {
                'success': True,
                'result': {'message': 'Shutdown initiated'}
            }

        else:
            raise ValueError(f"Unknown system function: {function_name}")

    def _handle_client(self, client_socket, client_address):
        """Handle individual client request"""
        try:
            logger.debug(f"Handling client connection from {client_address}")

            # Read request with size limit
            data = b''
            while len(data) < MAX_REQUEST_SIZE:
                chunk = client_socket.recv(4096)
                if not chunk:
                    break
                data += chunk

                # Try to parse JSON to see if we have complete message
                try:
                    json.loads(data.decode('utf-8'))
                    break  # Complete JSON received
                except json.JSONDecodeError:
                    continue  # Need more data

            if len(data) >= MAX_REQUEST_SIZE:
                raise ValueError(f"Request too large: {len(data)} bytes (max: {MAX_REQUEST_SIZE})")

            if not data:
                raise ValueError("Empty request received")

            # Parse JSON request
            request_str = data.decode('utf-8')
            request = json.loads(request_str)

            logger.debug(f"Received request: {request.get('module', 'unknown')}.{request.get('function', 'unknown')}")

            # Validate and route request
            self._validate_request(request)
            response = self._route_request(request)

            # Update statistics
            self.stats['requests_processed'] += 1

        except Exception as e:
            logger.error(f"Error handling client request: {e}")
            if DEBUG_LEVEL >= 1:
                logger.error(f"Traceback: {traceback.format_exc()}")

            # Format error response
            response = {
                'success': False,
                'error': str(e),
                'error_type': type(e).__name__,
                'daemon_info': {
                    'version': __version__,
                    'python_version': sys.version
                }
            }

            if DEBUG_LEVEL >= 1:
                response['traceback'] = traceback.format_exc()

            # Update error statistics
            self.stats['requests_failed'] += 1

        try:
            # Send response
            response_json = json.dumps(response, default=str, ensure_ascii=False, separators=(',', ':'))
            client_socket.send(response_json.encode('utf-8'))

        except Exception as e:
            logger.error(f"Error sending response: {e}")

        finally:
            try:
                client_socket.close()
            except:
                pass

    def _cleanup_thread_func(self):
        """Background thread for periodic cleanup"""
        logger.info("Cleanup thread started")

        while self.running:
            try:
                time.sleep(CLEANUP_INTERVAL)
                if not self.running:
                    break

                logger.debug("Running periodic cleanup...")

                # Clean up any stale resources in helper modules
                for module_name, module in self.helper_modules.items():
                    if hasattr(module, 'cleanup_stale_resources'):
                        try:
                            module.cleanup_stale_resources()
                            logger.debug(f"Cleaned up {module_name} resources")
                        except Exception as e:
                            logger.warning(f"Error cleaning up {module_name}: {e}")

                # Update cleanup time
                self.stats['last_cleanup'] = time.time()

            except Exception as e:
                logger.error(f"Error in cleanup thread: {e}")

        logger.info("Cleanup thread stopped")

    def _health_thread_func(self):
        """Background thread for health monitoring"""
        logger.info("Health monitoring thread started")

        while self.running:
            try:
                time.sleep(60)  # Check every minute
                if not self.running:
                    break

                # Log basic health stats
                uptime = time.time() - self.stats['start_time']
                logger.info(f"Health check - Uptime: {uptime:.0f}s, "
                           f"Requests: {self.stats['requests_processed']}, "
                           f"Errors: {self.stats['requests_failed']}, "
                           f"Active connections: {len(self.active_connections)}")

            except Exception as e:
                logger.error(f"Error in health thread: {e}")

        logger.info("Health monitoring thread stopped")

    def _create_socket(self):
        """Create and configure Unix domain socket"""
        # Remove existing socket file
        if os.path.exists(SOCKET_PATH):
            os.unlink(SOCKET_PATH)

        # Create socket
        self.server_socket = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.server_socket.bind(SOCKET_PATH)

        # Set restrictive permissions (owner only)
        os.chmod(SOCKET_PATH, 0o600)

        # Start listening
        self.server_socket.listen(MAX_CONNECTIONS)

        logger.info(f"Unix domain socket created at {SOCKET_PATH}")

    def start_server(self):
        """Start the daemon server"""
        try:
            # Setup environment
            self._setup_python_path()

            # Load helper modules
            logger.info("Loading helper modules...")
            self.helper_modules = self._load_helper_modules()

            # Create socket
            logger.info("Creating Unix domain socket...")
            self._create_socket()

            # Start background threads
            logger.info("Starting background threads...")
            self.cleanup_thread = threading.Thread(target=self._cleanup_thread_func, daemon=True)
            self.health_thread = threading.Thread(target=self._health_thread_func, daemon=True)

            self.cleanup_thread.start()
            self.health_thread.start()

            logger.info(f"CPAN Bridge Daemon v{__version__} started successfully")
            logger.info(f"Listening on {SOCKET_PATH}")
            logger.info(f"Loaded modules: {list(self.helper_modules.keys())}")

            # Main server loop
            while self.running:
                try:
                    # Accept connections with timeout
                    self.server_socket.settimeout(1.0)
                    client_socket, client_address = self.server_socket.accept()

                    # Handle client in separate thread
                    client_thread = threading.Thread(
                        target=self._handle_client,
                        args=(client_socket, client_address),
                        daemon=True
                    )
                    client_thread.start()
                    self.threads.append(client_thread)

                    # Clean up finished threads
                    self.threads = [t for t in self.threads if t.is_alive()]

                except socket.timeout:
                    continue  # Check running flag and continue
                except Exception as e:
                    if self.running:  # Only log if not shutting down
                        logger.error(f"Error accepting connections: {e}")

        except Exception as e:
            logger.error(f"Fatal error starting daemon: {e}")
            logger.error(f"Traceback: {traceback.format_exc()}")
            return 1

        finally:
            self._shutdown()

        return 0

    def _shutdown(self):
        """Graceful shutdown of the daemon"""
        logger.info("Shutting down daemon...")

        self.running = False

        # Close server socket
        if self.server_socket:
            try:
                self.server_socket.close()
            except:
                pass

        # Wait for threads to finish
        logger.info("Waiting for threads to finish...")
        for thread in self.threads:
            if thread.is_alive():
                thread.join(timeout=5.0)

        # Cleanup socket file
        try:
            if os.path.exists(SOCKET_PATH):
                os.unlink(SOCKET_PATH)
                logger.info(f"Removed socket file: {SOCKET_PATH}")
        except:
            pass

        # Cleanup helper modules
        for module_name, module in self.helper_modules.items():
            if hasattr(module, 'shutdown'):
                try:
                    module.shutdown()
                    logger.debug(f"Shutdown {module_name} module")
                except Exception as e:
                    logger.warning(f"Error shutting down {module_name}: {e}")

        logger.info("Daemon shutdown complete")


def main():
    """Main entry point"""
    if len(sys.argv) > 1 and sys.argv[1] in ['--help', '-h']:
        print(f"""
CPAN Bridge Daemon v{__version__}

Usage: {sys.argv[0]} [options]

Options:
  -h, --help     Show this help message
  --version      Show version information

Environment Variables:
  CPAN_BRIDGE_SOCKET      Unix socket path (default: /tmp/cpan_bridge.sock)
  CPAN_BRIDGE_DEBUG       Debug level 0-2 (default: 0)
  CPAN_BRIDGE_MAX_CONNECTIONS  Max concurrent connections (default: 100)
  CPAN_BRIDGE_MAX_REQUEST_SIZE Max request size in bytes (default: 10MB)
  CPAN_BRIDGE_TIMEOUT     Connection timeout in seconds (default: 1800)
  CPAN_BRIDGE_CLEANUP_INTERVAL Cleanup interval in seconds (default: 300)
""")
        return 0

    if len(sys.argv) > 1 and sys.argv[1] == '--version':
        print(f"CPAN Bridge Daemon v{__version__}")
        return 0

    # Start daemon
    daemon = CPANBridgeDaemon()
    return daemon.start_server()


if __name__ == "__main__":
    sys.exit(main())