#!/usr/bin/env python3
"""
logging_helper.py - Complete Log::Log4perl replacement

Provides comprehensive logging functionality based on enterprise Log4perl usage analysis.
Implements WlaLog.pm wrapper patterns with programmatic configuration.
"""

import logging
import sys
import os
import time
import uuid
from datetime import datetime
from typing import Dict, Any, List, Optional

# Global state storage (matches Log::Log4perl singleton pattern)
LOGGERS = {}
APPENDERS = {}
LAYOUTS = {}
INITIALIZED = False
CALLER_DEPTH = 1

# Log level mapping (matches Log4perl levels)
LEVEL_MAP = {
    'TRACE': 5,
    'DEBUG': logging.DEBUG,     # 10
    'INFO': logging.INFO,       # 20
    'WARN': logging.WARNING,    # 30
    'WARNING': logging.WARNING, # 30
    'ERROR': logging.ERROR,     # 40
    'FATAL': logging.CRITICAL,  # 50
    'CRITICAL': logging.CRITICAL, # 50
}

# Add TRACE level to Python logging
logging.addLevelName(5, 'TRACE')

def initialized() -> Dict[str, Any]:
    """
    Check if Log4perl system has been initialized

    Returns:
        Dictionary with initialization status
    """
    return {
        'success': True,
        'result': INITIALIZED
    }

def init_logger(category: str = "main", level: str = "INFO",
                caller_depth: int = 1) -> Dict[str, Any]:
    """
    Initialize Log4perl-style logger with programmatic configuration
    (matches Log::Log4perl->get_logger() + appender setup)

    Args:
        category: Logger category/name
        level: Default log level
        caller_depth: Caller depth for enhanced formatting

    Returns:
        Dictionary with logger ID and configuration
    """
    global INITIALIZED, CALLER_DEPTH

    try:
        CALLER_DEPTH = caller_depth

        # Create unique logger ID
        logger_id = str(uuid.uuid4())

        # Get or create Python logger
        py_logger = logging.getLogger(category)
        py_logger.handlers.clear()  # Clear any existing handlers

        # Set logger level
        log_level = LEVEL_MAP.get(level.upper(), logging.INFO)
        py_logger.setLevel(log_level)

        # Create Screen appender (matches Log::Log4perl::Appender::Screen)
        appender_name = "sysout"
        handler = logging.StreamHandler(sys.stdout)

        # Create PatternLayout (matches %d{EEE yyyy/MM/dd HH:mm:ss}|%m%n)
        layout_pattern = "%(day_abbrev)s %(asctime)s|%(message)s"
        formatter = Log4perlFormatter(layout_pattern)
        handler.setFormatter(formatter)

        py_logger.addHandler(handler)

        # Store logger configuration
        LOGGERS[logger_id] = {
            'category': category,
            'logger': py_logger,
            'level': level,
            'appender_name': appender_name,
            'handler': handler,
            'original_layout': formatter,
            'current_level': log_level
        }

        # Store appender reference
        APPENDERS[appender_name] = {
            'handler': handler,
            'original_layout': formatter
        }

        INITIALIZED = True

        return {
            'success': True,
            'result': {
                'logger_id': logger_id,
                'category': category,
                'level': level,
                'appender': appender_name
            }
        }

    except Exception as e:
        return {
            'success': False,
            'error': f'Logger initialization failed: {str(e)}'
        }

def get_logger(category: str = "main") -> Dict[str, Any]:
    """
    Get existing logger instance (matches Log::Log4perl->get_logger())

    Args:
        category: Logger category name

    Returns:
        Dictionary with logger ID or creates new one
    """
    try:
        # Find existing logger with this category
        for logger_id, config in LOGGERS.items():
            if config['category'] == category:
                return {
                    'success': True,
                    'result': {
                        'logger_id': logger_id,
                        'category': category
                    }
                }

        # If not found, create new logger with default settings
        return init_logger(category, "INFO")

    except Exception as e:
        return {
            'success': False,
            'error': f'Get logger failed: {str(e)}'
        }

def log_message(logger_id: str, level: str, message: str,
                filename: str = None, line: int = None,
                package: str = None, enhanced: bool = False) -> Dict[str, Any]:
    """
    Log message with optional enhanced formatting

    Args:
        logger_id: Logger instance ID
        level: Log level (TRACE, DEBUG, INFO, WARN, ERROR, FATAL)
        message: Log message
        filename: Source filename (for enhanced formatting)
        line: Source line number (for enhanced formatting)
        package: Source package (for enhanced formatting)
        enhanced: Use enhanced debug/error formatting

    Returns:
        Dictionary with logging result
    """
    try:
        if logger_id not in LOGGERS:
            return {
                'success': False,
                'error': 'Logger not found'
            }

        config = LOGGERS[logger_id]
        py_logger = config['logger']
        log_level = LEVEL_MAP.get(level.upper(), logging.INFO)

        # Format message based on pattern
        if enhanced and filename and line:
            if level.upper() == 'DEBUG':
                formatted_message = f"DEBUG: {filename} line:{line}: {message}"
            elif level.upper() in ['ERROR', 'FATAL']:
                formatted_message = f"{filename} line:{line}: {message}"
            elif level.upper() == 'FATAL':
                formatted_message = f"LOGANDDIE> {filename} line:{line}: {message} \n\tExiting program {filename}"
            else:
                formatted_message = message
        else:
            formatted_message = message

        # Switch to debug layout for enhanced messages
        if enhanced and level.upper() in ['DEBUG', 'ERROR', 'FATAL']:
            _switch_to_debug_layout(logger_id)

        # Log the message
        py_logger.log(log_level, formatted_message)

        # Reset layout if switched
        if enhanced and level.upper() in ['DEBUG', 'ERROR', 'FATAL']:
            _reset_original_layout(logger_id)

        return {
            'success': True,
            'result': {
                'logged': True,
                'level': level,
                'message': formatted_message
            }
        }

    except Exception as e:
        return {
            'success': False,
            'error': f'Logging failed: {str(e)}'
        }

def log_trace(logger_id: str, message: str, **kwargs) -> Dict[str, Any]:
    """Log TRACE level message"""
    return log_message(logger_id, 'TRACE', message, **kwargs)

def log_debug(logger_id: str, message: str, **kwargs) -> Dict[str, Any]:
    """Log DEBUG level message with enhanced formatting"""
    kwargs['enhanced'] = True
    return log_message(logger_id, 'DEBUG', message, **kwargs)

def log_info(logger_id: str, message: str, **kwargs) -> Dict[str, Any]:
    """Log INFO level message"""
    return log_message(logger_id, 'INFO', message, **kwargs)

def log_warn(logger_id: str, message: str, **kwargs) -> Dict[str, Any]:
    """Log WARN level message"""
    return log_message(logger_id, 'WARN', message, **kwargs)

def log_error(logger_id: str, message: str, **kwargs) -> Dict[str, Any]:
    """Log ERROR level message with enhanced formatting"""
    kwargs['enhanced'] = True
    return log_message(logger_id, 'ERROR', message, **kwargs)

def log_fatal(logger_id: str, message: str, **kwargs) -> Dict[str, Any]:
    """Log FATAL level message with enhanced formatting"""
    kwargs['enhanced'] = True
    return log_message(logger_id, 'FATAL', message, **kwargs)

def logdie(logger_id: str, message: str, **kwargs) -> Dict[str, Any]:
    """Log FATAL message and indicate program should exit"""
    kwargs['enhanced'] = True
    result = log_message(logger_id, 'FATAL', message, **kwargs)
    if result['success']:
        result['result']['should_exit'] = True
    return result

def always_log(logger_id: str, message: str, **kwargs) -> Dict[str, Any]:
    """
    Log message bypassing level restrictions (always log pattern)

    Args:
        logger_id: Logger instance ID
        message: Message to log
        **kwargs: Additional parameters

    Returns:
        Dictionary with logging result
    """
    try:
        if logger_id not in LOGGERS:
            return {
                'success': False,
                'error': 'Logger not found'
            }

        config = LOGGERS[logger_id]
        py_logger = config['logger']

        # Store current level
        current_level = py_logger.level

        # Set to TRACE to ensure message is logged
        py_logger.setLevel(5)  # TRACE level

        # Log as TRACE
        result = log_message(logger_id, 'TRACE', message, **kwargs)

        # Restore original level
        py_logger.setLevel(current_level)

        return result

    except Exception as e:
        return {
            'success': False,
            'error': f'Always log failed: {str(e)}'
        }

def is_trace(logger_id: str) -> Dict[str, Any]:
    """Check if TRACE level is enabled"""
    return _is_level_enabled(logger_id, 'TRACE')

def is_debug(logger_id: str) -> Dict[str, Any]:
    """Check if DEBUG level is enabled"""
    return _is_level_enabled(logger_id, 'DEBUG')

def is_info(logger_id: str) -> Dict[str, Any]:
    """Check if INFO level is enabled"""
    return _is_level_enabled(logger_id, 'INFO')

def is_warn(logger_id: str) -> Dict[str, Any]:
    """Check if WARN level is enabled"""
    return _is_level_enabled(logger_id, 'WARN')

def is_error(logger_id: str) -> Dict[str, Any]:
    """Check if ERROR level is enabled"""
    return _is_level_enabled(logger_id, 'ERROR')

def is_fatal(logger_id: str) -> Dict[str, Any]:
    """Check if FATAL level is enabled"""
    return _is_level_enabled(logger_id, 'FATAL')

def _is_level_enabled(logger_id: str, level: str) -> Dict[str, Any]:
    """Check if specific log level is enabled"""
    try:
        if logger_id not in LOGGERS:
            return {
                'success': False,
                'error': 'Logger not found'
            }

        config = LOGGERS[logger_id]
        py_logger = config['logger']
        log_level = LEVEL_MAP.get(level.upper(), logging.INFO)

        enabled = py_logger.isEnabledFor(log_level)

        return {
            'success': True,
            'result': enabled
        }

    except Exception as e:
        return {
            'success': False,
            'error': f'Level check failed: {str(e)}'
        }

def set_level(logger_id: str, level: str) -> Dict[str, Any]:
    """
    Set logger level (matches $logger->level($setlevel))

    Args:
        logger_id: Logger instance ID
        level: New log level

    Returns:
        Dictionary with result
    """
    try:
        if logger_id not in LOGGERS:
            return {
                'success': False,
                'error': 'Logger not found'
            }

        config = LOGGERS[logger_id]
        py_logger = config['logger']
        log_level = LEVEL_MAP.get(level.upper(), logging.INFO)

        py_logger.setLevel(log_level)
        config['level'] = level
        config['current_level'] = log_level

        return {
            'success': True,
            'result': {
                'level': level,
                'numeric_level': log_level
            }
        }

    except Exception as e:
        return {
            'success': False,
            'error': f'Set level failed: {str(e)}'
        }

def get_level(logger_id: str) -> Dict[str, Any]:
    """
    Get current logger level

    Args:
        logger_id: Logger instance ID

    Returns:
        Dictionary with current level
    """
    try:
        if logger_id not in LOGGERS:
            return {
                'success': False,
                'error': 'Logger not found'
            }

        config = LOGGERS[logger_id]

        return {
            'success': True,
            'result': {
                'level': config['level'],
                'numeric_level': config['current_level']
            }
        }

    except Exception as e:
        return {
            'success': False,
            'error': f'Get level failed: {str(e)}'
        }

def appender_by_name(appender_name: str) -> Dict[str, Any]:
    """
    Get appender by name (matches Log::Log4perl->appender_by_name())

    Args:
        appender_name: Name of appender

    Returns:
        Dictionary with appender info
    """
    try:
        if appender_name not in APPENDERS:
            return {
                'success': False,
                'error': f'Appender not found: {appender_name}'
            }

        appender_id = str(uuid.uuid4())

        return {
            'success': True,
            'result': {
                'appender_id': appender_id,
                'appender_name': appender_name,
                'handler': appender_name  # For layout switching
            }
        }

    except Exception as e:
        return {
            'success': False,
            'error': f'Get appender failed: {str(e)}'
        }

def set_layout(appender_name: str, layout_pattern: str) -> Dict[str, Any]:
    """
    Set layout for appender (matches $a->layout($debuglayout))

    Args:
        appender_name: Name of appender
        layout_pattern: Layout pattern string

    Returns:
        Dictionary with result
    """
    try:
        if appender_name not in APPENDERS:
            return {
                'success': False,
                'error': f'Appender not found: {appender_name}'
            }

        appender = APPENDERS[appender_name]
        handler = appender['handler']

        # Create new formatter based on pattern
        if layout_pattern == "debug":
            # Debug layout: %d|%p> %m%n
            formatter = Log4perlFormatter("%(day_abbrev)s %(asctime)s|%(levelname)s> %(message)s")
        elif layout_pattern == "simple":
            # Simple layout: %d|%m%n
            formatter = Log4perlFormatter("%(day_abbrev)s %(asctime)s|%(message)s")
        else:
            # Custom pattern
            formatter = Log4perlFormatter(layout_pattern)

        handler.setFormatter(formatter)

        return {
            'success': True,
            'result': {
                'appender': appender_name,
                'layout': layout_pattern
            }
        }

    except Exception as e:
        return {
            'success': False,
            'error': f'Set layout failed: {str(e)}'
        }

def _switch_to_debug_layout(logger_id: str) -> None:
    """Switch to debug layout for enhanced messages"""
    try:
        config = LOGGERS[logger_id]
        appender_name = config['appender_name']
        set_layout(appender_name, "debug")
    except:
        pass

def _reset_original_layout(logger_id: str) -> None:
    """Reset to original layout"""
    try:
        config = LOGGERS[logger_id]
        appender_name = config['appender_name']
        appender = APPENDERS[appender_name]
        handler = appender['handler']
        original_formatter = appender['original_layout']
        handler.setFormatter(original_formatter)
    except:
        pass

class Log4perlFormatter(logging.Formatter):
    """Custom formatter that mimics Log4perl patterns"""

    def __init__(self, pattern):
        super().__init__()
        self.pattern = pattern

    def format(self, record):
        # Create day abbreviation
        day_abbrev = datetime.now().strftime('%a')

        # Create timestamp in Log4perl format
        timestamp = datetime.now().strftime('%Y/%m/%d %H:%M:%S')

        # Add custom fields to record
        record.day_abbrev = day_abbrev
        record.asctime = timestamp

        # Format the message
        return self.pattern % record.__dict__

def cleanup_logger(logger_id: str) -> Dict[str, Any]:
    """
    Clean up logger resources

    Args:
        logger_id: Logger instance ID

    Returns:
        Dictionary with cleanup result
    """
    try:
        if logger_id in LOGGERS:
            config = LOGGERS[logger_id]

            # Close handlers
            if 'handler' in config:
                config['handler'].close()

            # Remove from storage
            del LOGGERS[logger_id]

        return {
            'success': True,
            'result': {
                'logger_id': logger_id,
                'cleaned_up': True
            }
        }

    except Exception as e:
        return {
            'success': False,
            'error': f'Logger cleanup failed: {str(e)}'
        }

# Convenience function for wrapper registration (matches Log::Log4perl->wrapper_register)
def wrapper_register(package_name: str) -> Dict[str, Any]:
    """
    Register wrapper package (compatibility function)

    Args:
        package_name: Package name to register

    Returns:
        Dictionary with registration result
    """
    return {
        'success': True,
        'result': {
            'package': package_name,
            'registered': True
        }
    }