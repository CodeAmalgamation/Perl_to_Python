package XMLDOMHelper;

use strict;
use warnings;
use CPANBridge;
use Carp;

our $VERSION = '1.0.0';

# Create bridge instance
our $bridge = CPANBridge->new();

# ============================================================================
# XML::DOM::Parser replacement
# ============================================================================

package XMLDOMHelper::Parser;

sub new {
    my $class = shift;
    my %options = @_;

    my $result = $XMLDOMHelper::bridge->call_python('xml_dom_helper', 'create_parser', \%options);

    if (!$result->{success}) {
        die "Failed to create XML parser: " . $result->{error};
    }

    my $self = {
        parser_id => $result->{result}->{parser_id},
        options => \%options
    };

    return bless $self, $class;
}

sub parse {
    my $self = shift;
    my $xml_string = shift;

    unless (defined $xml_string) {
        die "XML string is required for parse()";
    }

    my $result = $XMLDOMHelper::bridge->call_python('xml_dom_helper', 'parse_string', {
        parser_id => $self->{parser_id},
        xml_string => $xml_string
    });

    if (!$result->{success}) {
        die "XML parsing failed: " . $result->{error};
    }

    return XMLDOMHelper::Document->new(
        $result->{result}->{document_id},
        $result->{result}->{root_node_id}
    );
}

# ============================================================================
# XML::DOM::Document replacement
# ============================================================================

package XMLDOMHelper::Document;

sub new {
    my $class = shift;
    my $document_id = shift;
    my $root_node_id = shift;

    unless (defined $document_id) {
        die "Document ID is required";
    }

    my $self = {
        document_id => $document_id,
        root_node_id => $root_node_id
    };

    return bless $self, $class;
}

sub getElementsByTagName {
    my $self = shift;
    my $tag_name = shift;

    unless (defined $tag_name) {
        die "Tag name is required for getElementsByTagName()";
    }

    my $result = $XMLDOMHelper::bridge->call_python('xml_dom_helper', 'get_elements_by_tag_name', {
        document_id => $self->{document_id},
        tag_name => $tag_name
    });

    if (!$result->{success}) {
        die "getElementsByTagName failed: " . $result->{error};
    }

    return XMLDOMHelper::NodeList->new(
        $result->{result}->{nodelist_id},
        $result->{result}->{node_ids}
    );
}

sub dispose {
    my $self = shift;

    # Try to dispose, but don't warn on errors since it's just cleanup
    # Dispose errors are not critical - documents will be garbage collected anyway
    eval {
        my $result = $XMLDOMHelper::bridge->call_python('xml_dom_helper', 'dispose_document', {
            document_id => $self->{document_id}
        });

        # Only log if debug is enabled
        if ($CPANBridge::DEBUG_LEVEL && !$result->{success}) {
            warn "Document dispose debug info: " . $result->{error};
        }
    };

    return 1;
}

sub createElement {
    my $self = shift;
    my $tag_name = shift;

    unless (defined $tag_name) {
        die "Tag name is required for createElement()";
    }

    my $result = $XMLDOMHelper::bridge->call_python('xml_dom_helper', 'create_element', {
        document_id => $self->{document_id},
        tag_name => $tag_name
    });

    if (!$result->{success}) {
        die "createElement failed: " . $result->{error};
    }

    return XMLDOMHelper::Element->new($result->{result}->{node_id});
}

sub createTextNode {
    my $self = shift;
    my $data = shift;

    $data = "" unless defined $data;

    my $result = $XMLDOMHelper::bridge->call_python('xml_dom_helper', 'create_text_node', {
        document_id => $self->{document_id},
        data => $data
    });

    if (!$result->{success}) {
        die "createTextNode failed: " . $result->{error};
    }

    return XMLDOMHelper::Element->new($result->{result}->{node_id});
}

sub toString {
    my $self = shift;
    my $indent = shift;

    my $params = {
        document_id => $self->{document_id}
    };
    $params->{indent} = $indent if defined $indent;

    my $result = $XMLDOMHelper::bridge->call_python('xml_dom_helper', 'to_string', $params);

    if (!$result->{success}) {
        return "";  # Return empty string on error for compatibility
    }

    return $result->{result}->{xml_string} || "";
}

sub getDocumentElement {
    my $self = shift;

    # Get the root element using getElementsByTagName and find the actual root
    my $all_elements = $self->getElementsByTagName('*');
    if ($all_elements->getLength() == 0) {
        return undef;
    }

    # For a well-formed XML document, the document element is the outermost element
    # We can identify it by finding an element that is not a child of any other element
    my @elements;
    for my $i (0 .. $all_elements->getLength() - 1) {
        push @elements, $all_elements->item($i);
    }

    # Find element that doesn't appear as a child of any other element
    for my $candidate (@elements) {
        my $is_root = 1;
        for my $potential_parent (@elements) {
            next if $candidate == $potential_parent;  # Skip self
            my $children = $potential_parent->getChildNodes();
            for my $j (0 .. $children->getLength() - 1) {
                my $child = $children->item($j);
                if (defined $child && ref($child) eq 'XMLDOMHelper::Element' &&
                    $child->{node_id} eq $candidate->{node_id}) {
                    $is_root = 0;
                    last;
                }
            }
            last unless $is_root;
        }
        return $candidate if $is_root;
    }

    # Fallback: return first element (should be root in most cases)
    return $elements[0];
}

# XQL support on Document level (queries from document root)
sub xql {
    my $self = shift;
    my $xpath = shift;

    # Handle invalid input gracefully
    unless (defined $xpath) {
        return ();
    }

    # Get the document's root element (document element, not first element)
    my $root_element = $self->getDocumentElement();
    if (defined $root_element) {
        return $root_element->xql($xpath);
    }

    return ();  # No root element found
}

# XQL Helper Methods for Document level
sub xql_findvalue {
    my $self = shift;
    my $xpath = shift;

    my $root_element = $self->getDocumentElement();
    if (defined $root_element) {
        return $root_element->xql_findvalue($xpath);
    }

    return "";
}

sub xql_exists {
    my $self = shift;
    my $xpath = shift;

    my $root_element = $self->getDocumentElement();
    if (defined $root_element) {
        return $root_element->xql_exists($xpath);
    }

    return 0;
}

# ============================================================================
# XML::DOM::Element replacement
# ============================================================================

package XMLDOMHelper::Element;

sub new {
    my $class = shift;
    my $node_id = shift;

    unless (defined $node_id) {
        die "Node ID is required";
    }

    my $self = {
        node_id => $node_id
    };

    return bless $self, $class;
}

sub getAttribute {
    my $self = shift;
    my $attr_name = shift;

    unless (defined $attr_name) {
        return "";  # Return empty string for undefined attribute name
    }

    my $result = $XMLDOMHelper::bridge->call_python('xml_dom_helper', 'get_attribute', {
        node_id => $self->{node_id},
        attr_name => $attr_name
    });

    if (!$result->{success}) {
        return "";  # Return empty string on error for compatibility
    }

    return $result->{result}->{value} || "";
}

sub setAttribute {
    my $self = shift;
    my $attr_name = shift;
    my $value = shift;

    unless (defined $attr_name) {
        die "Attribute name is required for setAttribute()";
    }

    $value = "" unless defined $value;

    my $result = $XMLDOMHelper::bridge->call_python('xml_dom_helper', 'set_attribute', {
        node_id => $self->{node_id},
        attr_name => $attr_name,
        value => $value
    });

    if (!$result->{success}) {
        die "setAttribute failed: " . $result->{error};
    }

    return 1;
}

sub hasAttribute {
    my $self = shift;
    my $attr_name = shift;

    unless (defined $attr_name) {
        return 0;  # Return false for undefined attribute name
    }

    my $result = $XMLDOMHelper::bridge->call_python('xml_dom_helper', 'has_attribute', {
        node_id => $self->{node_id},
        attr_name => $attr_name
    });

    if (!$result->{success}) {
        return 0;  # Return false on error
    }

    return $result->{result}->{has_attribute} ? 1 : 0;
}

sub removeAttribute {
    my $self = shift;
    my $attr_name = shift;

    unless (defined $attr_name) {
        return 1;  # Succeed silently for undefined attribute name
    }

    my $result = $XMLDOMHelper::bridge->call_python('xml_dom_helper', 'remove_attribute', {
        node_id => $self->{node_id},
        attr_name => $attr_name
    });

    if (!$result->{success}) {
        die "removeAttribute failed: " . $result->{error};
    }

    return 1;
}

sub getChildNodes {
    my $self = shift;

    my $result = $XMLDOMHelper::bridge->call_python('xml_dom_helper', 'get_child_nodes', {
        node_id => $self->{node_id}
    });

    if (!$result->{success}) {
        die "getChildNodes failed: " . $result->{error};
    }

    return XMLDOMHelper::NodeList->new(
        $result->{result}->{nodelist_id},
        $result->{result}->{node_ids}
    );
}

sub getElementsByTagName {
    my $self = shift;
    my $tag_name = shift;

    unless (defined $tag_name) {
        die "Tag name is required for getElementsByTagName()";
    }

    my $result = $XMLDOMHelper::bridge->call_python('xml_dom_helper', 'get_elements_by_tag_name_from_node', {
        node_id => $self->{node_id},
        tag_name => $tag_name
    });

    if (!$result->{success}) {
        die "getElementsByTagName failed: " . $result->{error};
    }

    return XMLDOMHelper::NodeList->new(
        $result->{result}->{nodelist_id},
        $result->{result}->{node_ids}
    );
}

sub getNodeValue {
    my $self = shift;

    my $result = $XMLDOMHelper::bridge->call_python('xml_dom_helper', 'get_node_value', {
        node_id => $self->{node_id}
    });

    if (!$result->{success}) {
        return "";  # Return empty string on error
    }

    return $result->{result}->{value} || "";
}

sub getTagName {
    my $self = shift;

    my $result = $XMLDOMHelper::bridge->call_python('xml_dom_helper', 'get_tag_name', {
        node_id => $self->{node_id}
    });

    if (!$result->{success}) {
        return "";  # Return empty string on error
    }

    return $result->{result}->{tag_name} || "";
}

sub appendChild {
    my $self = shift;
    my $child = shift;

    unless (defined $child && ref($child) && $child->isa('XMLDOMHelper::Element')) {
        die "Valid child element is required for appendChild()";
    }

    my $result = $XMLDOMHelper::bridge->call_python('xml_dom_helper', 'append_child', {
        parent_id => $self->{node_id},
        child_id => $child->{node_id}
    });

    if (!$result->{success}) {
        die "appendChild failed: " . $result->{error};
    }

    return $child;
}

sub removeChild {
    my $self = shift;
    my $child = shift;

    unless (defined $child && ref($child) && $child->isa('XMLDOMHelper::Element')) {
        die "Valid child element is required for removeChild()";
    }

    my $result = $XMLDOMHelper::bridge->call_python('xml_dom_helper', 'remove_child', {
        parent_id => $self->{node_id},
        child_id => $child->{node_id}
    });

    if (!$result->{success}) {
        die "removeChild failed: " . $result->{error};
    }

    return $child;
}

sub replaceChild {
    my $self = shift;
    my $new_child = shift;
    my $old_child = shift;

    unless (defined $new_child && ref($new_child) && $new_child->isa('XMLDOMHelper::Element')) {
        die "Valid new child element is required for replaceChild()";
    }

    unless (defined $old_child && ref($old_child) && $old_child->isa('XMLDOMHelper::Element')) {
        die "Valid old child element is required for replaceChild()";
    }

    my $result = $XMLDOMHelper::bridge->call_python('xml_dom_helper', 'replace_child', {
        parent_id => $self->{node_id},
        new_child_id => $new_child->{node_id},
        old_child_id => $old_child->{node_id}
    });

    if (!$result->{success}) {
        die "replaceChild failed: " . $result->{error};
    }

    return $old_child;
}

sub insertBefore {
    my $self = shift;
    my $new_child = shift;
    my $ref_child = shift;

    unless (defined $new_child && ref($new_child) && $new_child->isa('XMLDOMHelper::Element')) {
        die "Valid new child element is required for insertBefore()";
    }

    unless (defined $ref_child && ref($ref_child) && $ref_child->isa('XMLDOMHelper::Element')) {
        die "Valid reference child element is required for insertBefore()";
    }

    my $result = $XMLDOMHelper::bridge->call_python('xml_dom_helper', 'insert_before', {
        parent_id => $self->{node_id},
        new_child_id => $new_child->{node_id},
        ref_child_id => $ref_child->{node_id}
    });

    if (!$result->{success}) {
        die "insertBefore failed: " . $result->{error};
    }

    return $new_child;
}

sub cloneNode {
    my $self = shift;
    my $deep = shift;

    $deep = 0 unless defined $deep;

    my $result = $XMLDOMHelper::bridge->call_python('xml_dom_helper', 'clone_node', {
        node_id => $self->{node_id},
        deep => $deep ? 1 : 0
    });

    if (!$result->{success}) {
        die "cloneNode failed: " . $result->{error};
    }

    return XMLDOMHelper::Element->new($result->{result}->{node_id});
}

sub getFirstChild {
    my $self = shift;

    my $result = $XMLDOMHelper::bridge->call_python('xml_dom_helper', 'get_first_child', {
        node_id => $self->{node_id}
    });

    if (!$result->{success}) {
        return undef;  # Return undef on error
    }

    my $child_node_id = $result->{result}->{node_id};
    return $child_node_id ? XMLDOMHelper::Element->new($child_node_id) : undef;
}

sub getParentNode {
    my $self = shift;

    my $result = $XMLDOMHelper::bridge->call_python('xml_dom_helper', 'get_parent_node', {
        node_id => $self->{node_id}
    });

    if (!$result->{success}) {
        return undef;  # Return undef on error
    }

    my $parent_node_id = $result->{result}->{node_id};
    return $parent_node_id ? XMLDOMHelper::Element->new($parent_node_id) : undef;
}

# ============================================================================
# XQL/XPath Integration (Phase 3) - Matches XML::XQL::DOM behavior
# ============================================================================

sub xql {
    my $self = shift;
    my $xpath = shift;  # Keep misleading name for compatibility with Config.pm!

    # Handle invalid input gracefully (matches XML::XQL behavior)
    unless (defined $xpath) {
        return ();  # Return empty array in array context
    }

    unless (defined $self->{node_id}) {
        return ();  # Return empty array for invalid node
    }

    # Execute XQL query with error handling
    my $result = eval {
        $XMLDOMHelper::bridge->call_python('xml_dom_helper', 'xql_query', {
            node_id => $self->{node_id},
            xpath_expression => $xpath
        });
    };

    # Debug output for troubleshooting
    if ($XMLDOMHelper::CPANBridge::DEBUG_LEVEL) {
        if ($@) {
            warn "DEBUG: XQL query eval error: $@";
        }
        if ($result && !$result->{success}) {
            warn "DEBUG: XQL query failed: " . ($result->{error} // "unknown error");
        }
    }

    # Return empty array on any error (matches XML::XQL behavior)
    if ($@ || !$result || !$result->{success}) {
        return ();
    }

    # Check if the inner Python function call succeeded
    my $python_result = $result->{result};
    if (!$python_result || !$python_result->{success}) {
        warn "DEBUG: Python XQL function failed: " . ($python_result->{error} // "unknown error");
        return ();
    }

    my $result_data = $python_result->{result};


    if ($result_data && $result_data->{type} && $result_data->{type} eq 'nodelist') {
        # Convert node IDs back to Element objects for array context
        # This supports: my $match = ( $node->xql( $xpath ) )[0];
        my @nodes = ();
        for my $node_id (@{$result_data->{node_ids}}) {
            push @nodes, XMLDOMHelper::Element->new($node_id);
        }
        return @nodes;  # Return array for array context usage
    } else {
        # Scalar result - return single value
        return ($result_data->{value});
    }
}

# XQL Helper Methods (bonus compatibility)
sub xql_findnodes {
    my $self = shift;
    my $xpath = shift;

    my @results = $self->xql($xpath);
    return @results;
}

sub xql_findvalue {
    my $self = shift;
    my $xpath = shift;

    unless (defined $xpath) {
        return "";
    }

    # Use the regular xql method and get text from first result
    my @results = $self->xql($xpath);

    if (@results && defined $results[0]) {
        return $results[0]->getNodeValue() || "";
    }

    return "";
}

sub xql_exists {
    my $self = shift;
    my $xpath = shift;

    unless (defined $xpath) {
        return 0;
    }

    # Use the regular xql method and check if any results exist
    my @results = $self->xql($xpath);

    return @results ? 1 : 0;
}

# ============================================================================
# NodeList replacement
# ============================================================================

package XMLDOMHelper::NodeList;

sub new {
    my $class = shift;
    my $nodelist_id = shift;
    my $node_ids = shift;

    my $self = {
        nodelist_id => $nodelist_id,
        node_ids => $node_ids || [],
        current_index => 0
    };

    return bless $self, $class;
}

sub getLength {
    my $self = shift;

    if ($self->{nodelist_id}) {
        my $result = $XMLDOMHelper::bridge->call_python('xml_dom_helper', 'get_nodelist_length', {
            nodelist_id => $self->{nodelist_id}
        });

        if ($result->{success}) {
            return $result->{result}->{length};
        }
    }

    # Fallback to local count
    return scalar @{$self->{node_ids}};
}

sub item {
    my $self = shift;
    my $index = shift;

    unless (defined $index) {
        return undef;
    }

    if ($self->{nodelist_id}) {
        my $result = $XMLDOMHelper::bridge->call_python('xml_dom_helper', 'get_nodelist_item', {
            nodelist_id => $self->{nodelist_id},
            index => $index
        });

        if ($result->{success}) {
            my $node_id = $result->{result}->{node_id};
            return $node_id ? XMLDOMHelper::Element->new($node_id) : undef;
        }
    }

    # Fallback to local access
    if ($index >= 0 && $index < scalar @{$self->{node_ids}}) {
        my $node_id = $self->{node_ids}->[$index];
        return XMLDOMHelper::Element->new($node_id);
    }

    return undef;
}

1;

__END__

=head1 NAME

XMLDOMHelper - XML::DOM replacement using Python backend

=head1 DESCRIPTION

XMLDOMHelper provides a replacement for XML::DOM functionality
using a Python backend through CPANBridge.

=cut