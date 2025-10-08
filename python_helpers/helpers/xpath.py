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
import sys
import tempfile
import pickle
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

# Persistent storage directory for cross-process document sharing
_STORAGE_DIR = os.path.join(tempfile.gettempdir(), 'cpan_xpath_storage')

def _ensure_storage_dir():
    """Ensure persistent storage directory exists"""
    if not os.path.exists(_STORAGE_DIR):
        os.makedirs(_STORAGE_DIR, mode=0o700)

def _get_document_file(document_id: str) -> str:
    """Get file path for document metadata"""
    _ensure_storage_dir()
    return os.path.join(_STORAGE_DIR, f'doc_{document_id}.pkl')

def _get_node_file(node_id: str) -> str:
    """Get file path for node metadata"""
    _ensure_storage_dir()
    return os.path.join(_STORAGE_DIR, f'node_{node_id}.pkl')

def _save_node_metadata(node_id: str, metadata: Dict[str, Any]) -> None:
    """Save node metadata to persistent storage"""
    try:
        file_path = _get_node_file(node_id)
        with open(file_path, 'wb') as f:
            pickle.dump(metadata, f)
    except Exception as e:
        if _is_debug_mode():
            print(f"Warning: Could not save node metadata: {e}", file=sys.stderr)

def _load_node_metadata(node_id: str) -> Optional[Dict[str, Any]]:
    """Load node metadata from persistent storage"""
    try:
        file_path = _get_node_file(node_id)
        if os.path.exists(file_path):
            with open(file_path, 'rb') as f:
                return pickle.load(f)
    except Exception as e:
        if _is_debug_mode():
            print(f"Warning: Could not load node metadata: {e}", file=sys.stderr)
    return None

def _restore_node(node_id: str) -> bool:
    """Restore node from persistent storage"""
    metadata = _load_node_metadata(node_id)
    if not metadata:
        return False

    try:
        document_id = metadata['document_id']

        # Ensure document is loaded
        if document_id not in _documents:
            if not _restore_document(document_id):
                return False

        # Recreate node from XPath
        doc = _documents[document_id]
        tree = doc['tree']

        # Use the stored XPath to find the element again
        xpath_to_node = metadata['xpath_to_node']
        elements = tree.xpath(xpath_to_node)

        if not elements:
            return False

        # Take the first matching element (should be unique)
        element = elements[0]

        # Recreate node data
        node_data = _process_node(element, document_id)

        # Restore with same node_id
        _nodes[node_id] = {
            'element': element,
            'document_id': document_id,
            'data': node_data
        }

        return True
    except Exception:
        return False

def _save_document_metadata(document_id: str, metadata: Dict[str, Any]) -> None:
    """Save document metadata to persistent storage"""
    try:
        file_path = _get_document_file(document_id)
        with open(file_path, 'wb') as f:
            pickle.dump(metadata, f)
    except Exception as e:
        if _is_debug_mode():
            print(f"Warning: Could not save document metadata: {e}", file=sys.stderr)

def _load_document_metadata(document_id: str) -> Optional[Dict[str, Any]]:
    """Load document metadata from persistent storage"""
    try:
        file_path = _get_document_file(document_id)
        if os.path.exists(file_path):
            with open(file_path, 'rb') as f:
                return pickle.load(f)
    except Exception as e:
        if _is_debug_mode():
            print(f"Warning: Could not load document metadata: {e}", file=sys.stderr)
    return None

def _remove_document_metadata(document_id: str) -> None:
    """Remove document metadata from persistent storage"""
    try:
        file_path = _get_document_file(document_id)
        if os.path.exists(file_path):
            os.remove(file_path)
    except Exception as e:
        if _is_debug_mode():
            print(f"Warning: Could not remove document metadata: {e}", file=sys.stderr)

def _restore_document(document_id: str) -> bool:
    """Restore document from persistent storage"""
    metadata = _load_document_metadata(document_id)
    if not metadata:
        return False

    try:
        # Reload XML from source
        if 'filename' in metadata:
            tree = etree.parse(metadata['filename'])
        elif 'xml_string' in metadata:
            root = etree.fromstring(metadata['xml_string'].encode('utf-8'))
            tree = etree.ElementTree(root)
        else:
            return False

        # Restore to in-memory cache
        _documents[document_id] = {
            'tree': tree,
            'filename': metadata.get('filename'),
            'source': metadata.get('source', 'file'),
            'root': tree.getroot()
        }
        return True
    except Exception:
        return False

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

        # Store document in memory
        _documents[document_id] = {
            'tree': tree,
            'filename': filename,
            'root': tree.getroot()
        }

        # Save metadata to persistent storage for cross-process access
        _save_document_metadata(document_id, {
            'filename': filename,
            'source': 'file'
        })

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

def load_xml_string(xml_string: str) -> Dict[str, Any]:
    """
    Load XML from string and return document ID for subsequent operations

    Matches: XML::XPath->new(xml => $xml_string)
    Used in: Informatica_30166.pm for parsing workflow log XML

    Args:
        xml_string: XML content as string

    Returns:
        Dict containing success status and document_id
    """
    try:
        if not LXML_AVAILABLE:
            raise ImportError("lxml library not available - install with: pip install lxml")

        if not xml_string or not isinstance(xml_string, str):
            raise ValueError("XML string must be a non-empty string")

        if not xml_string.strip():
            raise ValueError("Empty XML string provided")

        # Parse XML string with lxml
        try:
            # Handle both bytes and string input
            if isinstance(xml_string, bytes):
                root = etree.fromstring(xml_string)
            else:
                root = etree.fromstring(xml_string.encode('utf-8'))
            tree = etree.ElementTree(root)
        except etree.XMLSyntaxError as e:
            raise ValueError(f"XML syntax error in string: {str(e)}")

        # Generate unique document ID
        document_id = str(uuid.uuid4())

        # Store document in memory
        _documents[document_id] = {
            'tree': tree,
            'source': 'string',
            'root': tree.getroot()
        }

        # Save metadata to persistent storage for cross-process access
        # Store the XML string so we can reload the document if needed
        _save_document_metadata(document_id, {
            'xml_string': xml_string,
            'source': 'string'
        })

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
        # Try to restore document if not in memory
        if document_id not in _documents:
            if not _restore_document(document_id):
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
        # Try to restore node if not in memory
        if node_id not in _nodes:
            if not _restore_node(node_id):
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
        # Clean up in-memory document
        if document_id in _documents:
            del _documents[document_id]

        # Clean up associated nodes
        nodes_to_remove = [
            nid for nid, node_info in _nodes.items()
            if node_info['document_id'] == document_id
        ]
        for nid in nodes_to_remove:
            del _nodes[nid]

        # Clean up persistent storage
        _remove_document_metadata(document_id)

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

    # Generate XPath to this specific element for persistence
    # Use getroottree().getpath() to get a unique XPath
    xpath_to_node = element.getroottree().getpath(element) if hasattr(element, 'getroottree') else None

    node_data = {
        'name': name,
        'value': text_content,
        'attributes': attributes,
        'node_id': node_id
    }

    # Store node for later reference (in-memory)
    _nodes[node_id] = {
        'element': element,
        'document_id': document_id,
        'data': node_data
    }

    # Save node metadata to persistent storage for cross-process access
    if xpath_to_node:
        _save_node_metadata(node_id, {
            'document_id': document_id,
            'xpath_to_node': xpath_to_node,
            'name': name,
            'attributes': attributes
        })

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