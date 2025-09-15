#!/usr/bin/env python3
"""
helpers/xpath.py - Production-ready XPath processing using lxml

Provides full XPath 1.0 support for XPathHelper.pm using the lxml library.
Handles all XPath expressions found in the codebase analysis.

Dependencies: lxml (pip install lxml)
"""

import uuid
import traceback
import os
from typing import Dict, Any, List, Optional

try:
    from lxml import etree
    LXML_AVAILABLE = True
except ImportError:
    LXML_AVAILABLE = False
    etree = None

# Global document storage for managing XML documents across calls
_documents = {}
_nodes = {}

def load_file(filename: str) -> Dict[str, Any]:
    """
    Load XML file and return document ID for subsequent operations
    
    Matches: XML::XPath->new(filename => $file)
    
    Args:
        filename: Path to XML file
        
    Returns:
        Dict containing success status and document_id
    """
    try:
        if not LXML_AVAILABLE:
            raise ImportError("lxml library not available - install with: pip install lxml")
        
        if not os.path.exists(filename):
            raise FileNotFoundError(f"XML file not found: {filename}")
        
        if not os.access(filename, os.R_OK):
            raise PermissionError(f"Cannot read XML file: {filename}")
        
        # Parse XML file with lxml
        try:
            tree = etree.parse(filename)
        except etree.XMLSyntaxError as e:
            raise ValueError(f"XML syntax error in {filename}: {str(e)}")
        
        # Generate unique document ID
        document_id = str(uuid.uuid4())
        
        # Store document
        _documents[document_id] = {
            'tree': tree,
            'filename': filename,
            'root': tree.getroot()
        }
        
        return {
            'success': True,
            'result': {
                'document_id': document_id
            }
        }
        
    except Exception as e:
        return {
            'success': False,
            'error': str(e),
            'error_type': type(e).__name__,
            'traceback': traceback.format_exc() if _is_debug_mode() else None
        }

def find_nodes(document_id: str, xpath: str) -> Dict[str, Any]:
    """
    Execute XPath query on document and return matching nodes
    
    Matches: $xml->find($xpath_expression)
    
    Args:
        document_id: Document identifier from load_file
        xpath: XPath expression to execute
        
    Returns:
        Dict containing success status and node data
    """
    try:
        if document_id not in _documents:
            raise ValueError(f"Document not found: {document_id}")
        
        doc = _documents[document_id]
        tree = doc['tree']
        
        # Execute XPath query
        try:
            nodes = tree.xpath(xpath)
        except etree.XPathEvalError as e:
            raise ValueError(f"Invalid XPath expression '{xpath}': {str(e)}")
        
        # Process results
        node_data = []
        for node in nodes:
            node_info = _process_node(node, document_id)
            if node_info:
                node_data.append(node_info)
        
        return {
            'success': True,
            'result': {
                'nodes': node_data,
                'size': len(node_data)
            }
        }
        
    except Exception as e:
        return {
            'success': False,
            'error': str(e),
            'error_type': type(e).__name__,
            'traceback': traceback.format_exc() if _is_debug_mode() else None
        }

def find_in_node(node_id: str, xpath: str) -> Dict[str, Any]:
    """
    Execute XPath query within a specific node context
    
    Matches: $node->find($xpath_expression)
    
    Args:
        node_id: Node identifier
        xpath: XPath expression relative to the node
        
    Returns:
        Dict containing success status and node data
    """
    try:
        if node_id not in _nodes:
            raise ValueError(f"Node not found: {node_id}")
        
        node_info = _nodes[node_id]
        element = node_info['element']
        
        # Execute XPath query relative to this node
        try:
            nodes = element.xpath(xpath)
        except etree.XPathEvalError as e:
            raise ValueError(f"Invalid XPath expression '{xpath}': {str(e)}")
        
        # Process results
        node_data = []
        for node in nodes:
            node_info = _process_node(node, node_info['document_id'])
            if node_info:
                node_data.append(node_info)
        
        return {
            'success': True,
            'result': {
                'nodes': node_data,
                'size': len(node_data)
            }
        }
        
    except Exception as e:
        return {
            'success': False,
            'error': str(e),
            'error_type': type(e).__name__
        }

def dispose_document(document_id: str) -> Dict[str, Any]:
    """
    Clean up document resources
    
    Args:
        document_id: Document identifier to dispose
        
    Returns:
        Dict containing success status
    """
    try:
        if document_id in _documents:
            del _documents[document_id]
        
        # Clean up associated nodes
        nodes_to_remove = [
            nid for nid, node_info in _nodes.items()
            if node_info['document_id'] == document_id
        ]
        for nid in nodes_to_remove:
            del _nodes[nid]
        
        return {
            'success': True,
            'result': 'Document disposed'
        }
        
    except Exception as e:
        return {
            'success': False,
            'error': str(e),
            'error_type': type(e).__name__
        }

def _process_node(element, document_id: str) -> Optional[Dict[str, Any]]:
    """
    Convert lxml element to node data structure for Perl consumption
    
    Args:
        element: lxml element object
        document_id: Associated document ID
        
    Returns:
        Dict containing node information
    """
    if element is None:
        return None
    
    # Generate unique node ID
    node_id = str(uuid.uuid4())
    
    # Extract element information
    name = element.tag if hasattr(element, 'tag') else ''
    
    # Get text content (matches XML::XPath string_value behavior)
    text_content = ''
    if hasattr(element, 'text') and element.text:
        text_content = element.text.strip()
    
    # If no direct text, get all text content (including from children)
    if not text_content and hasattr(element, 'xpath'):
        try:
            text_nodes = element.xpath('.//text()')
            if text_nodes:
                text_content = ''.join(str(t).strip() for t in text_nodes if str(t).strip())
        except:
            pass
    
    # Get attributes
    attributes = {}
    if hasattr(element, 'attrib'):
        attributes = dict(element.attrib)
    
    node_data = {
        'name': name,
        'value': text_content,
        'attributes': attributes,
        'node_id': node_id
    }
    
    # Store node for later reference
    _nodes[node_id] = {
        'element': element,
        'document_id': document_id,
        'data': node_data
    }
    
    return node_data

def _is_debug_mode() -> bool:
    """Check if debug mode is enabled"""
    return os.environ.get('CPAN_BRIDGE_DEBUG', '0') != '0'

def check_lxml_availability() -> Dict[str, Any]:
    """
    Check if lxml is available and working
    
    Returns:
        Dict containing availability status and version info
    """
    try:
        if not LXML_AVAILABLE:
            return {
                'success': False,
                'error': 'lxml not available - install with: pip install lxml',
                'available': False
            }
        
        # Try to create a simple XML document to test functionality
        root = etree.Element("test")
        tree = etree.ElementTree(root)
        
        # Test XPath functionality
        result = tree.xpath("/test")
        
        return {
            'success': True,
            'result': {
                'available': True,
                'version': getattr(etree, '__version__', 'unknown'),
                'features': {
                    'xpath': True,
                    'xml_parsing': True
                }
            }
        }
        
    except Exception as e:
        return {
            'success': False,
            'error': f"lxml test failed: {str(e)}",
            'available': False
        }

# Test functions for development and validation
def _test_xpath_expressions():
    """Test the XPath expressions found in your codebase"""
    test_xml = '''<?xml version="1.0"?>
    <DocumentMessage>
        <Fax>
            <ToFaxNumber>555-1234</ToFaxNumber>
            <DateTime>2025-01-15T10:30:00</DateTime>
            <Status>Sent</Status>
        </Fax>
        <apps>
            <app name="TestApp">
                <version name="1.0">
                    <dependency>lib1</dependency>
                    <reference>ref1</reference>
                    <vm>java8</vm>
                    <parm>param1</parm>
                </version>
            </app>
        </apps>
    </DocumentMessage>'''
    
    # Create temporary file
    import tempfile
    with tempfile.NamedTemporaryFile(mode='w', suffix='.xml', delete=False) as f:
        f.write(test_xml)
        temp_file = f.name
    
    try:
        # Test loading
        print("Testing XML::XPath expressions...")
        load_result = load_file(temp_file)
        if not load_result['success']:
            print(f"FAIL: Load file: {load_result['error']}")
            return False
        
        doc_id = load_result['result']['document_id']
        
        # Test your actual XPath expressions
        test_expressions = [
            "/DocumentMessage/Fax/*",
            "//apps/app[@name='TestApp']",
            "//version[@name='1.0']",
            "dependency",
            "reference", 
            "vm",
            "parm"
        ]
        
        for xpath in test_expressions:
            result = find_nodes(doc_id, xpath)
            if result['success']:
                print(f"PASS: {xpath} -> {result['result']['size']} nodes")
            else:
                print(f"FAIL: {xpath} -> {result['error']}")
        
        # Clean up
        dispose_document(doc_id)
        os.unlink(temp_file)
        
        print("XPath expression tests complete")
        return True
        
    except Exception as e:
        print(f"Test failed: {e}")
        return False

if __name__ == "__main__":
    # Run tests when called directly
    print("XPathHelper Test Suite")
    print("=" * 40)
    
    # Check lxml availability
    lxml_check = check_lxml_availability()
    if lxml_check['success']:
        print("✓ lxml available and working")
        print(f"  Version: {lxml_check['result']['version']}")
        
        # Run XPath tests
        print()
        _test_xpath_expressions()
    else:
        print("✗ lxml not available")
        print(f"  Error: {lxml_check['error']}")
        print("  Install with: pip install lxml")