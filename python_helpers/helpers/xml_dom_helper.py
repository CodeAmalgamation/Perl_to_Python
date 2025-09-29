#!/usr/bin/env python3
"""
xml_dom_helper.py - XML::DOM replacement using Python XML processing

Provides comprehensive DOM functionality matching XML::DOM usage patterns.
Supports full document object model with parsing, navigation, modification,
and XPath/XQL integration.
"""

import xml.etree.ElementTree as ET
from xml.dom import minidom
import uuid
import time
import copy
import traceback
from typing import Dict, Any, List, Optional, Union
import os
import re

try:
    # Try to import lxml for advanced XPath support
    from lxml import etree
    LXML_AVAILABLE = True
except ImportError:
    LXML_AVAILABLE = False

# Global storage for documents, nodes, and parsers
DOCUMENTS = {}
NODES = {}
PARSERS = {}
NODE_LISTS = {}

# Configuration
DEBUG_MODE = False

def _debug(message: str):
    """Debug logging helper"""
    if DEBUG_MODE:
        print(f"[XML_DOM_DEBUG] {message}")

def _generate_id() -> str:
    """Generate unique identifier"""
    return str(uuid.uuid4())

class XMLDOMException(Exception):
    """Base exception for XML DOM operations"""
    pass

class ParseException(XMLDOMException):
    """XML parsing errors"""
    pass

class NodeException(XMLDOMException):
    """Node operation errors"""
    pass

# ============================================================================
# PARSER FUNCTIONALITY
# ============================================================================

def create_parser(**options) -> Dict[str, Any]:
    """
    Create XML parser instance (matches XML::DOM::Parser->new())

    Args:
        **options: Parser configuration options

    Returns:
        Dictionary with parser instance information
    """
    try:
        parser_id = _generate_id()

        parser_config = {
            'parser_id': parser_id,
            'options': options,
            'created_at': time.time()
        }

        PARSERS[parser_id] = parser_config
        _debug(f"Created parser: {parser_id}")

        return {
            'success': True,
            'result': {
                'parser_id': parser_id,
                'options': options
            }
        }

    except Exception as e:
        return {
            'success': False,
            'error': f'Failed to create parser: {str(e)}'
        }

def parse_string(parser_id: str, xml_string: str) -> Dict[str, Any]:
    """
    Parse XML from string (matches $parser->parse($xml))

    Args:
        parser_id: Parser instance ID
        xml_string: XML content as string

    Returns:
        Dictionary with document information
    """
    try:
        if parser_id not in PARSERS:
            return {
                'success': False,
                'error': 'Invalid parser ID'
            }

        # Parse XML using ElementTree
        root = ET.fromstring(xml_string)

        # Create document representation
        document_id = _generate_id()
        document = {
            'document_id': document_id,
            'root_element': root,
            'xml_string': xml_string,
            'parser_id': parser_id,
            'created_at': time.time()
        }

        DOCUMENTS[document_id] = document

        # Create root node reference
        root_node_id = _create_node_reference(root, document_id)

        _debug(f"Parsed XML document: {document_id}")

        return {
            'success': True,
            'result': {
                'document_id': document_id,
                'root_node_id': root_node_id
            }
        }

    except ET.ParseError as e:
        return {
            'success': False,
            'error': f'XML parsing failed: {str(e)}'
        }
    except Exception as e:
        return {
            'success': False,
            'error': f'Unexpected error during parsing: {str(e)}'
        }

def parse_file(parser_id: str, filename: str) -> Dict[str, Any]:
    """
    Parse XML from file (matches $parser->parsefile($file))

    Args:
        parser_id: Parser instance ID
        filename: Path to XML file

    Returns:
        Dictionary with document information
    """
    try:
        if parser_id not in PARSERS:
            return {
                'success': False,
                'error': 'Invalid parser ID'
            }

        if not os.path.exists(filename):
            return {
                'success': False,
                'error': f'File not found: {filename}'
            }

        # Read file content
        with open(filename, 'r', encoding='utf-8') as f:
            xml_string = f.read()

        # Use parse_string for actual parsing
        result = parse_string(parser_id, xml_string)

        if result['success']:
            # Add filename to document info
            document_id = result['result']['document_id']
            DOCUMENTS[document_id]['filename'] = filename

        return result

    except Exception as e:
        return {
            'success': False,
            'error': f'File parsing failed: {str(e)}'
        }

# ============================================================================
# NODE MANAGEMENT
# ============================================================================

def _create_node_reference(element: ET.Element, document_id: str) -> str:
    """
    Create a reference to an XML element node

    Args:
        element: ElementTree element
        document_id: Parent document ID

    Returns:
        Unique node ID
    """
    node_id = _generate_id()

    node_info = {
        'node_id': node_id,
        'element': element,
        'document_id': document_id,
        'created_at': time.time()
    }

    NODES[node_id] = node_info
    return node_id

def _get_node(node_id: str) -> Optional[ET.Element]:
    """Get ElementTree element by node ID"""
    if node_id in NODES:
        return NODES[node_id]['element']
    return None

def _get_document(document_id: str) -> Optional[Dict]:
    """Get document by document ID"""
    return DOCUMENTS.get(document_id)

# ============================================================================
# DOM NAVIGATION
# ============================================================================

def get_elements_by_tag_name(document_id: str, tag_name: str) -> Dict[str, Any]:
    """
    Find all elements with specified tag name (matches getElementsByTagName)

    Args:
        document_id: Document to search
        tag_name: Tag name to find

    Returns:
        Dictionary with NodeList information
    """
    try:
        document = _get_document(document_id)
        if not document:
            return {
                'success': False,
                'error': 'Invalid document ID'
            }

        root = document['root_element']
        matching_elements = []

        # Find all elements with matching tag name
        for elem in root.iter(tag_name):
            node_id = _create_node_reference(elem, document_id)
            matching_elements.append(node_id)

        # Create NodeList
        nodelist_id = _create_node_list(matching_elements)

        _debug(f"Found {len(matching_elements)} elements with tag '{tag_name}'")

        return {
            'success': True,
            'result': {
                'nodelist_id': nodelist_id,
                'node_ids': matching_elements,
                'length': len(matching_elements)
            }
        }

    except Exception as e:
        return {
            'success': False,
            'error': f'getElementsByTagName failed: {str(e)}'
        }

def get_elements_by_tag_name_from_node(node_id: str, tag_name: str) -> Dict[str, Any]:
    """
    Find all elements with specified tag name starting from a specific node

    Args:
        node_id: Starting node for search
        tag_name: Tag name to find

    Returns:
        Dictionary with NodeList information
    """
    try:
        node = _get_node(node_id)
        if node is None:
            return {
                'success': False,
                'error': 'Invalid node ID'
            }

        node_info = NODES[node_id]
        document_id = node_info['document_id']
        matching_elements = []

        # Find all elements with matching tag name under this node
        for elem in node.iter(tag_name):
            node_ref_id = _create_node_reference(elem, document_id)
            matching_elements.append(node_ref_id)

        # Create NodeList
        nodelist_id = _create_node_list(matching_elements)

        _debug(f"Found {len(matching_elements)} elements with tag '{tag_name}' under node")

        return {
            'success': True,
            'result': {
                'nodelist_id': nodelist_id,
                'node_ids': matching_elements,
                'length': len(matching_elements)
            }
        }

    except Exception as e:
        return {
            'success': False,
            'error': f'getElementsByTagName from node failed: {str(e)}'
        }

def get_child_nodes(node_id: str) -> Dict[str, Any]:
    """
    Get all child nodes (matches getChildNodes())

    Args:
        node_id: Parent node ID

    Returns:
        Dictionary with child node information
    """
    try:
        node = _get_node(node_id)
        if node is None:
            return {
                'success': False,
                'error': 'Invalid node ID'
            }

        node_info = NODES[node_id]
        document_id = node_info['document_id']
        child_node_ids = []

        # Create references for all child elements
        for child in node:
            child_id = _create_node_reference(child, document_id)
            child_node_ids.append(child_id)

        # Create NodeList for children
        nodelist_id = _create_node_list(child_node_ids)

        _debug(f"Node has {len(child_node_ids)} child nodes")

        return {
            'success': True,
            'result': {
                'nodelist_id': nodelist_id,
                'node_ids': child_node_ids,
                'length': len(child_node_ids)
            }
        }

    except Exception as e:
        return {
            'success': False,
            'error': f'getChildNodes failed: {str(e)}'
        }

def get_first_child(node_id: str) -> Dict[str, Any]:
    """
    Get first child node (matches getFirstChild())

    Args:
        node_id: Parent node ID

    Returns:
        Dictionary with first child information
    """
    try:
        child_result = get_child_nodes(node_id)
        if not child_result['success']:
            return child_result

        child_ids = child_result['result']['node_ids']
        if not child_ids:
            return {
                'success': True,
                'result': {
                    'node_id': None
                }
            }

        return {
            'success': True,
            'result': {
                'node_id': child_ids[0]
            }
        }

    except Exception as e:
        return {
            'success': False,
            'error': f'getFirstChild failed: {str(e)}'
        }

# ============================================================================
# ATTRIBUTE HANDLING
# ============================================================================

def get_attribute(node_id: str, attr_name: str) -> Dict[str, Any]:
    """
    Get attribute value (matches getAttribute())

    Args:
        node_id: Node ID
        attr_name: Attribute name

    Returns:
        Dictionary with attribute value
    """
    try:
        node = _get_node(node_id)
        if node is None:
            return {
                'success': False,
                'error': 'Invalid node ID'
            }

        attr_value = node.get(attr_name, '')

        return {
            'success': True,
            'result': {
                'value': attr_value
            }
        }

    except Exception as e:
        return {
            'success': False,
            'error': f'getAttribute failed: {str(e)}'
        }

def set_attribute(node_id: str, attr_name: str, value: str) -> Dict[str, Any]:
    """
    Set attribute value (matches setAttribute())

    Args:
        node_id: Node ID
        attr_name: Attribute name
        value: Attribute value

    Returns:
        Success status
    """
    try:
        node = _get_node(node_id)
        if node is None:
            return {
                'success': False,
                'error': 'Invalid node ID'
            }

        node.set(attr_name, str(value))

        return {
            'success': True,
            'result': {
                'attribute': attr_name,
                'value': str(value)
            }
        }

    except Exception as e:
        return {
            'success': False,
            'error': f'setAttribute failed: {str(e)}'
        }

def has_attribute(node_id: str, attr_name: str) -> Dict[str, Any]:
    """
    Check if attribute exists (matches hasAttribute())

    Args:
        node_id: Node ID
        attr_name: Attribute name

    Returns:
        Dictionary with boolean result
    """
    try:
        node = _get_node(node_id)
        if node is None:
            return {
                'success': False,
                'error': 'Invalid node ID'
            }

        has_attr = attr_name in node.attrib

        return {
            'success': True,
            'result': {
                'has_attribute': has_attr
            }
        }

    except Exception as e:
        return {
            'success': False,
            'error': f'hasAttribute failed: {str(e)}'
        }

# ============================================================================
# TEXT CONTENT EXTRACTION
# ============================================================================

def get_text_contents(node_id: str, trim: bool = False) -> Dict[str, Any]:
    """
    Extract text content from node and children (matches getTextContents pattern)

    Args:
        node_id: Node ID
        trim: Whether to trim whitespace

    Returns:
        Dictionary with text content
    """
    try:
        node = _get_node(node_id)
        if node is None:
            return {
                'success': False,
                'error': 'Invalid node ID'
            }

        def extract_text(element):
            """Recursively extract all text content"""
            text = ""

            # Add element's text
            if element.text:
                text += element.text

            # Add text from all children
            for child in element:
                text += extract_text(child)
                # Add tail text after child
                if child.tail:
                    text += child.tail

            return text

        content = extract_text(node)

        if trim:
            content = content.strip()

        return {
            'success': True,
            'result': {
                'text_content': content
            }
        }

    except Exception as e:
        return {
            'success': False,
            'error': f'getTextContents failed: {str(e)}'
        }

def get_node_value(node_id: str) -> Dict[str, Any]:
    """
    Get node's direct text value (matches getNodeValue())

    Args:
        node_id: Node ID

    Returns:
        Dictionary with node value
    """
    try:
        node = _get_node(node_id)
        if node is None:
            return {
                'success': False,
                'error': 'Invalid node ID'
            }

        # For element nodes, return text content
        value = node.text if node.text else ""

        return {
            'success': True,
            'result': {
                'value': value
            }
        }

    except Exception as e:
        return {
            'success': False,
            'error': f'getNodeValue failed: {str(e)}'
        }

def is_element_node(node_id: str) -> Dict[str, Any]:
    """
    Check if node is an element node (matches isElementNode())

    Args:
        node_id: Node ID

    Returns:
        Dictionary with boolean result
    """
    try:
        node = _get_node(node_id)
        if node is None:
            return {
                'success': False,
                'error': 'Invalid node ID'
            }

        # In ElementTree, all nodes we handle are element nodes
        is_element = True

        return {
            'success': True,
            'result': {
                'is_element': is_element
            }
        }

    except Exception as e:
        return {
            'success': False,
            'error': f'isElementNode failed: {str(e)}'
        }

# ============================================================================
# NODE LIST MANAGEMENT
# ============================================================================

def _create_node_list(node_ids: List[str]) -> str:
    """
    Create a NodeList container for multiple nodes

    Args:
        node_ids: List of node IDs

    Returns:
        NodeList ID
    """
    nodelist_id = _generate_id()

    nodelist_info = {
        'nodelist_id': nodelist_id,
        'node_ids': node_ids,
        'length': len(node_ids),
        'created_at': time.time()
    }

    NODE_LISTS[nodelist_id] = nodelist_info
    return nodelist_id

def get_nodelist_length(nodelist_id: str) -> Dict[str, Any]:
    """
    Get length of NodeList (matches getLength())

    Args:
        nodelist_id: NodeList ID

    Returns:
        Dictionary with length
    """
    try:
        if nodelist_id not in NODE_LISTS:
            return {
                'success': False,
                'error': 'Invalid NodeList ID'
            }

        nodelist = NODE_LISTS[nodelist_id]

        return {
            'success': True,
            'result': {
                'length': nodelist['length']
            }
        }

    except Exception as e:
        return {
            'success': False,
            'error': f'getLength failed: {str(e)}'
        }

def get_nodelist_item(nodelist_id: str, index: int) -> Dict[str, Any]:
    """
    Get item from NodeList at index (matches item())

    Args:
        nodelist_id: NodeList ID
        index: Index position

    Returns:
        Dictionary with node information
    """
    try:
        if nodelist_id not in NODE_LISTS:
            return {
                'success': False,
                'error': 'Invalid NodeList ID'
            }

        nodelist = NODE_LISTS[nodelist_id]

        if index < 0 or index >= nodelist['length']:
            return {
                'success': True,
                'result': {
                    'node_id': None
                }
            }

        node_id = nodelist['node_ids'][index]

        return {
            'success': True,
            'result': {
                'node_id': node_id
            }
        }

    except Exception as e:
        return {
            'success': False,
            'error': f'item failed: {str(e)}'
        }

# ============================================================================
# MEMORY MANAGEMENT
# ============================================================================

def get_document_root(document_id: str) -> Dict[str, Any]:
    """
    Get the root element of a document

    Args:
        document_id: Document ID

    Returns:
        Dictionary with root element node ID
    """
    try:
        if document_id not in DOCUMENTS:
            return {
                'success': False,
                'error': 'Document not found'
            }

        # Get document root element
        document_root = DOCUMENTS[document_id]['root']

        # Create node reference for root element
        root_node_id = _create_node_reference(document_root, document_id)

        return {
            'success': True,
            'result': {
                'root_node_id': root_node_id
            }
        }

    except Exception as e:
        return {
            'success': False,
            'error': f'get_document_root failed: {str(e)}'
        }

def dispose_document(document_id: str) -> Dict[str, Any]:
    """
    Clean up document resources (matches dispose())

    Args:
        document_id: Document ID

    Returns:
        Success status
    """
    try:
        if document_id in DOCUMENTS:
            del DOCUMENTS[document_id]

        # Clean up associated nodes
        nodes_to_remove = []
        for node_id, node_info in NODES.items():
            if node_info['document_id'] == document_id:
                nodes_to_remove.append(node_id)

        for node_id in nodes_to_remove:
            del NODES[node_id]

        _debug(f"Disposed document: {document_id}")

        return {
            'success': True,
            'result': {
                'disposed': True,
                'nodes_cleaned': len(nodes_to_remove)
            }
        }

    except Exception as e:
        return {
            'success': False,
            'error': f'dispose failed: {str(e)}'
        }

def dispose_node(node_id: str) -> Dict[str, Any]:
    """
    Clean up node resources

    Args:
        node_id: Node ID

    Returns:
        Success status
    """
    try:
        if node_id in NODES:
            del NODES[node_id]

        return {
            'success': True,
            'result': {
                'disposed': True
            }
        }

    except Exception as e:
        return {
            'success': False,
            'error': f'dispose node failed: {str(e)}'
        }

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

def get_tag_name(node_id: str) -> Dict[str, Any]:
    """
    Get tag name of element node

    Args:
        node_id: Node ID

    Returns:
        Dictionary with tag name
    """
    try:
        node = _get_node(node_id)
        if node is None:
            return {
                'success': False,
                'error': 'Invalid node ID'
            }

        return {
            'success': True,
            'result': {
                'tag_name': node.tag
            }
        }

    except Exception as e:
        return {
            'success': False,
            'error': f'getTagName failed: {str(e)}'
        }

# ============================================================================
# MODULE INFO
# ============================================================================

def get_module_info() -> Dict[str, Any]:
    """Get module information and statistics"""
    return {
        'success': True,
        'result': {
            'module': 'xml_dom_helper',
            'version': '1.0.0',
            'lxml_available': LXML_AVAILABLE,
            'active_documents': len(DOCUMENTS),
            'active_nodes': len(NODES),
            'active_parsers': len(PARSERS),
            'active_nodelists': len(NODE_LISTS)
        }
    }

# ============================================================================
# DOM MODIFICATION FUNCTIONS (Phase 2)
# ============================================================================

def create_element(document_id: str, tag_name: str) -> Dict[str, Any]:
    """
    Create a new element node

    Args:
        document_id: Parent document ID
        tag_name: Name of the element to create

    Returns:
        Dictionary with new element node ID
    """
    try:
        if not document_id or not tag_name:
            return {
                'success': False,
                'error': 'Document ID and tag name are required'
            }

        # Validate tag name
        if not re.match(r'^[a-zA-Z][a-zA-Z0-9_-]*$', tag_name):
            return {
                'success': False,
                'error': f'Invalid tag name: {tag_name}'
            }

        # Create new element
        new_element = ET.Element(tag_name)

        # Create node reference and store it
        node_id = _create_node_reference(new_element, document_id)

        return {
            'success': True,
            'result': {
                'node_id': node_id
            }
        }

    except Exception as e:
        return {
            'success': False,
            'error': f'createElement failed: {str(e)}'
        }

def create_text_node(document_id: str, data: str) -> Dict[str, Any]:
    """
    Create a text node

    Args:
        document_id: Parent document ID
        data: Text content

    Returns:
        Dictionary with new text node ID
    """
    try:
        if not document_id:
            return {
                'success': False,
                'error': 'Document ID is required'
            }

        # Create element to hold text (ElementTree doesn't have standalone text nodes)
        text_element = ET.Element('_text_node_')
        text_element.text = data or ""

        # Create node reference
        node_id = _create_node_reference(text_element, document_id)

        return {
            'success': True,
            'result': {
                'node_id': node_id
            }
        }

    except Exception as e:
        return {
            'success': False,
            'error': f'createTextNode failed: {str(e)}'
        }

def set_attribute(node_id: str, attr_name: str, value: str) -> Dict[str, Any]:
    """
    Set an attribute on an element

    Args:
        node_id: Element node ID
        attr_name: Attribute name
        value: Attribute value

    Returns:
        Dictionary with success status
    """
    try:
        node = _get_node(node_id)
        if node is None:
            return {
                'success': False,
                'error': 'Invalid node ID'
            }

        if not attr_name:
            return {
                'success': False,
                'error': 'Attribute name is required'
            }

        # Set the attribute
        node.set(attr_name, str(value) if value is not None else "")

        return {
            'success': True,
            'result': {}
        }

    except Exception as e:
        return {
            'success': False,
            'error': f'setAttribute failed: {str(e)}'
        }

def has_attribute(node_id: str, attr_name: str) -> Dict[str, Any]:
    """
    Check if element has an attribute

    Args:
        node_id: Element node ID
        attr_name: Attribute name

    Returns:
        Dictionary with boolean result
    """
    try:
        node = _get_node(node_id)
        if node is None:
            return {
                'success': False,
                'error': 'Invalid node ID'
            }

        if not attr_name:
            return {
                'success': True,
                'result': {
                    'has_attribute': False
                }
            }

        has_attr = attr_name in node.attrib

        return {
            'success': True,
            'result': {
                'has_attribute': has_attr
            }
        }

    except Exception as e:
        return {
            'success': False,
            'error': f'hasAttribute failed: {str(e)}'
        }

def remove_attribute(node_id: str, attr_name: str) -> Dict[str, Any]:
    """
    Remove an attribute from an element

    Args:
        node_id: Element node ID
        attr_name: Attribute name

    Returns:
        Dictionary with success status
    """
    try:
        node = _get_node(node_id)
        if node is None:
            return {
                'success': False,
                'error': 'Invalid node ID'
            }

        if not attr_name:
            return {
                'success': True,
                'result': {}
            }

        # Remove attribute if it exists
        if attr_name in node.attrib:
            del node.attrib[attr_name]

        return {
            'success': True,
            'result': {}
        }

    except Exception as e:
        return {
            'success': False,
            'error': f'removeAttribute failed: {str(e)}'
        }

def append_child(parent_id: str, child_id: str) -> Dict[str, Any]:
    """
    Append a child node to a parent element

    Args:
        parent_id: Parent element node ID
        child_id: Child node ID to append

    Returns:
        Dictionary with success status
    """
    try:
        parent = _get_node(parent_id)
        child = _get_node(child_id)

        if parent is None:
            return {
                'success': False,
                'error': 'Invalid parent node ID'
            }

        if child is None:
            return {
                'success': False,
                'error': 'Invalid child node ID'
            }

        # Append child to parent
        parent.append(child)

        return {
            'success': True,
            'result': {}
        }

    except Exception as e:
        return {
            'success': False,
            'error': f'appendChild failed: {str(e)}'
        }

def remove_child(parent_id: str, child_id: str) -> Dict[str, Any]:
    """
    Remove a child node from a parent element

    Args:
        parent_id: Parent element node ID
        child_id: Child node ID to remove

    Returns:
        Dictionary with success status
    """
    try:
        parent = _get_node(parent_id)
        child = _get_node(child_id)

        if parent is None:
            return {
                'success': False,
                'error': 'Invalid parent node ID'
            }

        if child is None:
            return {
                'success': False,
                'error': 'Invalid child node ID'
            }

        # Remove child from parent
        parent.remove(child)

        return {
            'success': True,
            'result': {}
        }

    except Exception as e:
        return {
            'success': False,
            'error': f'removeChild failed: {str(e)}'
        }

def replace_child(parent_id: str, new_child_id: str, old_child_id: str) -> Dict[str, Any]:
    """
    Replace a child node with a new node

    Args:
        parent_id: Parent element node ID
        new_child_id: New child node ID
        old_child_id: Old child node ID to replace

    Returns:
        Dictionary with success status
    """
    try:
        parent = _get_node(parent_id)
        new_child = _get_node(new_child_id)
        old_child = _get_node(old_child_id)

        if parent is None:
            return {
                'success': False,
                'error': 'Invalid parent node ID'
            }

        if new_child is None:
            return {
                'success': False,
                'error': 'Invalid new child node ID'
            }

        if old_child is None:
            return {
                'success': False,
                'error': 'Invalid old child node ID'
            }

        # Find index of old child
        try:
            index = list(parent).index(old_child)
            parent.remove(old_child)
            parent.insert(index, new_child)
        except ValueError:
            return {
                'success': False,
                'error': 'Old child not found in parent'
            }

        return {
            'success': True,
            'result': {}
        }

    except Exception as e:
        return {
            'success': False,
            'error': f'replaceChild failed: {str(e)}'
        }

def insert_before(parent_id: str, new_child_id: str, ref_child_id: str) -> Dict[str, Any]:
    """
    Insert a new child before a reference child

    Args:
        parent_id: Parent element node ID
        new_child_id: New child node ID to insert
        ref_child_id: Reference child node ID (insert before this)

    Returns:
        Dictionary with success status
    """
    try:
        parent = _get_node(parent_id)
        new_child = _get_node(new_child_id)
        ref_child = _get_node(ref_child_id)

        if parent is None:
            return {
                'success': False,
                'error': 'Invalid parent node ID'
            }

        if new_child is None:
            return {
                'success': False,
                'error': 'Invalid new child node ID'
            }

        if ref_child is None:
            return {
                'success': False,
                'error': 'Invalid reference child node ID'
            }

        # Find index of reference child
        try:
            index = list(parent).index(ref_child)
            parent.insert(index, new_child)
        except ValueError:
            return {
                'success': False,
                'error': 'Reference child not found in parent'
            }

        return {
            'success': True,
            'result': {}
        }

    except Exception as e:
        return {
            'success': False,
            'error': f'insertBefore failed: {str(e)}'
        }

def clone_node(node_id: str, deep: bool = False) -> Dict[str, Any]:
    """
    Clone a node (shallow or deep copy)

    Args:
        node_id: Source node ID to clone
        deep: If True, clone all descendants

    Returns:
        Dictionary with cloned node ID
    """
    try:
        source_node = _get_node(node_id)
        if source_node is None:
            return {
                'success': False,
                'error': 'Invalid node ID'
            }

        # Get the document ID from the node info
        node_info = NODES.get(node_id)
        if not node_info:
            return {
                'success': False,
                'error': 'Node information not found'
            }

        document_id = node_info['document_id']

        if deep:
            # Deep copy including all children
            cloned_node = copy.deepcopy(source_node)
        else:
            # Shallow copy - just the element without children
            cloned_node = ET.Element(source_node.tag, source_node.attrib)
            cloned_node.text = source_node.text
            cloned_node.tail = source_node.tail

        # Create new node reference
        cloned_node_id = _create_node_reference(cloned_node, document_id)

        return {
            'success': True,
            'result': {
                'node_id': cloned_node_id
            }
        }

    except Exception as e:
        return {
            'success': False,
            'error': f'cloneNode failed: {str(e)}'
        }

def to_string(document_id: str, indent: str = None) -> Dict[str, Any]:
    """
    Convert document to XML string

    Args:
        document_id: Document ID to serialize
        indent: Indentation for pretty printing (optional)

    Returns:
        Dictionary with XML string
    """
    try:
        document = _get_document(document_id)
        if document is None:
            return {
                'success': False,
                'error': 'Invalid document ID'
            }

        root = document['root_element']

        if indent:
            # Pretty print with indentation
            rough_string = ET.tostring(root, encoding='unicode')
            reparsed = minidom.parseString(rough_string)
            xml_string = reparsed.toprettyxml(indent=indent)
            # Remove empty lines and extra whitespace
            xml_string = '\n'.join([line for line in xml_string.split('\n') if line.strip()])
        else:
            # Compact format
            xml_string = ET.tostring(root, encoding='unicode')

        return {
            'success': True,
            'result': {
                'xml_string': xml_string
            }
        }

    except Exception as e:
        return {
            'success': False,
            'error': f'toString failed: {str(e)}'
        }

def get_first_child(node_id: str) -> Dict[str, Any]:
    """
    Get the first child element of a node

    Args:
        node_id: Parent node ID

    Returns:
        Dictionary with first child node ID or None
    """
    try:
        node = _get_node(node_id)
        if node is None:
            return {
                'success': False,
                'error': 'Invalid node ID'
            }

        # Get first child element
        children = list(node)
        if not children:
            return {
                'success': True,
                'result': {
                    'node_id': None
                }
            }

        first_child = children[0]

        # Get document ID from parent node
        node_info = NODES.get(node_id)
        if not node_info:
            return {
                'success': False,
                'error': 'Node information not found'
            }

        document_id = node_info['document_id']
        child_node_id = _create_node_reference(first_child, document_id)

        return {
            'success': True,
            'result': {
                'node_id': child_node_id
            }
        }

    except Exception as e:
        return {
            'success': False,
            'error': f'getFirstChild failed: {str(e)}'
        }

def get_parent_node(node_id: str) -> Dict[str, Any]:
    """
    Get the parent node of an element

    Args:
        node_id: Child node ID

    Returns:
        Dictionary with parent node ID or None
    """
    try:
        # This is complex in ElementTree as it doesn't maintain parent references
        # We'd need to search through the document to find the parent
        # For now, return a placeholder implementation

        return {
            'success': True,
            'result': {
                'node_id': None,
                'note': 'getParentNode not fully implemented - ElementTree limitation'
            }
        }

    except Exception as e:
        return {
            'success': False,
            'error': f'getParentNode failed: {str(e)}'
        }

# ============================================================================
# XQL/XPATH INTEGRATION (Phase 3)
# ============================================================================

def _convert_to_lxml(et_node, document_id: str = None) -> Any:
    """
    Convert ElementTree node to lxml for XPath support

    Args:
        et_node: ElementTree node
        document_id: Optional document ID for full document context

    Returns:
        lxml.etree node or document
    """
    try:
        if not LXML_AVAILABLE:
            raise Exception("lxml not available for XPath support")

        # Always use full document context for proper XPath support
        if document_id and document_id in DOCUMENTS:
            document_root = DOCUMENTS[document_id]['root']
            xml_string = ET.tostring(document_root, encoding='unicode')
            lxml_doc = etree.fromstring(xml_string)
            return lxml_doc
        else:
            # Convert single node without document context
            xml_string = ET.tostring(et_node, encoding='unicode')
            return etree.fromstring(xml_string)

    except Exception as e:
        raise Exception(f"ElementTree to lxml conversion failed: {str(e)}")

def _convert_from_lxml(lxml_node, document_id: str, lxml_root, et_root) -> str:
    """
    Convert lxml result back to ElementTree node reference using positional mapping

    Args:
        lxml_node: lxml result node
        document_id: Document ID for node reference
        lxml_root: The lxml root document for position calculation
        et_root: The ElementTree root for position mapping

    Returns:
        Node ID string
    """
    try:
        # Create XPath to find the position of this node in the lxml tree
        # We'll use the node's position among siblings of the same tag

        # Build path from root to this node
        path_elements = []
        current = lxml_node

        while current is not None and current != lxml_root:
            parent = current.getparent()
            if parent is not None:
                # Find position among siblings with same tag
                siblings = [child for child in parent if child.tag == current.tag]
                position = siblings.index(current) + 1  # 1-based indexing
                path_elements.insert(0, (current.tag, position))
            current = parent

        # Now traverse the ElementTree using the same path
        et_current = et_root
        for tag, position in path_elements:
            # Find children with matching tag
            et_children = [child for child in et_current if child.tag == tag]
            if position <= len(et_children):
                et_current = et_children[position - 1]  # Convert to 0-based
            else:
                # Fallback: just use the element directly
                break

        return _create_node_reference(et_current, document_id)

    except Exception as e:
        # Fallback: create new node reference
        xml_string = etree.tostring(lxml_node, encoding='unicode')
        et_node = ET.fromstring(xml_string)
        return _create_node_reference(et_node, document_id)

def xql_query(node_id: str, xpath_expression: str) -> Dict[str, Any]:
    """
    Execute XQL/XPath query on node (matches XML::XQL::DOM behavior)

    This implements the core XQL functionality that matches:
    my $match = ( $node->xql( $xpath ) )[0];

    Args:
        node_id: Context node for query
        xpath_expression: XPath/XQL query string

    Returns:
        Dictionary with matching node IDs or scalar result
    """
    try:
        # Get the source node
        source_node = _get_node(node_id)
        if source_node is None:
            return {
                'success': False,
                'error': 'Invalid node ID'
            }

        # Get document ID for result node creation
        node_info = NODES.get(node_id)
        if not node_info:
            return {
                'success': False,
                'error': 'Node information not found'
            }
        document_id = node_info['document_id']

        _debug(f"Executing XQL query: {xpath_expression} on node {node_id}")

        if LXML_AVAILABLE:
            # Use lxml for full XPath 1.0 support
            try:
                lxml_root = _convert_to_lxml(source_node, document_id)
                results = lxml_root.xpath(xpath_expression)
                # Store both roots for conversion
                et_root = DOCUMENTS[document_id]['root']
            except Exception as e:
                return {
                    'success': False,
                    'error': f'XPath execution failed: {str(e)}'
                }
        else:
            # Fallback to ElementTree's limited XPath support
            try:
                results = source_node.findall(xpath_expression)
            except Exception as e:
                return {
                    'success': False,
                    'error': f'XPath execution failed (ElementTree fallback): {str(e)}'
                }

        # Process results based on type
        if isinstance(results, list):
            # Node list result (most common case for XQL)
            node_ids = []

            _debug(f"Processing {len(results)} XPath results")

            for i, result_node in enumerate(results):
                if LXML_AVAILABLE:
                    # lxml result
                    if hasattr(result_node, 'tag'):  # Element node
                        try:
                            _debug(f"Converting lxml result {i}: tag={result_node.tag}, attrib={dict(result_node.attrib)}")
                            converted_node_id = _convert_from_lxml(result_node, document_id, lxml_root, et_root)
                            node_ids.append(converted_node_id)
                            _debug(f"Successfully converted result {i} to node_id: {converted_node_id}")
                        except Exception as e:
                            _debug(f"Failed to convert lxml result {i}: {str(e)}")
                            continue
                else:
                    # ElementTree result
                    if hasattr(result_node, 'tag'):  # Element node
                        converted_node_id = _create_node_reference(result_node, document_id)
                        node_ids.append(converted_node_id)

            return {
                'success': True,
                'result': {
                    'type': 'nodelist',
                    'node_ids': node_ids,
                    'length': len(node_ids)
                }
            }
        else:
            # Scalar result (string, number, boolean)
            return {
                'success': True,
                'result': {
                    'type': 'scalar',
                    'value': str(results) if results is not None else ""
                }
            }

    except Exception as e:
        return {
            'success': False,
            'error': f'XQL query failed: {str(e)}'
        }

def xql_find_nodes(node_id: str, xpath: str) -> Dict[str, Any]:
    """
    Find nodes matching XPath (wrapper around xql_query for NodeList results)

    Args:
        node_id: Context node
        xpath: XPath expression

    Returns:
        Dictionary with NodeList result
    """
    result = xql_query(node_id, xpath)
    if not result['success']:
        return result

    result_data = result['result']
    if result_data['type'] != 'nodelist':
        # Convert scalar to empty nodelist
        return {
            'success': True,
            'result': {
                'type': 'nodelist',
                'node_ids': [],
                'length': 0
            }
        }

    return result

def xql_find_value(node_id: str, xpath: str) -> Dict[str, Any]:
    """
    Find single value matching XPath (returns string)

    Args:
        node_id: Context node
        xpath: XPath expression

    Returns:
        Dictionary with string result
    """
    result = xql_query(node_id, xpath)
    if not result['success']:
        return result

    result_data = result['result']
    if result_data['type'] == 'scalar':
        return {
            'success': True,
            'result': {
                'value': result_data['value']
            }
        }
    elif result_data['type'] == 'nodelist' and result_data['length'] > 0:
        # Get text content of first node
        first_node_id = result_data['node_ids'][0]
        text_result = get_node_value(first_node_id)
        if text_result['success']:
            return {
                'success': True,
                'result': {
                    'value': text_result['result']['value']
                }
            }

    # No results or error
    return {
        'success': True,
        'result': {
            'value': ""
        }
    }

def xql_exists(node_id: str, xpath: str) -> Dict[str, Any]:
    """
    Check if XPath matches any nodes (returns boolean)

    Args:
        node_id: Context node
        xpath: XPath expression

    Returns:
        Dictionary with boolean result
    """
    result = xql_query(node_id, xpath)
    if not result['success']:
        return {
            'success': True,
            'result': {
                'exists': False
            }
        }

    result_data = result['result']
    if result_data['type'] == 'nodelist':
        exists = result_data['length'] > 0
    else:
        exists = bool(result_data['value'])

    return {
        'success': True,
        'result': {
            'exists': exists
        }
    }

# ============================================================================
# TESTING FUNCTION
# ============================================================================

def test_basic_functionality():
    """Test basic XML DOM functionality"""
    print("Testing XML DOM Helper...")

    # Test parser creation
    parser_result = create_parser()
    if not parser_result['success']:
        print("❌ Parser creation failed")
        return

    parser_id = parser_result['result']['parser_id']
    print("✅ Parser created")

    # Test XML parsing
    test_xml = """<?xml version="1.0" encoding="UTF-8"?>
    <root>
        <item id="1">First Item</item>
        <item id="2">Second Item</item>
        <nested>
            <item id="3">Nested Item</item>
        </nested>
    </root>"""

    parse_result = parse_string(parser_id, test_xml)
    if not parse_result['success']:
        print("❌ XML parsing failed")
        return

    document_id = parse_result['result']['document_id']
    print("✅ XML parsing successful")

    # Test getElementsByTagName
    elements_result = get_elements_by_tag_name(document_id, 'item')
    if not elements_result['success']:
        print("❌ getElementsByTagName failed")
        return

    print(f"✅ Found {elements_result['result']['length']} item elements")

    # Test cleanup
    dispose_result = dispose_document(document_id)
    if dispose_result['success']:
        print("✅ Document disposed successfully")

    print("XML DOM Helper test completed!")

if __name__ == "__main__":
    test_basic_functionality()