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
import psutil
import re
import uuid
import hashlib
import tempfile

# Import resource module with Windows compatibility
try:
    import resource
    HAS_RESOURCE = True
except ImportError:
    # Windows doesn't have resource module
    HAS_RESOURCE = False
    resource = None
from typing import Dict, Any, Optional, List, Union
from pathlib import Path
from collections import defaultdict
from dataclasses import dataclass, field
from datetime import datetime, timedelta

# Version and configuration
__version__ = "1.0.0"
DAEMON_VERSION = "1.0.0"
MIN_CLIENT_VERSION = "1.0.0"

# Configuration from environment
# Platform-specific socket path
if os.name == 'nt':  # Windows
    DEFAULT_SOCKET = r'\\.\pipe\cpan_bridge'
else:  # Unix-like systems
    DEFAULT_SOCKET = '/tmp/cpan_bridge.sock'

SOCKET_PATH = os.environ.get('CPAN_BRIDGE_SOCKET', DEFAULT_SOCKET)
DEBUG_LEVEL = int(os.environ.get('CPAN_BRIDGE_DEBUG', '0'))
MAX_CONNECTIONS = int(os.environ.get('CPAN_BRIDGE_MAX_CONNECTIONS', '100'))
MAX_REQUEST_SIZE = int(os.environ.get('CPAN_BRIDGE_MAX_REQUEST_SIZE', '10485760'))  # 10MB
CONNECTION_TIMEOUT = int(os.environ.get('CPAN_BRIDGE_TIMEOUT', '1800'))  # 30 minutes
CLEANUP_INTERVAL = int(os.environ.get('CPAN_BRIDGE_CLEANUP_INTERVAL', '300'))  # 5 minutes

# Resource management configuration
MAX_MEMORY_MB = int(os.environ.get('CPAN_BRIDGE_MAX_MEMORY_MB', '1024'))  # 1GB
MAX_CPU_PERCENT = float(os.environ.get('CPAN_BRIDGE_MAX_CPU_PERCENT', '200.0'))  # 200% (allows for multi-core burst)
MAX_REQUESTS_PER_MINUTE = int(os.environ.get('CPAN_BRIDGE_MAX_REQUESTS_PER_MINUTE', '1000'))
MAX_CONCURRENT_REQUESTS = int(os.environ.get('CPAN_BRIDGE_MAX_CONCURRENT_REQUESTS', '50'))
STALE_CONNECTION_TIMEOUT = int(os.environ.get('CPAN_BRIDGE_STALE_TIMEOUT', '300'))  # 5 minutes
RESOURCE_CHECK_INTERVAL = int(os.environ.get('CPAN_BRIDGE_RESOURCE_CHECK_INTERVAL', '60'))  # 1 minute

# Enhanced validation configuration
MAX_STRING_LENGTH = int(os.environ.get('CPAN_BRIDGE_MAX_STRING_LENGTH', '10000'))  # 10KB strings
MAX_ARRAY_LENGTH = int(os.environ.get('CPAN_BRIDGE_MAX_ARRAY_LENGTH', '1000'))  # 1000 items
MAX_OBJECT_DEPTH = int(os.environ.get('CPAN_BRIDGE_MAX_OBJECT_DEPTH', '10'))  # 10 levels deep
MAX_PARAM_COUNT = int(os.environ.get('CPAN_BRIDGE_MAX_PARAM_COUNT', '100'))  # 100 parameters
ENABLE_STRICT_VALIDATION = os.environ.get('CPAN_BRIDGE_STRICT_VALIDATION', '1') == '1'

# Cross-platform log file paths
temp_dir = tempfile.gettempdir()
daemon_log_path = os.path.join(temp_dir, 'cpan_daemon.log')
security_log_path = os.path.join(temp_dir, 'cpan_security.log')

# Set up logging
logging.basicConfig(
    level=logging.DEBUG if DEBUG_LEVEL > 0 else logging.INFO,
    format='%(asctime)s [%(levelname)s] %(name)s: %(message)s',
    handlers=[
        logging.StreamHandler(sys.stderr),
        logging.FileHandler(daemon_log_path, mode='a')
    ]
)
logger = logging.getLogger('CPANDaemon')

# Security logging setup
security_logger = logging.getLogger('CPANSecurity')
security_handler = logging.FileHandler(security_log_path, mode='a')
security_formatter = logging.Formatter(
    '%(asctime)s [SECURITY] %(levelname)s: %(message)s'
)
security_handler.setFormatter(security_formatter)
security_logger.addHandler(security_handler)
security_logger.setLevel(logging.INFO)


@dataclass
class ConnectionInfo:
    """Information about an active connection"""
    client_address: str
    start_time: float  # Use timestamp for consistency
    last_activity: float  # Use timestamp for consistency
    requests_count: int = 0
    bytes_sent: int = 0
    bytes_received: int = 0
    thread_id: Optional[int] = None
    status: str = 'active'


@dataclass
class ResourceMetrics:
    """Resource usage metrics"""
    timestamp: datetime = field(default_factory=datetime.now)
    memory_mb: float = 0.0
    cpu_percent: float = 0.0
    active_connections: int = 0
    concurrent_requests: int = 0
    requests_per_minute: int = 0
    total_requests: int = 0
    failed_requests: int = 0


@dataclass
class SecurityEvent:
    """Security event for logging and monitoring"""
    event_id: str = field(default_factory=lambda: str(uuid.uuid4()))
    timestamp: datetime = field(default_factory=datetime.now)
    event_type: str = ''
    severity: str = 'info'  # info, warning, error, critical
    client_info: str = ''
    request_id: str = ''
    module: str = ''
    function: str = ''
    details: Dict[str, Any] = field(default_factory=dict)
    remediation: str = ''


@dataclass
class ValidationResult:
    """Result of request validation"""
    is_valid: bool = True
    errors: List[str] = field(default_factory=list)
    warnings: List[str] = field(default_factory=list)
    sanitized_request: Optional[Dict[str, Any]] = None
    security_events: List[SecurityEvent] = field(default_factory=list)


class RequestValidator:
    """Enhanced request validation with JSON schema and security checks"""

    def __init__(self):
        self.request_schemas = self._define_schemas()
        self.module_whitelist = self._load_module_whitelist()
        self.security_patterns = self._load_security_patterns()

    def _define_schemas(self) -> Dict[str, Dict[str, Any]]:
        """Define JSON schemas for different request types"""
        base_schema = {
            "type": "object",
            "required": ["module", "function"],
            "properties": {
                "module": {
                    "type": "string",
                    "pattern": "^[a-zA-Z][a-zA-Z0-9_]*$",
                    "maxLength": 50
                },
                "function": {
                    "type": "string",
                    "pattern": "^[a-zA-Z][a-zA-Z0-9_]*$",
                    "maxLength": 100
                },
                "params": {
                    "type": ["object", "array", "string", "number", "boolean", "null"]
                },
                "timestamp": {
                    "type": "number"
                },
                "request_id": {
                    "type": "string",
                    "maxLength": 100
                },
                "perl_caller": {
                    "type": "string",
                    "maxLength": 200
                },
                "client_version": {
                    "type": "string",
                    "maxLength": 50
                }
            },
            "additionalProperties": False
        }

        return {
            "default": base_schema,
            "system": {
                **base_schema,
                "properties": {
                    **base_schema["properties"],
                    "module": {
                        "type": "string",
                        "enum": ["system", "test"]
                    }
                }
            }
        }

    def _load_module_whitelist(self) -> Dict[str, List[str]]:
        """Load allowed modules and their functions"""
        return {
            # Core helper modules
            "database": ["connect", "disconnect", "execute_statement", "fetch_row", "fetch_all",
                        "prepare", "finish_statement", "begin_transaction", "commit", "rollback"],
            "xml_helper": ["xml_in", "xml_out", "escape_xml", "unescape_xml"],
            "xpath": ["new", "find", "findnodes", "findvalue", "exists"],
            "http": ["lwp_request", "get", "post", "put", "delete", "head"],
            "datetime_helper": ["format_date", "parse_date", "add_days", "diff_days", "now"],
            "crypto": ["encrypt", "decrypt", "hash", "generate_key", "sign", "verify"],
            "email_helper": ["send_email", "send_html_email", "validate_email"],
            "logging_helper": ["log_message", "log_error", "log_warning", "log_debug"],
            "excel": ["create_workbook", "add_worksheet", "write_cell", "save_workbook"],
            "sftp": ["connect", "put", "get", "delete", "list_files", "disconnect"],
            # Administrative modules
            "test": ["ping", "health", "stats", "echo"],
            "system": ["info", "shutdown", "health", "stats", "performance", "connections",
                      "cleanup", "metrics"]
        }

    def _load_security_patterns(self) -> Dict[str, List[str]]:
        """Load security threat patterns"""
        return {
            "injection_patterns": [
                r"[\x00-\x1f\x7f-\x9f]",  # Control characters
                r"<script[^>]*>",  # Script tags
                r"javascript:",  # JavaScript protocol
                r"on\w+\s*=",  # Event handlers
                r"\$\{.*\}",  # Variable interpolation
                r"\#\{.*\}",  # Ruby interpolation
                r"\.\./",  # Path traversal
                r"\\\\.*\\\\"  # UNC paths
            ],
            "dangerous_functions": [
                "eval", "exec", "compile", "__import__", "open", "file",
                "subprocess", "os", "sys", "globals", "locals", "vars",
                "input", "raw_input", "execfile", "reload"
            ],
            "suspicious_strings": [
                "DROP TABLE", "DELETE FROM", "UPDATE SET", "INSERT INTO",
                "UNION SELECT", "OR 1=1", "AND 1=1", "' OR '", '" OR "',
                "--", "/*", "*/", "xp_", "sp_", "ALTER TABLE"
            ]
        }

    def validate_request(self, request: Dict[str, Any], client_info: str = "") -> ValidationResult:
        """Comprehensive request validation with security checks"""
        result = ValidationResult()
        request_id = request.get('request_id', str(uuid.uuid4()))

        try:
            # Step 1: Basic structure validation
            self._validate_structure(request, result)

            # Step 2: Schema validation
            if result.is_valid:
                self._validate_schema(request, result)

            # Step 3: Security validation
            if result.is_valid:
                self._validate_security(request, result, client_info, request_id)

            # Step 4: Parameter sanitization and validation
            if result.is_valid:
                result.sanitized_request = self._sanitize_request(request, result)

            # Step 5: Module/function whitelist validation
            if result.is_valid:
                self._validate_whitelist(request, result, client_info, request_id)

        except Exception as e:
            result.is_valid = False
            result.errors.append(f"Validation error: {str(e)}")
            result.security_events.append(SecurityEvent(
                event_type="validation_exception",
                severity="error",
                client_info=client_info,
                request_id=request_id,
                details={"error": str(e), "request": self._safe_request_repr(request)}
            ))

        return result

    def _validate_structure(self, request: Dict[str, Any], result: ValidationResult) -> None:
        """Validate basic request structure"""
        if not isinstance(request, dict):
            result.is_valid = False
            result.errors.append("Request must be a JSON object")
            return

        required_fields = ['module', 'function']
        for field in required_fields:
            if field not in request:
                result.is_valid = False
                result.errors.append(f"Missing required field: {field}")

        # Check for excessive parameters
        if len(request) > MAX_PARAM_COUNT:
            result.is_valid = False
            result.errors.append(f"Too many parameters: {len(request)} (max: {MAX_PARAM_COUNT})")

    def _validate_schema(self, request: Dict[str, Any], result: ValidationResult) -> None:
        """Validate request against JSON schema"""
        module_name = request.get('module', '')
        schema_key = 'system' if module_name in ['system', 'test'] else 'default'
        schema = self.request_schemas[schema_key]

        # Simple schema validation (would use jsonschema library in production)
        self._validate_against_schema(request, schema, result)

    def _validate_against_schema(self, data: Any, schema: Dict[str, Any], result: ValidationResult, path: str = "") -> None:
        """Simple JSON schema validation implementation"""
        if schema.get("type") == "object":
            if not isinstance(data, dict):
                result.is_valid = False
                result.errors.append(f"Expected object at {path or 'root'}")
                return

            # Check required properties
            for prop in schema.get("required", []):
                if prop not in data:
                    result.is_valid = False
                    result.errors.append(f"Missing required property: {prop}")

            # Validate properties
            for prop, value in data.items():
                if "properties" in schema and prop in schema["properties"]:
                    self._validate_against_schema(value, schema["properties"][prop], result, f"{path}.{prop}")
                elif not schema.get("additionalProperties", True):
                    result.is_valid = False
                    result.errors.append(f"Additional property not allowed: {prop}")

        elif schema.get("type") == "string":
            if not isinstance(data, str):
                result.is_valid = False
                result.errors.append(f"Expected string at {path}")
                return

            if "maxLength" in schema and len(data) > schema["maxLength"]:
                result.is_valid = False
                result.errors.append(f"String too long at {path}: {len(data)} > {schema['maxLength']}")

            if "pattern" in schema and not re.match(schema["pattern"], data):
                result.is_valid = False
                result.errors.append(f"String pattern mismatch at {path}")

            if "enum" in schema and data not in schema["enum"]:
                result.is_valid = False
                result.errors.append(f"Value not in allowed enum at {path}: {data}")

    def _validate_security(self, request: Dict[str, Any], result: ValidationResult,
                          client_info: str, request_id: str) -> None:
        """Comprehensive security validation"""
        module_name = request.get('module', '')
        function_name = request.get('function', '')

        # Check for injection patterns
        request_str = json.dumps(request)
        for pattern in self.security_patterns["injection_patterns"]:
            if re.search(pattern, request_str, re.IGNORECASE):
                result.is_valid = False
                result.errors.append("Potential injection attack detected")
                result.security_events.append(SecurityEvent(
                    event_type="injection_attempt",
                    severity="critical",
                    client_info=client_info,
                    request_id=request_id,
                    module=module_name,
                    function=function_name,
                    details={"pattern": pattern, "request": self._safe_request_repr(request)}
                ))
                break

        # Check for dangerous function names (but exempt whitelisted modules)
        # Exempt administrative and legitimate helper modules
        exempt_modules = ['system', 'test', 'file_helper', 'db_helper', 'email_helper',
                         'xml_helper', 'json_helper', 'string_helper', 'date_helper',
                         'datetime_helper', 'http_helper', 'sftp_helper', 'logging_helper',
                         'excel_helper', 'crypto_helper', 'xpath_helper']
        if module_name not in exempt_modules:
            for dangerous in self.security_patterns["dangerous_functions"]:
                if dangerous in function_name.lower() or dangerous in module_name.lower():
                    result.is_valid = False
                    result.errors.append(f"Dangerous function/module name detected: {dangerous}")
                    result.security_events.append(SecurityEvent(
                        event_type="dangerous_function",
                        severity="error",
                        client_info=client_info,
                        request_id=request_id,
                        module=module_name,
                        function=function_name,
                        details={"dangerous_pattern": dangerous}
                    ))

        # Check for SQL injection patterns
        for pattern in self.security_patterns["suspicious_strings"]:
            if pattern.lower() in request_str.lower():
                result.warnings.append(f"Suspicious string pattern detected: {pattern}")
                result.security_events.append(SecurityEvent(
                    event_type="suspicious_content",
                    severity="warning",
                    client_info=client_info,
                    request_id=request_id,
                    module=module_name,
                    function=function_name,
                    details={"pattern": pattern}
                ))

    def _sanitize_request(self, request: Dict[str, Any], result: ValidationResult) -> Dict[str, Any]:
        """Sanitize and normalize request parameters"""
        sanitized = {}

        for key, value in request.items():
            sanitized[key] = self._sanitize_value(value, result, key)

        return sanitized

    def _sanitize_value(self, value: Any, result: ValidationResult, path: str) -> Any:
        """Sanitize individual values"""
        if isinstance(value, str):
            # Length check
            if len(value) > MAX_STRING_LENGTH:
                result.warnings.append(f"String truncated at {path}: {len(value)} > {MAX_STRING_LENGTH}")
                value = value[:MAX_STRING_LENGTH]

            # Remove control characters
            value = re.sub(r'[\x00-\x1f\x7f-\x9f]', '', value)

            return value

        elif isinstance(value, dict):
            return {k: self._sanitize_value(v, result, f"{path}.{k}") for k, v in value.items()}

        elif isinstance(value, list):
            if len(value) > MAX_ARRAY_LENGTH:
                result.warnings.append(f"Array truncated at {path}: {len(value)} > {MAX_ARRAY_LENGTH}")
                value = value[:MAX_ARRAY_LENGTH]

            return [self._sanitize_value(item, result, f"{path}[{i}]") for i, item in enumerate(value)]

        return value

    def _validate_whitelist(self, request: Dict[str, Any], result: ValidationResult,
                           client_info: str, request_id: str) -> None:
        """Validate against module/function whitelist"""
        module_name = request.get('module', '')
        function_name = request.get('function', '')

        if module_name not in self.module_whitelist:
            result.is_valid = False
            result.errors.append(f"Module not allowed: {module_name}")
            result.security_events.append(SecurityEvent(
                event_type="unauthorized_module",
                severity="error",
                client_info=client_info,
                request_id=request_id,
                module=module_name,
                function=function_name,
                details={"attempted_module": module_name}
            ))
            return

        allowed_functions = self.module_whitelist[module_name]
        if function_name not in allowed_functions:
            result.is_valid = False
            result.errors.append(f"Function not allowed: {module_name}.{function_name}")
            result.security_events.append(SecurityEvent(
                event_type="unauthorized_function",
                severity="error",
                client_info=client_info,
                request_id=request_id,
                module=module_name,
                function=function_name,
                details={"attempted_function": function_name, "allowed_functions": allowed_functions}
            ))

    def _safe_request_repr(self, request: Dict[str, Any]) -> Dict[str, Any]:
        """Create safe representation of request for logging"""
        safe_request = {}
        for key, value in request.items():
            if key.lower() in ['password', 'secret', 'token', 'key']:
                safe_request[key] = "[REDACTED]"
            elif isinstance(value, str) and len(value) > 100:
                safe_request[key] = value[:97] + "..."
            else:
                safe_request[key] = value
        return safe_request


class SecurityLogger:
    """Enhanced security logging and monitoring"""

    def __init__(self):
        self.security_events = []
        self.security_metrics = defaultdict(int)
        self.alert_thresholds = {
            "injection_attempt": 5,  # per hour
            "unauthorized_access": 10,  # per hour
            "validation_failure": 50,  # per hour
        }

    def log_security_event(self, event: SecurityEvent) -> None:
        """Log security event with structured format"""
        # Log to security log file
        log_data = {
            "event_id": event.event_id,
            "timestamp": event.timestamp.isoformat(),
            "event_type": event.event_type,
            "severity": event.severity,
            "client_info": event.client_info,
            "request_id": event.request_id,
            "module": event.module,
            "function": event.function,
            "details": event.details
        }

        security_logger.info(json.dumps(log_data))

        # Update metrics
        self.security_metrics[event.event_type] += 1
        self.security_metrics[f"{event.event_type}_{event.severity}"] += 1

        # Store for analysis
        self.security_events.append(event)

        # Clean old events (keep last 1000)
        if len(self.security_events) > 1000:
            self.security_events = self.security_events[-1000:]

        # Check alert thresholds
        self._check_alert_thresholds(event)

    def _check_alert_thresholds(self, event: SecurityEvent) -> None:
        """Check if security event triggers alerts"""
        if event.event_type in self.alert_thresholds:
            threshold = self.alert_thresholds[event.event_type]
            recent_events = [
                e for e in self.security_events
                if e.event_type == event.event_type
                and (datetime.now() - e.timestamp).total_seconds() < 3600  # Last hour
            ]

            if len(recent_events) >= threshold:
                security_logger.critical(
                    f"SECURITY ALERT: {event.event_type} threshold exceeded: "
                    f"{len(recent_events)} events in last hour (threshold: {threshold})"
                )

    def get_security_metrics(self) -> Dict[str, Any]:
        """Get current security metrics"""
        return {
            "total_events": len(self.security_events),
            "events_by_type": dict(self.security_metrics),
            "recent_events": [
                {
                    "event_type": e.event_type,
                    "severity": e.severity,
                    "timestamp": e.timestamp.isoformat(),
                    "client_info": e.client_info
                }
                for e in self.security_events[-10:]  # Last 10 events
            ]
        }


class PerformanceMonitor:
    """Advanced performance monitoring and metrics collection"""

    def __init__(self):
        self.start_time = time.time()
        self.request_latencies = []
        self.error_history = []
        self.performance_metrics = {
            'total_requests': 0,
            'successful_requests': 0,
            'failed_requests': 0,
            'avg_response_time': 0.0,
            'p95_response_time': 0.0,
            'p99_response_time': 0.0,
            'requests_per_second': 0.0,
            'error_rate': 0.0,
            'uptime_seconds': 0.0
        }
        self.module_metrics = defaultdict(lambda: {
            'request_count': 0,
            'total_time': 0.0,
            'avg_time': 0.0,
            'error_count': 0,
            'error_rate': 0.0
        })

    def record_request(self, module: str, function: str, duration: float, success: bool, error: str = None):
        """Record request performance metrics"""
        current_time = time.time()

        # Update global metrics
        self.performance_metrics['total_requests'] += 1
        if success:
            self.performance_metrics['successful_requests'] += 1
        else:
            self.performance_metrics['failed_requests'] += 1
            self.error_history.append({
                'timestamp': current_time,
                'module': module,
                'function': function,
                'error': error,
                'duration': duration
            })

        # Record latency
        self.request_latencies.append({
            'timestamp': current_time,
            'duration': duration,
            'module': module,
            'function': function,
            'success': success
        })

        # Clean old latency data (keep last 1000)
        if len(self.request_latencies) > 1000:
            self.request_latencies = self.request_latencies[-1000:]

        # Clean old error data (keep last 500)
        if len(self.error_history) > 500:
            self.error_history = self.error_history[-500:]

        # Update module-specific metrics
        module_key = f"{module}.{function}"
        module_stats = self.module_metrics[module_key]
        module_stats['request_count'] += 1
        module_stats['total_time'] += duration
        module_stats['avg_time'] = module_stats['total_time'] / module_stats['request_count']

        if not success:
            module_stats['error_count'] += 1
            module_stats['error_rate'] = module_stats['error_count'] / module_stats['request_count']

        # Update computed metrics
        self._update_computed_metrics()

    def _update_computed_metrics(self):
        """Update computed performance metrics"""
        current_time = time.time()

        # Calculate uptime
        self.performance_metrics['uptime_seconds'] = current_time - self.start_time

        if not self.request_latencies:
            return

        # Calculate response time statistics
        recent_latencies = [req['duration'] for req in self.request_latencies[-100:]]  # Last 100 requests
        if recent_latencies:
            self.performance_metrics['avg_response_time'] = sum(recent_latencies) / len(recent_latencies)
            sorted_latencies = sorted(recent_latencies)
            n = len(sorted_latencies)
            self.performance_metrics['p95_response_time'] = sorted_latencies[int(n * 0.95)] if n > 0 else 0
            self.performance_metrics['p99_response_time'] = sorted_latencies[int(n * 0.99)] if n > 0 else 0

        # Calculate requests per second (last minute)
        minute_ago = current_time - 60
        recent_requests = [req for req in self.request_latencies if req['timestamp'] > minute_ago]
        self.performance_metrics['requests_per_second'] = len(recent_requests) / 60.0

        # Calculate error rate (last 100 requests)
        recent_errors = sum(1 for req in self.request_latencies[-100:] if not req['success'])
        recent_total = min(100, len(self.request_latencies))
        self.performance_metrics['error_rate'] = (recent_errors / recent_total) if recent_total > 0 else 0.0

    def get_performance_report(self) -> Dict[str, Any]:
        """Get comprehensive performance report"""
        self._update_computed_metrics()

        # Get top performing modules
        top_modules = sorted(
            [(k, v) for k, v in self.module_metrics.items() if v['request_count'] > 0],
            key=lambda x: x[1]['request_count'],
            reverse=True
        )[:10]

        # Get recent errors
        recent_errors = self.error_history[-10:] if self.error_history else []

        return {
            'performance_metrics': self.performance_metrics.copy(),
            'module_performance': {
                'top_modules': [
                    {
                        'module_function': mod,
                        'requests': stats['request_count'],
                        'avg_time_ms': round(stats['avg_time'] * 1000, 2),
                        'error_rate': round(stats['error_rate'] * 100, 2)
                    }
                    for mod, stats in top_modules
                ],
                'total_modules': len(self.module_metrics)
            },
            'recent_errors': [
                {
                    'timestamp': error['timestamp'],
                    'module_function': f"{error['module']}.{error['function']}",
                    'error': error['error'],
                    'duration_ms': round(error['duration'] * 1000, 2)
                }
                for error in recent_errors
            ],
            'health_indicators': self._get_health_indicators()
        }

    def _get_health_indicators(self) -> Dict[str, Any]:
        """Calculate health indicators"""
        indicators = {
            'overall_health': 'healthy',
            'concerns': [],
            'recommendations': []
        }

        metrics = self.performance_metrics

        # Check error rate
        if metrics['error_rate'] > 0.05:  # 5% error rate
            indicators['overall_health'] = 'degraded'
            indicators['concerns'].append(f"High error rate: {metrics['error_rate']:.1%}")
            indicators['recommendations'].append("Investigate recent errors and performance issues")

        # Check response time
        if metrics['avg_response_time'] > 1.0:  # 1 second average
            indicators['overall_health'] = 'degraded' if indicators['overall_health'] == 'healthy' else indicators['overall_health']
            indicators['concerns'].append(f"Slow response time: {metrics['avg_response_time']:.2f}s")
            indicators['recommendations'].append("Check resource usage and optimize slow operations")

        # Check requests per second
        if metrics['requests_per_second'] > 50:  # High load threshold
            indicators['concerns'].append(f"High load: {metrics['requests_per_second']:.1f} req/s")
            indicators['recommendations'].append("Monitor resource usage and consider scaling")

        return indicators


class HealthChecker:
    """Comprehensive system health monitoring"""

    def __init__(self, daemon_instance):
        self.daemon = daemon_instance
        self.health_history = []

    def perform_health_check(self) -> Dict[str, Any]:
        """Perform comprehensive health check"""
        check_time = datetime.now()
        health_status = {
            'timestamp': check_time.isoformat(),
            'overall_status': 'healthy',
            'checks': {},
            'warnings': [],
            'errors': []
        }

        # Check daemon components
        self._check_daemon_components(health_status)
        self._check_resource_usage(health_status)
        self._check_helper_modules(health_status)
        self._check_socket_connectivity(health_status)
        self._check_performance_indicators(health_status)

        # Determine overall status
        if health_status['errors']:
            health_status['overall_status'] = 'unhealthy'
        elif health_status['warnings']:
            health_status['overall_status'] = 'degraded'

        # Store health history
        self.health_history.append(health_status)
        if len(self.health_history) > 100:  # Keep last 100 checks
            self.health_history = self.health_history[-100:]

        return health_status

    def _check_daemon_components(self, health_status: Dict[str, Any]):
        """Check core daemon components"""
        checks = health_status['checks']

        # Check if daemon is running
        checks['daemon_running'] = {
            'status': 'pass',
            'message': 'Daemon is running and responsive'
        }

        # Check thread health
        active_threads = len([t for t in self.daemon.threads if t.is_alive()])
        checks['thread_health'] = {
            'status': 'pass' if active_threads < 100 else 'warn',
            'message': f'{active_threads} active threads',
            'details': {'active_threads': active_threads}
        }

        if active_threads > 100:
            health_status['warnings'].append(f"High thread count: {active_threads}")

    def _check_resource_usage(self, health_status: Dict[str, Any]):
        """Check system resource usage"""
        checks = health_status['checks']

        try:
            # Memory usage
            memory_info = self.daemon.resource_manager.process.memory_info()
            memory_mb = memory_info.rss / 1024 / 1024

            checks['memory_usage'] = {
                'status': 'pass' if memory_mb < 500 else 'warn' if memory_mb < 1000 else 'fail',
                'message': f'{memory_mb:.1f} MB memory usage',
                'details': {'memory_mb': memory_mb}
            }

            if memory_mb > 1000:
                health_status['errors'].append(f"High memory usage: {memory_mb:.1f} MB")
            elif memory_mb > 500:
                health_status['warnings'].append(f"Elevated memory usage: {memory_mb:.1f} MB")

            # CPU usage
            cpu_percent = self.daemon.resource_manager.process.cpu_percent()
            checks['cpu_usage'] = {
                'status': 'pass' if cpu_percent < 80 else 'warn' if cpu_percent < 95 else 'fail',
                'message': f'{cpu_percent:.1f}% CPU usage',
                'details': {'cpu_percent': cpu_percent}
            }

            if cpu_percent > 95:
                health_status['errors'].append(f"High CPU usage: {cpu_percent:.1f}%")
            elif cpu_percent > 80:
                health_status['warnings'].append(f"Elevated CPU usage: {cpu_percent:.1f}%")

        except Exception as e:
            checks['resource_usage'] = {
                'status': 'fail',
                'message': f'Resource check failed: {str(e)}'
            }
            health_status['errors'].append(f"Resource monitoring error: {str(e)}")

    def _check_helper_modules(self, health_status: Dict[str, Any]):
        """Check helper module availability"""
        checks = health_status['checks']

        loaded_modules = len(self.daemon.helper_modules)
        expected_modules = ['test', 'http', 'datetime_helper', 'crypto', 'email_helper',
                           'logging_helper', 'excel', 'sftp', 'xpath']  # Core modules

        checks['helper_modules'] = {
            'status': 'pass' if loaded_modules >= len(expected_modules) * 0.8 else 'warn',
            'message': f'{loaded_modules} helper modules loaded',
            'details': {
                'loaded_modules': list(self.daemon.helper_modules.keys()),
                'expected_count': len(expected_modules)
            }
        }

        if loaded_modules < len(expected_modules) * 0.8:
            health_status['warnings'].append(f"Some helper modules missing: {loaded_modules}/{len(expected_modules)}")

    def _check_socket_connectivity(self, health_status: Dict[str, Any]):
        """Check socket connectivity"""
        checks = health_status['checks']

        try:
            # Check socket connectivity (platform-specific)
            socket_path = getattr(self, 'actual_socket_path', SOCKET_PATH)
            if os.name == 'nt':
                # For Windows TCP socket, check if server is listening
                if hasattr(self, 'server_socket') and self.server_socket:
                    checks['socket_connectivity'] = {
                        'status': 'pass',
                        'message': 'TCP socket is listening',
                        'details': {'socket_path': socket_path}
                    }
                else:
                    checks['socket_connectivity'] = {
                        'status': 'fail',
                        'message': 'TCP socket not available',
                        'details': {'socket_path': socket_path}
                    }
            else:
                # For Unix domain socket, check if file exists
                if os.path.exists(SOCKET_PATH):
                    checks['socket_connectivity'] = {
                        'status': 'pass',
                        'message': 'Socket file exists and accessible',
                        'details': {'socket_path': socket_path}
                    }
                else:
                    checks['socket_connectivity'] = {
                        'status': 'fail',
                        'message': 'Socket file not found',
                        'details': {'socket_path': socket_path}
                    }
                health_status['errors'].append("Socket file not accessible")

        except Exception as e:
            checks['socket_connectivity'] = {
                'status': 'fail',
                'message': f'Socket check failed: {str(e)}'
            }
            health_status['errors'].append(f"Socket connectivity error: {str(e)}")

    def _check_performance_indicators(self, health_status: Dict[str, Any]):
        """Check performance indicators"""
        checks = health_status['checks']

        try:
            performance_report = self.daemon.performance_monitor.get_performance_report()
            metrics = performance_report['performance_metrics']
            health_indicators = performance_report['health_indicators']

            checks['performance'] = {
                'status': 'pass' if health_indicators['overall_health'] == 'healthy' else 'warn',
                'message': f"Performance: {health_indicators['overall_health']}",
                'details': {
                    'error_rate': f"{metrics['error_rate']:.1%}",
                    'avg_response_time': f"{metrics['avg_response_time']:.3f}s",
                    'requests_per_second': f"{metrics['requests_per_second']:.1f}"
                }
            }

            if health_indicators['concerns']:
                health_status['warnings'].extend(health_indicators['concerns'])

        except Exception as e:
            checks['performance'] = {
                'status': 'fail',
                'message': f'Performance check failed: {str(e)}'
            }
            health_status['errors'].append(f"Performance monitoring error: {str(e)}")


class ConnectionManager:
    """Advanced connection management and monitoring"""

    def __init__(self, daemon_instance):
        self.daemon = daemon_instance

    def get_connection_status(self) -> Dict[str, Any]:
        """Get detailed connection status"""
        current_time = time.time()
        connections = []

        for conn_id, conn_info in self.daemon.active_connections.items():
            connection_duration = current_time - conn_info.start_time
            connections.append({
                'connection_id': conn_id,
                'start_time': datetime.fromtimestamp(conn_info.start_time).isoformat(),
                'duration_seconds': round(connection_duration, 2),
                'requests_count': conn_info.requests_count,
                'last_activity': datetime.fromtimestamp(conn_info.last_activity).isoformat(),
                'idle_time': round(current_time - conn_info.last_activity, 2),
                'status': 'active' if connection_duration < STALE_CONNECTION_TIMEOUT else 'stale'
            })

        # Sort by start time (newest first)
        connections.sort(key=lambda x: x['start_time'], reverse=True)

        return {
            'total_connections': len(connections),
            'active_connections': len([c for c in connections if c['status'] == 'active']),
            'stale_connections': len([c for c in connections if c['status'] == 'stale']),
            'connections': connections,
            'connection_limits': {
                'max_concurrent': MAX_CONCURRENT_REQUESTS,
                'stale_timeout': STALE_CONNECTION_TIMEOUT
            }
        }

    def cleanup_stale_connections(self) -> Dict[str, Any]:
        """Force cleanup of stale connections"""
        current_time = time.time()
        stale_connections = []

        for conn_id, conn_info in list(self.daemon.active_connections.items()):
            idle_time = current_time - conn_info.last_activity
            if idle_time > STALE_CONNECTION_TIMEOUT:
                stale_connections.append({
                    'connection_id': conn_id,
                    'idle_time': idle_time
                })
                del self.daemon.active_connections[conn_id]

        return {
            'cleaned_connections': len(stale_connections),
            'connections_details': stale_connections,
            'remaining_connections': len(self.daemon.active_connections)
        }


class ResourceManager:
    """Manages resource limits and monitoring"""

    def __init__(self):
        self.process = psutil.Process()
        self.request_timestamps = []
        self.concurrent_requests = 0
        self.peak_memory = 0.0
        self.peak_cpu = 0.0
        self.resource_alerts = defaultdict(int)

    def check_resource_limits(self) -> Dict[str, Any]:
        """Check if resource limits are exceeded"""
        current_time = datetime.now()

        # Get current resource usage
        memory_info = self.process.memory_info()
        memory_mb = memory_info.rss / 1024 / 1024  # Convert to MB
        cpu_percent = self.process.cpu_percent()

        # Update peaks
        self.peak_memory = max(self.peak_memory, memory_mb)
        self.peak_cpu = max(self.peak_cpu, cpu_percent)

        # Clean old request timestamps (keep last minute)
        minute_ago = current_time - timedelta(minutes=1)
        self.request_timestamps = [ts for ts in self.request_timestamps if ts > minute_ago]
        requests_per_minute = len(self.request_timestamps)

        # Check limits
        violations = []
        warnings = []

        if memory_mb > MAX_MEMORY_MB:
            violations.append(f"Memory usage {memory_mb:.1f}MB exceeds limit {MAX_MEMORY_MB}MB")
            self.resource_alerts['memory'] += 1

        elif memory_mb > MAX_MEMORY_MB * 0.8:  # 80% warning threshold
            warnings.append(f"Memory usage {memory_mb:.1f}MB approaching limit {MAX_MEMORY_MB}MB")

        if cpu_percent > MAX_CPU_PERCENT:
            violations.append(f"CPU usage {cpu_percent:.1f}% exceeds limit {MAX_CPU_PERCENT}%")
            self.resource_alerts['cpu'] += 1

        elif cpu_percent > MAX_CPU_PERCENT * 0.8:  # 80% warning threshold
            warnings.append(f"CPU usage {cpu_percent:.1f}% approaching limit {MAX_CPU_PERCENT}%")

        if requests_per_minute > MAX_REQUESTS_PER_MINUTE:
            violations.append(f"Request rate {requests_per_minute}/min exceeds limit {MAX_REQUESTS_PER_MINUTE}/min")
            self.resource_alerts['requests'] += 1

        if self.concurrent_requests > MAX_CONCURRENT_REQUESTS:
            violations.append(f"Concurrent requests {self.concurrent_requests} exceeds limit {MAX_CONCURRENT_REQUESTS}")
            self.resource_alerts['concurrent'] += 1

        return {
            'memory_mb': memory_mb,
            'cpu_percent': cpu_percent,
            'requests_per_minute': requests_per_minute,
            'concurrent_requests': self.concurrent_requests,
            'violations': violations,
            'warnings': warnings,
            'peak_memory': self.peak_memory,
            'peak_cpu': self.peak_cpu,
            'alerts': dict(self.resource_alerts)
        }

    def track_request(self):
        """Track a new request"""
        self.request_timestamps.append(datetime.now())
        self.concurrent_requests += 1

    def complete_request(self):
        """Mark a request as completed"""
        self.concurrent_requests = max(0, self.concurrent_requests - 1)

    def get_metrics(self) -> ResourceMetrics:
        """Get current resource metrics"""
        status = self.check_resource_limits()
        return ResourceMetrics(
            memory_mb=status['memory_mb'],
            cpu_percent=status['cpu_percent'],
            concurrent_requests=status['concurrent_requests'],
            requests_per_minute=status['requests_per_minute']
        )


class CPANBridgeDaemon:
    """Main daemon class for CPAN Bridge operations"""

    def __init__(self):
        """Initialize the daemon"""
        self.running = True
        self.server_socket = None
        self.helper_modules = {}
        self.active_connections = {}  # Changed to dict for better tracking

        # Enhanced statistics
        self.stats = {
            'requests_processed': 0,
            'requests_failed': 0,
            'requests_rejected': 0,
            'validation_failures': 0,
            'security_events': 0,
            'start_time': time.time(),
            'last_cleanup': time.time(),
            'last_resource_check': time.time(),
            'connections_total': 0,
            'connections_rejected': 0,
            'peak_connections': 0
        }

        # Resource management
        self.resource_manager = ResourceManager()
        self.connection_lock = threading.Lock()

        # Enhanced validation and security
        self.validator = RequestValidator()
        self.security_logger = SecurityLogger()

        # Operational monitoring components
        self.performance_monitor = PerformanceMonitor()
        self.health_checker = HealthChecker(self)
        self.connection_manager = ConnectionManager(self)

        # Thread management
        self.threads = []
        self.cleanup_thread = None
        self.health_thread = None
        self.resource_thread = None

        # Setup signal handlers
        signal.signal(signal.SIGTERM, self._signal_handler)
        signal.signal(signal.SIGINT, self._signal_handler)

        logger.info(f"CPAN Bridge Daemon v{__version__} initializing...")
        logger.info(f"Resource limits - Memory: {MAX_MEMORY_MB}MB, CPU: {MAX_CPU_PERCENT}%, "
                   f"Requests/min: {MAX_REQUESTS_PER_MINUTE}, Concurrent: {MAX_CONCURRENT_REQUESTS}")
        logger.info(f"Resource monitoring - Stale timeout: {STALE_CONNECTION_TIMEOUT}s, "
                   f"Check interval: {RESOURCE_CHECK_INTERVAL}s")
        logger.info(f"Validation limits - String: {MAX_STRING_LENGTH}, Array: {MAX_ARRAY_LENGTH}, "
                   f"Depth: {MAX_OBJECT_DEPTH}, Params: {MAX_PARAM_COUNT}")
        logger.info(f"Security features - Strict validation: {ENABLE_STRICT_VALIDATION}, "
                   f"Security logging: enabled")

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

    def _validate_request(self, request: Dict[str, Any], client_info: str = "") -> ValidationResult:
        """Enhanced request validation with comprehensive security checks"""
        # Generate or extract request ID for tracking
        request_id = request.get('request_id', str(uuid.uuid4()))
        request['request_id'] = request_id

        # Perform comprehensive validation
        validation_result = self.validator.validate_request(request, client_info)

        # Log all security events
        for event in validation_result.security_events:
            self.security_logger.log_security_event(event)
            self.stats['security_events'] += 1

        # Update statistics
        if not validation_result.is_valid:
            self.stats['validation_failures'] += 1
            self.stats['requests_rejected'] += 1

            # Log validation failure
            security_logger.warning(
                f"Request validation failed - Request ID: {request_id}, "
                f"Client: {client_info}, Errors: {validation_result.errors}"
            )

        # Log warnings even for valid requests
        if validation_result.warnings:
            security_logger.info(
                f"Request validation warnings - Request ID: {request_id}, "
                f"Client: {client_info}, Warnings: {validation_result.warnings}"
            )

        return validation_result

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

        elif function_name == 'stats':
            return {
                'success': True,
                'result': {
                    **self.stats.copy(),
                    'security_metrics': self.security_logger.get_security_metrics(),
                    'validation_config': {
                        'strict_mode': ENABLE_STRICT_VALIDATION,
                        'max_string_length': MAX_STRING_LENGTH,
                        'max_array_length': MAX_ARRAY_LENGTH,
                        'max_object_depth': MAX_OBJECT_DEPTH,
                        'max_param_count': MAX_PARAM_COUNT
                    }
                }
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
                    'socket_path': getattr(self, 'actual_socket_path', SOCKET_PATH),
                    'uptime': time.time() - self.stats['start_time'],
                    'loaded_modules': list(self.helper_modules.keys()),
                    'active_connections': len(self.active_connections),
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

        elif function_name == 'health':
            # Comprehensive health check
            health_status = self.health_checker.perform_health_check()
            return {
                'success': True,
                'result': health_status
            }

        elif function_name == 'performance':
            # Detailed performance report
            performance_report = self.performance_monitor.get_performance_report()
            return {
                'success': True,
                'result': performance_report
            }

        elif function_name == 'connections':
            # Connection management and status
            connection_status = self.connection_manager.get_connection_status()
            return {
                'success': True,
                'result': connection_status
            }

        elif function_name == 'cleanup':
            # Force cleanup of stale connections
            cleanup_result = self.connection_manager.cleanup_stale_connections()
            return {
                'success': True,
                'result': cleanup_result
            }

        elif function_name == 'metrics':
            # Combined metrics dashboard
            current_time = time.time()
            uptime = current_time - self.stats['start_time']

            # Get resource status
            resource_status = self.resource_manager.check_resource_limits()

            # Get performance summary
            performance_report = self.performance_monitor.get_performance_report()

            # Get security metrics
            security_metrics = self.security_logger.get_security_metrics()

            # Get connection summary
            connection_status = self.connection_manager.get_connection_status()

            return {
                'success': True,
                'result': {
                    'timestamp': datetime.now().isoformat(),
                    'daemon_info': {
                        'version': __version__,
                        'uptime_seconds': uptime,
                        'uptime_formatted': f"{int(uptime//3600)}h {int((uptime%3600)//60)}m {int(uptime%60)}s"
                    },
                    'resource_status': resource_status,
                    'performance_metrics': performance_report['performance_metrics'],
                    'security_summary': {
                        'total_security_events': security_metrics['total_events'],
                        'validation_failures': self.stats.get('validation_failures', 0),
                        'requests_rejected': self.stats.get('requests_rejected', 0)
                    },
                    'connection_summary': {
                        'total_connections': connection_status['total_connections'],
                        'active_connections': connection_status['active_connections'],
                        'stale_connections': connection_status['stale_connections']
                    },
                    'module_status': {
                        'loaded_modules': len(self.helper_modules),
                        'available_modules': list(self.helper_modules.keys())
                    },
                    'system_stats': self.stats.copy()
                }
            }

        elif function_name == 'stats':
            # Enhanced stats with all monitoring data
            return {
                'success': True,
                'result': {
                    **self.stats.copy(),
                    'security_metrics': self.security_logger.get_security_metrics(),
                    'performance_summary': self.performance_monitor.get_performance_report()['performance_metrics'],
                    'resource_status': self.resource_manager.check_resource_limits(),
                    'validation_config': {
                        'strict_mode': ENABLE_STRICT_VALIDATION,
                        'max_string_length': MAX_STRING_LENGTH,
                        'max_array_length': MAX_ARRAY_LENGTH,
                        'max_object_depth': MAX_OBJECT_DEPTH,
                        'max_param_count': MAX_PARAM_COUNT
                    }
                }
            }

        else:
            raise ValueError(f"Unknown system function: {function_name}")

    def _handle_client(self, client_socket, client_address):
        """Handle individual client request"""
        connection_id = f"{client_address}_{threading.get_ident()}_{time.time()}"
        start_time = time.time()

        # Track connection
        with self.connection_lock:
            conn_info = ConnectionInfo(
                client_address=str(client_address),
                start_time=start_time,
                last_activity=start_time,
                thread_id=threading.get_ident()
            )
            self.active_connections[connection_id] = conn_info
            self.stats['connections_total'] += 1
            self.stats['peak_connections'] = max(self.stats['peak_connections'],
                                               len(self.active_connections))

        try:
            logger.debug(f"Handling client connection {connection_id}")

            # Check resource limits before processing
            resource_status = self.resource_manager.check_resource_limits()
            if resource_status['violations']:
                logger.warning(f"Resource violations detected: {resource_status['violations']}")
                # Still process but log the violation

            # Track request start
            self.resource_manager.track_request()

            # Read request with size limit and timeout
            client_socket.settimeout(30.0)  # 30 second timeout for reading
            data = b''
            total_bytes = 0

            while len(data) < MAX_REQUEST_SIZE:
                try:
                    chunk = client_socket.recv(4096)
                    if not chunk:
                        break
                    data += chunk
                    total_bytes += len(chunk)

                    # Update connection activity
                    with self.connection_lock:
                        if connection_id in self.active_connections:
                            self.active_connections[connection_id].last_activity = time.time()
                            self.active_connections[connection_id].bytes_received += len(chunk)

                    # Try to parse JSON to see if we have complete message
                    try:
                        json.loads(data.decode('utf-8'))
                        break  # Complete JSON received
                    except json.JSONDecodeError:
                        continue  # Need more data

                except socket.timeout:
                    raise ValueError("Request timeout - data transmission too slow")

            if len(data) >= MAX_REQUEST_SIZE:
                self.stats['requests_rejected'] += 1
                raise ValueError(f"Request too large: {len(data)} bytes (max: {MAX_REQUEST_SIZE})")

            if not data:
                raise ValueError("Empty request received")

            # Parse JSON request
            request_str = data.decode('utf-8')
            request = json.loads(request_str)

            logger.debug(f"Received request: {request.get('module', 'unknown')}.{request.get('function', 'unknown')}")

            # Update connection request count
            with self.connection_lock:
                if connection_id in self.active_connections:
                    self.active_connections[connection_id].requests_count += 1

            # Enhanced validation with security logging
            validation_result = self._validate_request(request, str(client_address))

            if not validation_result.is_valid:
                raise ValueError(f"Request validation failed: {'; '.join(validation_result.errors)}")

            # Use sanitized request for processing
            sanitized_request = validation_result.sanitized_request or request

            # Track performance
            start_time = time.time()
            response = self._route_request(sanitized_request)
            duration = time.time() - start_time

            # Record performance metrics
            module_name = sanitized_request.get('module', 'unknown')
            function_name = sanitized_request.get('function', 'unknown')
            success = response.get('success', False)
            error_msg = response.get('error', '') if not success else None

            self.performance_monitor.record_request(
                module_name, function_name, duration, success, error_msg
            )

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

                # Clean up stale connections
                current_time = time.time()  # Use timestamp for consistency
                stale_connections = []

                with self.connection_lock:
                    for conn_id, conn_info in list(self.active_connections.items()):
                        time_since_activity = current_time - conn_info.last_activity
                        if time_since_activity > STALE_CONNECTION_TIMEOUT:
                            stale_connections.append(conn_id)
                            logger.debug(f"Found stale connection {conn_id} - {time_since_activity:.1f}s since last activity")

                    # Remove stale connections
                    for conn_id in stale_connections:
                        try:
                            del self.active_connections[conn_id]
                            logger.debug(f"Removed stale connection {conn_id}")
                        except Exception as e:
                            logger.warning(f"Error removing stale connection {conn_id}: {e}")

                if stale_connections:
                    logger.info(f"Cleaned up {len(stale_connections)} stale connections")

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

                # Log resource status if there are issues
                try:
                    resource_status = self.resource_manager.check_resource_limits()
                    if resource_status['violations']:
                        logger.warning(f"Resource violations: {resource_status['violations']}")
                    elif resource_status['warnings']:
                        logger.info(f"Resource warnings: {resource_status['warnings']}")
                except Exception as e:
                    logger.error(f"Error checking resource limits: {e}")

            except Exception as e:
                logger.error(f"Error in health thread: {e}")

        logger.info("Health monitoring thread stopped")

    def _resource_thread_func(self):
        """Background thread for resource monitoring"""
        logger.info("Resource monitoring thread started")

        while self.running:
            try:
                time.sleep(RESOURCE_CHECK_INTERVAL)
                if not self.running:
                    break

                # Check resource limits
                resource_status = self.resource_manager.check_resource_limits()
                current_time = time.time()
                self.stats['last_resource_check'] = current_time

                # Log violations and warnings
                if resource_status['violations']:
                    logger.critical(f"RESOURCE VIOLATION: {resource_status['violations']}")
                    logger.critical(f"Memory: {resource_status['memory_mb']:.1f}MB, "
                                  f"CPU: {resource_status['cpu_percent']:.1f}%, "
                                  f"Requests/min: {resource_status['requests_per_minute']}, "
                                  f"Concurrent: {resource_status['concurrent_requests']}")

                elif resource_status['warnings']:
                    logger.warning(f"Resource warning: {resource_status['warnings']}")

                # Log periodic resource summary
                if current_time % 300 < RESOURCE_CHECK_INTERVAL:  # Every 5 minutes
                    logger.info(f"Resource summary - "
                               f"Memory: {resource_status['memory_mb']:.1f}MB "
                               f"(peak: {resource_status['peak_memory']:.1f}MB), "
                               f"CPU: {resource_status['cpu_percent']:.1f}% "
                               f"(peak: {resource_status['peak_cpu']:.1f}%), "
                               f"Concurrent requests: {resource_status['concurrent_requests']}, "
                               f"Requests/min: {resource_status['requests_per_minute']}")

            except Exception as e:
                logger.error(f"Error in resource thread: {e}")

        logger.info("Resource monitoring thread stopped")

    def _create_socket(self):
        """Create and configure Unix domain socket"""
        # Platform-specific socket creation
        if os.name == 'nt':  # Windows - use TCP localhost socket
            # For Windows, use localhost TCP socket instead of Unix domain socket
            self.server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            self.server_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            # Use a high port number to avoid conflicts
            self.server_socket.bind(('127.0.0.1', 0))  # Let system choose available port
            self.actual_socket_path = f"127.0.0.1:{self.server_socket.getsockname()[1]}"
        else:  # Unix-like systems
            # Remove existing socket file
            if os.path.exists(SOCKET_PATH):
                os.unlink(SOCKET_PATH)

            # Create Unix domain socket
            self.server_socket = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            self.server_socket.bind(SOCKET_PATH)
            self.actual_socket_path = SOCKET_PATH

            # Set restrictive permissions (owner only)
            os.chmod(SOCKET_PATH, 0o600)

        # Start listening
        self.server_socket.listen(MAX_CONNECTIONS)

        if os.name == 'nt':
            logger.info(f"TCP socket created at {self.actual_socket_path}")
            # Save socket info for Windows Perl clients
            try:
                with open('cpan_bridge_socket.txt', 'w') as f:
                    f.write(self.actual_socket_path)
            except Exception as e:
                logger.warning(f"Could not save socket info file: {e}")
        else:
            logger.info(f"Unix domain socket created at {self.actual_socket_path}")

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
            self.resource_thread = threading.Thread(target=self._resource_thread_func, daemon=True)

            self.cleanup_thread.start()
            self.health_thread.start()
            self.resource_thread.start()

            logger.info(f"CPAN Bridge Daemon v{__version__} started successfully")
            logger.info(f"Listening on {self.actual_socket_path}")
            logger.info(f"Loaded modules: {list(self.helper_modules.keys())}")

            # Main server loop
            while self.running:
                try:
                    # Check connection limits before accepting
                    if len(self.active_connections) >= MAX_CONNECTIONS:
                        logger.warning(f"Connection limit reached ({MAX_CONNECTIONS}), rejecting new connections")
                        time.sleep(0.1)  # Brief pause to prevent tight loop
                        continue

                    # Check resource limits before accepting
                    resource_status = self.resource_manager.check_resource_limits()
                    if resource_status['violations']:
                        logger.warning(f"Resource violations detected, throttling connections: {resource_status['violations']}")
                        time.sleep(1.0)  # Longer pause under resource pressure
                        continue

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
        # Cleanup socket file (Unix only)
        try:
            if os.name != 'nt' and os.path.exists(SOCKET_PATH):
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