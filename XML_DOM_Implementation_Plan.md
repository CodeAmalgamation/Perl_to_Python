# XML::DOM Replacement Implementation Plan

## Overview
This document outlines the implementation plan to create a comprehensive XML::DOM replacement using Python's XML processing capabilities. The analysis shows sophisticated DOM manipulation, XQL integration, and extensive document modification requirements.

## Current XML::DOM Usage Analysis

### Key Patterns Identified
1. **Full DOM Tree Manipulation** - Not just parsing, but complete document object model
2. **getElementsByTagName Navigation** - Primary method for element discovery
3. **Mixed DOM/XQL Queries** - Integration with XML::XQL for complex queries
4. **Document Creation & Modification** - Building XML documents from scratch
5. **Memory Management** - Explicit dispose() for memory cleanup
6. **Complex Text Extraction** - Multi-level node traversal for content
7. **Attribute Access & Modification** - Extensive getAttribute/setAttribute usage
8. **Node Cloning & Tree Manipulation** - Deep cloning and subtree operations

## Implementation Strategy

### Phase 1: Core DOM Infrastructure
**Goal:** Basic DOM parsing, navigation, and document representation

**Python Backend:** xml_dom_helper.py
**Perl Interface:** XMLDOMHelper.pm

### Phase 2: Document Modification & Creation
**Goal:** Node creation, modification, and document generation

### Phase 3: XPath/XQL Integration
**Goal:** Complex querying capabilities compatible with XML::XQL

### Phase 4: Advanced Features
**Goal:** Memory management, performance optimization, error handling

## Technical Architecture

### Python Backend: xml_dom_helper.py

```python
import xml.etree.ElementTree as ET
from xml.dom import minidom
import xml.etree.ElementTree as XMLTree
from lxml import etree, html
import uuid
import copy
```

**Key Libraries:**
- **xml.etree.ElementTree** - Primary XML processing
- **xml.dom.minidom** - DOM-like interface
- **lxml** - Advanced XPath support and better DOM features
- **html** - HTML parsing if needed

### Perl Interface: XMLDOMHelper.pm

```perl
package XMLDOMHelper;
use strict;
use warnings;
use CPANBridge;

# Maintain compatibility with XML::DOM API
```

## Detailed Implementation Plan

### 1. Parser & Document Creation

#### XML::DOM::Parser Replacement
```python
def create_parser(**options):
    """
    Create XML parser instance
    Returns: parser_id for subsequent operations
    """
    parser_config = {
        'parser_id': str(uuid.uuid4()),
        'options': options,
        'created_at': time.time()
    }
    return parser_config

def parse_string(parser_id, xml_string):
    """
    Parse XML from string
    Args:
        parser_id: Parser instance ID
        xml_string: XML content as string
    Returns:
        document_id: Parsed document identifier
    """

def parse_file(parser_id, filename):
    """
    Parse XML from file
    Args:
        parser_id: Parser instance ID
        filename: Path to XML file
    Returns:
        document_id: Parsed document identifier
    """
```

#### Document Object Model
```python
class XMLDocument:
    def __init__(self, root_element=None):
        self.doc_id = str(uuid.uuid4())
        self.root = root_element
        self.xml_declaration = {'version': '1.0', 'encoding': 'UTF-8'}

    def get_elements_by_tag_name(self, tag_name):
        """Find all elements with specified tag name"""

    def create_element(self, tag_name):
        """Create new element node"""

    def create_text_node(self, data):
        """Create text node with data"""

    def create_cdata_section(self, data):
        """Create CDATA section"""
```

### 2. DOM Navigation Methods

#### getElementsByTagName Implementation
```python
def get_elements_by_tag_name(document_id, tag_name):
    """
    Find all elements with specified tag name
    Returns: NodeList with matching elements
    """
    document = get_document(document_id)
    elements = []

    # Recursive search through DOM tree
    def find_elements(node, tag):
        if node.tag == tag:
            elements.append(create_node_reference(node))
        for child in node:
            find_elements(child, tag)

    find_elements(document.root, tag_name)
    return create_node_list(elements)
```

#### Child Node Access
```python
def get_child_nodes(node_id):
    """Get all child nodes of specified node"""

def get_first_child(node_id):
    """Get first child node"""

def get_next_sibling(node_id):
    """Get next sibling node"""

def is_element_node(node_id):
    """Check if node is element type"""
```

#### Attribute Handling
```python
def get_attribute(node_id, attr_name):
    """Get attribute value"""

def set_attribute(node_id, attr_name, value):
    """Set attribute value"""

def remove_attribute(node_id, attr_name):
    """Remove attribute"""

def has_attribute(node_id, attr_name):
    """Check if attribute exists"""
```

### 3. Text Content Extraction

#### Complex Text Extraction Pattern
```python
def get_text_contents(node_id, trim=False):
    """
    Extract text content from node and children
    Replicates the complex getTextContents pattern
    """
    node = get_node(node_id)
    contents = ""

    def extract_text(element):
        text = ""
        if element.text:
            text += element.text
        for child in element:
            text += extract_text(child)
            if child.tail:
                text += child.tail
        return text

    contents = extract_text(node)
    return contents.strip() if trim else contents

def get_node_value(node_id):
    """Get node's direct text value"""

def get_data(node_id):
    """Get text data from text/CDATA nodes"""
```

### 4. Document Modification

#### Node Creation
```python
def create_element(document_id, tag_name):
    """Create new element"""

def create_text_node(document_id, data):
    """Create text node"""

def create_cdata_section(document_id, data):
    """Create CDATA section"""

def create_xml_declaration(document_id, version, encoding, standalone):
    """Create XML declaration"""
```

#### Tree Manipulation
```python
def append_child(parent_id, child_id):
    """Append child node to parent"""

def remove_child(parent_id, child_id):
    """Remove child from parent"""

def replace_child(parent_id, new_child_id, old_child_id):
    """Replace child node"""

def insert_before(parent_id, new_child_id, ref_child_id):
    """Insert child before reference node"""
```

#### Node Cloning
```python
def clone_node(node_id, deep=False):
    """
    Clone node (shallow or deep)

    Args:
        node_id: Source node to clone
        deep: If True, clone all descendants
    Returns:
        cloned_node_id: New cloned node
    """
    source_node = get_node(node_id)

    if deep:
        cloned = copy.deepcopy(source_node)
    else:
        cloned = copy.copy(source_node)
        # Remove children for shallow copy
        cloned.clear()

    return create_node_reference(cloned)
```

### 5. XPath/XQL Integration

#### XQL Method Support
```python
def xql_query(node_id, xpath_expression):
    """
    Execute XQL/XPath query on node

    Args:
        node_id: Context node for query
        xpath_expression: XPath query string
    Returns:
        List of matching node IDs
    """
    node = get_node(node_id)

    # Use lxml for advanced XPath support
    if hasattr(node, 'xpath'):
        results = node.xpath(xpath_expression)
    else:
        # Fallback to ElementTree findall with limited XPath
        results = node.findall(xpath_expression)

    return [create_node_reference(result) for result in results]

def find_node(node_id, xpath):
    """Find single node matching XPath (first match)"""
    results = xql_query(node_id, xpath)
    return results[0] if results else None
```

### 6. Document Serialization

#### XML Generation
```python
def to_string(document_id, indent=None):
    """
    Convert document to XML string

    Args:
        document_id: Document to serialize
        indent: Indentation for pretty printing
    Returns:
        XML string representation
    """
    document = get_document(document_id)

    if indent:
        # Pretty print with indentation
        rough_string = ET.tostring(document.root, encoding='unicode')
        reparsed = minidom.parseString(rough_string)
        return reparsed.toprettyxml(indent=indent)
    else:
        return ET.tostring(document.root, encoding='unicode')

def write_to_file(document_id, filename, encoding='UTF-8'):
    """Write document to file"""
```

### 7. Memory Management

#### Resource Cleanup
```python
def dispose_document(document_id):
    """Clean up document resources"""
    if document_id in DOCUMENTS:
        del DOCUMENTS[document_id]

    # Clean up associated nodes
    cleanup_document_nodes(document_id)

def dispose_node(node_id):
    """Clean up node resources"""
    if node_id in NODES:
        del NODES[node_id]

# Automatic cleanup with context managers
class DocumentContext:
    def __init__(self, document_id):
        self.document_id = document_id

    def __enter__(self):
        return self.document_id

    def __exit__(self, exc_type, exc_val, exc_tb):
        dispose_document(self.document_id)
```

### 8. Error Handling

#### Comprehensive Error Management
```python
class XMLDOMException(Exception):
    """Base exception for XML DOM operations"""
    pass

class ParseException(XMLDOMException):
    """XML parsing errors"""
    pass

class NodeException(XMLDOMException):
    """Node operation errors"""
    pass

def safe_parse(parser_id, xml_input, is_file=False):
    """
    Safe XML parsing with comprehensive error handling
    """
    try:
        if is_file:
            return parse_file(parser_id, xml_input)
        else:
            return parse_string(parser_id, xml_input)
    except ET.ParseError as e:
        raise ParseException(f"XML parsing failed: {str(e)}")
    except Exception as e:
        raise XMLDOMException(f"Unexpected error: {str(e)}")
```

## Perl Interface Design

### XMLDOMHelper.pm Structure

```perl
package XMLDOMHelper;
use strict;
use warnings;
use CPANBridge;
use Carp;

our $bridge = CPANBridge->new();

# Parser Class
package XMLDOMHelper::Parser;

sub new {
    my ($class, %options) = @_;

    my $result = $bridge->call_python('xml_dom_helper', 'create_parser', \%options);
    if (!$result->{success}) {
        croak "Failed to create XML parser: " . $result->{error};
    }

    return bless {
        parser_id => $result->{result}->{parser_id}
    }, $class;
}

sub parse {
    my ($self, $xml_string) = @_;

    my $result = $bridge->call_python('xml_dom_helper', 'parse_string', {
        parser_id => $self->{parser_id},
        xml_string => $xml_string
    });

    if (!$result->{success}) {
        croak "XML parsing failed: " . $result->{error};
    }

    return XMLDOMHelper::Document->new($result->{result}->{document_id});
}

sub parsefile {
    my ($self, $filename) = @_;

    my $result = $bridge->call_python('xml_dom_helper', 'parse_file', {
        parser_id => $self->{parser_id},
        filename => $filename
    });

    if (!$result->{success}) {
        croak "File parsing failed: " . $result->{error};
    }

    return XMLDOMHelper::Document->new($result->{result}->{document_id});
}

# Document Class
package XMLDOMHelper::Document;

sub new {
    my ($class, $document_id) = @_;
    return bless { document_id => $document_id }, $class;
}

sub getElementsByTagName {
    my ($self, $tag_name) = @_;

    my $result = $bridge->call_python('xml_dom_helper', 'get_elements_by_tag_name', {
        document_id => $self->{document_id},
        tag_name => $tag_name
    });

    return XMLDOMHelper::NodeList->new($result->{result}->{node_ids});
}

sub createElement {
    my ($self, $tag_name) = @_;

    my $result = $bridge->call_python('xml_dom_helper', 'create_element', {
        document_id => $self->{document_id},
        tag_name => $tag_name
    });

    return XMLDOMHelper::Element->new($result->{result}->{node_id});
}

sub toString {
    my ($self) = @_;

    my $result = $bridge->call_python('xml_dom_helper', 'to_string', {
        document_id => $self->{document_id}
    });

    return $result->{result}->{xml_string};
}

sub dispose {
    my ($self) = @_;

    $bridge->call_python('xml_dom_helper', 'dispose_document', {
        document_id => $self->{document_id}
    });
}

# Element Class
package XMLDOMHelper::Element;

sub new {
    my ($class, $node_id) = @_;
    return bless { node_id => $node_id }, $class;
}

sub getAttribute {
    my ($self, $attr_name) = @_;

    my $result = $bridge->call_python('xml_dom_helper', 'get_attribute', {
        node_id => $self->{node_id},
        attr_name => $attr_name
    });

    return $result->{result}->{value};
}

sub getChildNodes {
    my ($self) = @_;

    my $result = $bridge->call_python('xml_dom_helper', 'get_child_nodes', {
        node_id => $self->{node_id}
    });

    return XMLDOMHelper::NodeList->new($result->{result}->{node_ids});
}

sub appendChild {
    my ($self, $child) = @_;

    $bridge->call_python('xml_dom_helper', 'append_child', {
        parent_id => $self->{node_id},
        child_id => $child->{node_id}
    });
}

sub xql {
    my ($self, $xpath) = @_;

    my $result = $bridge->call_python('xml_dom_helper', 'xql_query', {
        node_id => $self->{node_id},
        xpath_expression => $xpath
    });

    my @nodes = map { XMLDOMHelper::Element->new($_) } @{$result->{result}->{node_ids}};
    return @nodes;
}

# NodeList Class
package XMLDOMHelper::NodeList;

sub new {
    my ($class, $node_ids) = @_;
    return bless {
        node_ids => $node_ids || [],
        current_index => 0
    }, $class;
}

sub getLength {
    my ($self) = @_;
    return scalar @{$self->{node_ids}};
}

sub item {
    my ($self, $index) = @_;
    return unless $index < $self->getLength();

    my $node_id = $self->{node_ids}->[$index];
    return XMLDOMHelper::Element->new($node_id);
}
```

## Implementation Timeline

### Phase 1: Core Infrastructure (Week 1)
- ✅ XML parsing (string and file)
- ✅ Basic DOM navigation (getElementsByTagName)
- ✅ Attribute access
- ✅ Text content extraction

### Phase 2: Document Modification (Week 2)
- ✅ Element creation
- ✅ Node manipulation (appendChild, removeChild)
- ✅ Text and CDATA node creation
- ✅ Document serialization

### Phase 3: Advanced Features (Week 3)
- ✅ XPath/XQL integration
- ✅ Node cloning
- ✅ Complex tree operations
- ✅ Memory management

### Phase 4: Testing & Optimization (Week 4)
- ✅ Comprehensive test suite
- ✅ Performance optimization
- ✅ Error handling refinement
- ✅ Documentation completion

## Success Criteria

### Functional Requirements
- ✅ 100% API compatibility with XML::DOM usage patterns
- ✅ Full getElementsByTagName support
- ✅ Complete attribute access/modification
- ✅ Document creation and modification
- ✅ XQL query support
- ✅ Memory management with dispose()

### Performance Requirements
- ✅ Parse performance comparable to XML::DOM
- ✅ Memory usage optimization
- ✅ Large document handling (>10MB XML files)

### Compatibility Requirements
- ✅ Seamless integration with existing Config.pm code
- ✅ No changes required to consumer code
- ✅ Full error handling compatibility

## Risk Assessment

### High Risk
- 🔴 XQL integration complexity
- 🔴 Memory management in Python/Perl bridge
- 🔴 Large document performance

### Medium Risk
- ⚠️ API compatibility edge cases
- ⚠️ Error message consistency
- ⚠️ Unicode handling

### Mitigation Strategies
- Incremental implementation with continuous testing
- Memory profiling at each phase
- Extensive compatibility testing with existing code
- Performance benchmarking against XML::DOM

---

*Implementation Plan Version: 1.0*
*Created: 2025-09-29*
*Estimated Timeline: 4 weeks*