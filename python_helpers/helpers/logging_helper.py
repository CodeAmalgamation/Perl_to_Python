#!/usr/bin/env python3
"""
logging_helper.py - Logging backend for Log::Log4perl replacement

Provides logging functionality using Python's standard logging module.
Implements Log4perl-style formatting and appender patterns.
"""

import logging
import sys
import time
import re
from datetime import datetime
from typing import Dict, Any, List

# Global logger storage
LOGGERS = {}
APPENDERS = {}

# Log level mapping
LEVEL_MAP = {
    'TRACE': 5,      # Custom level below DEBUG
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

def log_message(category: str, level: str, message: str, filename: str = None,
               line: int = None, package: str = None, timestamp: float = None,
               appenders: List[Dict[str, Any]] = None) -> Dict[str, Any]:
    """
    Log a message using Python logging with Log4perl-style formatting
    
    Args:
        category: Logger category/name
        level: Log level (TRACE, DEBUG, INFO, WARN, ERROR, FATAL)
        message: Log message
        filename: Source filename (for enhanced formatting)
        line: Source line number (for enhanced formatting)
        package: Source package (for enhanced formatting)
        timestamp: Message timestamp
        appenders: List of appender configurations
    
    Returns:
        Dictionary with operation result
    """
    try:
        # Get or create logger
        logger = get_logger(category)
        
        # Convert level
        numeric_level = LEVEL_MAP.get(level.upper(), logging.INFO)
        
        # Format timestamp
        if timestamp:
            dt = datetime.fromtimestamp(timestamp)
        else:
            dt = datetime.now()
        
        # Determine layout pattern based on level and message content
        layout_pattern = _determine_layout_pattern(level, message, appenders)
        
        # Format message according to pattern
        formatted_message = _format_message(
            layout_pattern, dt, level, message, 
            filename, line, package, category
        )
        
        # Log the message
        logger.log(numeric_level, formatted_message)
        
        return {
            'success': True,
            'result': {
                'category': category,
                'level': level,
                'formatted_message': formatted_message,
                'timestamp': dt.isoformat()
            }
        }
        
    except Exception as e:
        return {
            'success': False,
            'error': f'Logging operation failed: {str(e)}'
        }

def get_logger(category: str) -> logging.Logger:
    """Get or create a logger for the given category"""
    if category not in LOGGERS:
        logger = logging.getLogger(category)
        
        # Configure default handler if none exists
        if not logger.handlers:
            handler = logging.StreamHandler(sys.stderr)
            handler.setFormatter(logging.Formatter('%(message)s'))
            logger.addHandler(handler)
            logger.setLevel(logging.INFO)
        
        LOGGERS[category] = logger
    
    return LOGGERS[category]

def _determine_layout_pattern(level: str, message: str, appenders: List[Dict[str, Any]] = None) -> str:
    """
    Determine the appropriate layout pattern based on level and context
    
    Based on your usage analysis:
    - Standard: "%d{EEE yyyy/MM/dd HH:mm:ss}|%m%n"
    - Debug/Error: "%d|%p> %m%n" 
    - Simple: "%d|%m%n"
    """
    
    # Check if this is an enhanced debug/error message (contains filename/line info)
    if any(pattern in message for pattern in ['line:', 'DEBUG:', 'LOGANDDIE>']):
        return "%d|%p> %m%n"  # Debug/error layout with log level
    
    # Check if appenders specify a particular layout
    if appenders:
        for appender in appenders:
            if hasattr(appender, 'layout') and appender.layout:
                if hasattr(appender.layout, 'pattern'):
                    return appender.layout.pattern()
    
    # Default standard layout
    return "%d{EEE yyyy/MM/dd HH:mm:ss}|%m%n"

def _format_message(pattern: str, dt: datetime, level: str, message: str,
                   filename: str = None, line: int = None, package: str = None,
                   category: str = None) -> str:
    """
    Format message according to Log4perl-style pattern
    
    Supported patterns:
    %d{format} - Date/time with optional format
    %p - Log level
    %m - Message
    %n - Newline
    %c - Category
    %F - Filename
    %L - Line number
    """
    
    formatted = pattern
    
    # Handle date formatting
    if '%d{EEE yyyy/MM/dd HH:mm:ss}' in formatted:
        # Your specific format: "Wed 2024/01/15 14:30:25"
        date_str = dt.strftime('%a %Y/%m/%d %H:%M:%S')
        formatted = formatted.replace('%d{EEE yyyy/MM/dd HH:mm:ss}', date_str)
    elif '%d' in formatted:
        # Simple date format
        date_str = dt.strftime('%Y-%m-%d %H:%M:%S')
        formatted = formatted.replace('%d', date_str)
    
    # Replace other patterns
    formatted = formatted.replace('%p', level)
    formatted = formatted.replace('%m', message)
    formatted = formatted.replace('%n', '')  # We'll add newline at output
    
    if category:
        formatted = formatted.replace('%c', category)
    if filename:
        formatted = formatted.replace('%F', filename)
    if line:
        formatted = formatted.replace('%L', str(line))
    
    return formatted

def set_logger_level(category: str, level: str) -> Dict[str, Any]:
    """Set the logging level for a specific logger"""
    try:
        logger = get_logger(category)
        numeric_level = LEVEL_MAP.get(level.upper(), logging.INFO)
        logger.setLevel(numeric_level)
        
        return {
            'success': True,
            'result': {
                'category': category,
                'level': level,
                'numeric_level': numeric_level
            }
        }
        
    except Exception as e:
        return {
            'success': False,
            'error': f'Failed to set logger level: {str(e)}'
        }

def check_logger_level(category: str, level: str) -> Dict[str, Any]:
    """
    Check if a logger would log at the given level
    (for is_debug, is_info, etc. methods)
    """
    try:
        logger = get_logger(category)
        numeric_level = LEVEL_MAP.get(level.upper(), logging.INFO)
        would_log = logger.isEnabledFor(numeric_level)
        
        return {
            'success': True,
            'result': {
                'category': category,
                'level': level,
                'would_log': would_log,
                'logger_level': logger.level
            }
        }
        
    except Exception as e:
        return {
            'success': False,
            'error': f'Failed to check logger level: {str(e)}'
        }

def create_appender(name: str, appender_type: str, config: Dict[str, Any] = None) -> Dict[str, Any]:
    """
    Create a logging appender
    
    Args:
        name: Appender name
        appender_type: Type of appender (Screen, File, etc.)
        config: Additional configuration
    """
    try:
        if appender_type == 'Screen':
            # Screen appender - logs to stdout/stderr
            handler = logging.StreamHandler(sys.stderr)
        elif appender_type == 'File':
            # File appender
            filename = config.get('filename', 'application.log') if config else 'application.log'
            handler = logging.FileHandler(filename)
        else:
            # Default to screen
            handler = logging.StreamHandler(sys.stderr)
        
        # Store appender reference
        APPENDERS[name] = {
            'handler': handler,
            'type': appender_type,
            'name': name,
            'config': config or {}
        }
        
        return {
            'success': True,
            'result': {
                'name': name,
                'type': appender_type,
                'created': True
            }
        }
        
    except Exception as e:
        return {
            'success': False,
            'error': f'Failed to create appender: {str(e)}'
        }

def set_appender_layout(name: str, pattern: str) -> Dict[str, Any]:
    """Set the layout pattern for an appender"""
    try:
        if name in APPENDERS:
            appender = APPENDERS[name]
            appender['layout_pattern'] = pattern
            
            # Update formatter
            formatter = logging.Formatter('%(message)s')  # We handle formatting in _format_message
            appender['handler'].setFormatter(formatter)
            
            return {
                'success': True,
                'result': {
                    'name': name,
                    'pattern': pattern
                }
            }
        else:
            return {
                'success': False,
                'error': f'Appender {name} not found'
            }
        
    except Exception as e:
        return {
            'success': False,
            'error': f'Failed to set appender layout: {str(e)}'
        }

def add_appender_to_logger(category: str, appender_name: str) -> Dict[str, Any]:
    """Add an appender to a logger"""
    try:
        logger = get_logger(category)
        
        if appender_name in APPENDERS:
            appender = APPENDERS[appender_name]
            handler = appender['handler']
            
            # Remove existing handlers if this is a replacement
            for existing_handler in logger.handlers[:]:
                if hasattr(existing_handler, '_appender_name') and existing_handler._appender_name == appender_name:
                    logger.removeHandler(existing_handler)
            
            # Mark handler with appender name
            handler._appender_name = appender_name
            logger.addHandler(handler)
            
            return {
                'success': True,
                'result': {
                    'category': category,
                    'appender': appender_name,
                    'added': True
                }
            }
        else:
            return {
                'success': False,
                'error': f'Appender {appender_name} not found'
            }
        
    except Exception as e:
        return {
            'success': False,
            'error': f'Failed to add appender to logger: {str(e)}'
        }

def get_logger_info(category: str) -> Dict[str, Any]:
    """Get information about a logger"""
    try:
        logger = get_logger(category)
        
        handler_info = []
        for handler in logger.handlers:
            handler_info.append({
                'type': type(handler).__name__,
                'level': handler.level,
                'appender_name': getattr(handler, '_appender_name', 'unknown')
            })
        
        return {
            'success': True,
            'result': {
                'category': category,
                'level': logger.level,
                'effective_level': logger.getEffectiveLevel(),
                'handlers': handler_info,
                'handler_count': len(logger.handlers)
            }
        }
        
    except Exception as e:
        return {
            'success': False,
            'error': f'Failed to get logger info: {str(e)}'
        }

def test_logging_patterns() -> Dict[str, Any]:
    """Test various logging patterns from your analysis"""
    try:
        results = {}
        
        # Test standard message
        result1 = log_message('main', 'INFO', 'Application started successfully')
        results['standard_info'] = result1.get('success', False)
        
        # Test debug message with enhanced formatting
        result2 = log_message(
            'main', 'DEBUG', 
            'DEBUG: /path/to/script.pl line:42: Variable value is 123',
            filename='/path/to/script.pl', 
            line=42
        )
        results['enhanced_debug'] = result2.get('success', False)
        
        # Test error message
        result3 = log_message(
            'main', 'ERROR',
            '/path/to/script.pl line:89: Database connection failed',
            filename='/path/to/script.pl',
            line=89
        )
        results['enhanced_error'] = result3.get('success', False)
        
        # Test log