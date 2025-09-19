#!/usr/bin/env python3
"""
helpers/xml_helper.py - Production-ready XML processing for XMLHelper.pm

Provides XML parsing and generation functionality that matches XML::Simple behavior
for use in the RHEL 9 migration project.
"""

import xml.etree.ElementTree as ET
import re
import os
import sys
from typing import Dict, Any, Union, Optional
import traceback

def xml_in(source: str, source_type: str = 'auto', options: Dict[str, Any] = None) -> Dict[str, Any]:
    """
    Parse XML from various sources into Perl-compatible data structures
    
    Args:
        source: XML content, file path, or URL
        source_type: 'string', 'file', 'url', 'filehandle', or 'auto'
        options: XML::Simple compatible options
    
    Returns:
        Dict containing success status and parsed data or error message
    """
    try:
        if options is None:
            options = {}
            
        # Auto-detect source type if not specified
        if source_type == 'auto':
            source_type = _detect_source_type(source)
        
        # Get XML content based on source type
        xml_content = _get_xml_content(source, source_type)
        
        # Parse XML
        root = ET.fromstring(xml_content)
        
        # Convert to Perl-compatible dict structure
        result = _xml_element_to_dict(root, options)
        
        # Handle KeepRoot option (XML::Simple compatibility)
        keep_root = options.get('KeepRoot', 1)
        if not keep_root:
            # Remove the root element wrapper
            if isinstance(result, dict) and len(result) == 1:
                result = list(result.values())[0]
        
        return {
            'success': True,
            'result': result
        }
        
    except ET.ParseError as e:
        return {
            'success': False,
            'error': f"XML Parse Error: {str(e)}",
            'error_type': 'ParseError'
        }
    except FileNotFoundError as e:
        return {
            'success': False,
            'error': f"File not found: {str(e)}",
            'error_type': 'FileNotFoundError'
        }
    except PermissionError as e:
        return {
            'success': False,
            'error': f"Permission denied: {str(e)}",
            'error_type': 'PermissionError'
        }
    except Exception as e:
        return {
            'success': False,
            'error': f"Unexpected error: {str(e)}",
            'error_type': type(e).__name__,
            'traceback': traceback.format_exc() if _is_debug_mode() else None
        }

def xml_out(data: Any, options: Dict[str, Any] = None) -> Dict[str, Any]:
    """
    Convert Perl data structure to XML string
    
    Args:
        data: Perl data structure to convert
        options: XML::Simple compatible options
    
    Returns:
        Dict containing success status and XML string or error message
    """
    try:
        if options is None:
            options = {}
            
        # Get root element name
        root_name = options.get('RootName', 'opt')
        
        # Create root element
        root = ET.Element(root_name)
        
        # Convert data to XML elements
        _dict_to_xml_element(data, root, options)
        
        # Convert to string
        xml_str = ET.tostring(root, encoding='unicode', method='xml')
        
        # Add XML declaration if requested
        if options.get('XMLDecl', False):
            xml_str = '<?xml version="1.0" encoding="UTF-8"?>\n' + xml_str
        
        return {
            'success': True,
            'result': xml_str
        }
        
    except Exception as e:
        return {
            'success': False,
            'error': f"XML generation error: {str(e)}",
            'error_type': type(e).__name__,
            'traceback': traceback.format_exc() if _is_debug_mode() else None
        }

def escape_xml(value: str) -> Dict[str, Any]:
    """
    Escape XML special characters
    """
    try:
        if not isinstance(value, str):
            value = str(value)
        
        # XML character escaping
        value = value.replace('&', '&amp;')
        value = value.replace('<', '&lt;')
        value = value.replace('>', '&gt;')
        value = value.replace('"', '&quot;')
        value = value.replace("'", '&apos;')
        
        return {
            'success': True,
            'result': value
        }
    except Exception as e:
        return {
            'success': False,
            'error': str(e)
        }

def unescape_xml(value: str) -> Dict[str, Any]:
    """
    Unescape XML special characters
    """
    try:
        if not isinstance(value, str):
            value = str(value)
        
        # XML character unescaping
        value = value.replace('&lt;', '<')
        value = value.replace('&gt;', '>')
        value = value.replace('&quot;', '"')
        value = value.replace('&apos;', "'")
        value = value.replace('&amp;', '&')  # Must be last
        
        return {
            'success': True,
            'result': value
        }
    except Exception as e:
        return {
            'success': False,
            'error': str(e)
        }

# Private helper functions

def _detect_source_type(source: str) -> str:
    """Auto-detect the type of XML source"""
    if not isinstance(source, str):
        return 'unknown'
    
    # Check for XML content (starts with < possibly after whitespace)
    if re.match(r'^\s*<', source):
        return 'string'
    
    # Check for URL
    if source.startswith(('http://', 'https://')):
        return 'url'
    
    # Assume file path
    return 'file'

def _get_xml_content(source: str, source_type: str) -> str:
    """Get XML content from various source types"""
    if source_type == 'string':
        return source
    
    elif source_type == 'file':
        # Validate file exists and is readable
        if not os.path.exists(source):
            raise FileNotFoundError(f"XML file not found: {source}")
        
        if not os.access(source, os.R_OK):
            raise PermissionError(f"Cannot read XML file: {source}")
        
        # Read file with proper encoding handling
        try:
            with open(source, 'r', encoding='utf-8') as f:
                return f.read()
        except UnicodeDecodeError:
            # Fallback to latin1 if UTF-8 fails
            with open(source, 'r', encoding='latin1') as f:
                return f.read()
    
    elif source_type == 'url':
        raise NotImplementedError("URL fetching not implemented - use LWP replacement instead")
    
    elif source_type == 'filehandle':
        raise NotImplementedError("Filehandle input not implemented in bridge mode")
    
    else:
        raise ValueError(f"Unknown source type: {source_type}")

def _xml_element_to_dict(element: ET.Element, options: Dict[str, Any]) -> Union[Dict, str, list]:
    """
    Convert XML element to Perl-compatible dict structure
    
    This function replicates XML::Simple's conversion logic:
    - Elements with only text become strings
    - Elements with children become dicts
    - Multiple elements with same name become arrays
    - Attributes are included with @ prefix (if not suppressed)
    """
    result = {}
    
    # Handle attributes
    if element.attrib and not options.get('SuppressEmpty'):
        for attr_name, attr_value in element.attrib.items():
            # Use @ prefix for attributes (XML::Simple style)
            result[f'@{attr_name}'] = attr_value
    
    # Group child elements by tag name
    children_by_tag = {}
    for child in element:
        tag = child.tag
        if tag not in children_by_tag:
            children_by_tag[tag] = []
        children_by_tag[tag].append(child)
    
    # Process child elements
    for tag, children in children_by_tag.items():
        if len(children) == 1:
            # Single child - convert to dict/string
            child_result = _xml_element_to_dict(children[0], options)
            result[tag] = child_result
        else:
            # Multiple children with same tag - create array
            child_array = []
            for child in children:
                child_result = _xml_element_to_dict(child, options)
                child_array.append(child_result)
            result[tag] = child_array
    
    # Handle text content
    text_content = element.text
    if text_content and text_content.strip():
        text_content = text_content.strip()
        
        if result:
            # Element has both text and children/attributes
            # Use 'content' key for text (XML::Simple behavior)
            result['content'] = text_content
        else:
            # Element has only text content
            return text_content
    
    # Handle empty elements
    if not result:
        suppress_empty = options.get('SuppressEmpty')
        if suppress_empty == '':
            return ''
        elif suppress_empty is None:
            return None
        elif suppress_empty == 1:
            return {}
        else:
            return {}
    
    return result

def _dict_to_xml_element(data: Any, parent: ET.Element, options: Dict[str, Any]) -> None:
    """Convert Perl data structure to XML elements"""
    
    if isinstance(data, dict):
        for key, value in data.items():
            if key.startswith('@'):
                # Attribute
                attr_name = key[1:]  # Remove @ prefix
                parent.set(attr_name, str(value))
            elif key == 'content':
                # Text content
                if parent.text is None:
                    parent.text = str(value)
                else:
                    parent.text += str(value)
            else:
                # Child element
                if isinstance(value, list):
                    # Multiple elements with same name
                    for item in value:
                        child = ET.SubElement(parent, key)
                        _dict_to_xml_element(item, child, options)
                else:
                    # Single element
                    child = ET.SubElement(parent, key)
                    _dict_to_xml_element(value, child, options)
    
    elif isinstance(data, list):
        # Handle list at root level
        for item in data:
            _dict_to_xml_element(item, parent, options)
    
    else:
        # Scalar value - set as text content
        if parent.text is None:
            parent.text = str(data) if data is not None else ''
        else:
            parent.text += str(data) if data is not None else ''

def _is_debug_mode() -> bool:
    """Check if debug mode is enabled"""
    return os.environ.get('CPAN_BRIDGE_DEBUG', '0') != '0'

# Test functions for development
def _test_basic_parsing():
    """Basic test function for development"""
    test_xml = '''<?xml version="1.0"?>
    <root>
        <item id="1">Value 1</item>
        <item id="2">Value 2</item>
        <data>
            <name>Test</name>
            <value>123</value>
        </data>
    </root>'''
    
    result = xml_in(test_xml, 'string', {})
    print("Test result:", result)
    
    # Test KeepRoot option
    result_no_root = xml_in(test_xml, 'string', {'KeepRoot': 0})
    print("Test result (no root):", result_no_root)

if __name__ == "__main__":
    # Run basic tests if called directly
    _test_basic_parsing()