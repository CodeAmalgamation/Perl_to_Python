# File: XMLHelper.pm
# Production-ready XML::Simple replacement for RHEL 9 migration
# Provides drop-in compatibility with XML::Simple functionality

package XMLHelper;

use strict;
use warnings;
use parent 'CPANBridge';
use Carp;
use Scalar::Util qw(blessed);

our $VERSION = '1.00';

# Class variables for XML::Simple compatibility
our $STRICT = 0;  # XML::Simple compatibility mode

sub new {
    my ($class, %args) = @_;
    
    # Initialize with CPANBridge functionality
    my $self = $class->SUPER::new(%args);
    
    # XML::Simple specific attributes
    $self->{strict} = $args{Strict} // $STRICT;
    $self->{cache} = {};  # For template caching if needed
    $self->{last_error} = undef;
    
    return $self;
}

# Main XMLin method - drop-in replacement for XML::Simple::XMLin
sub XMLin {
    my ($self, $source, %options) = @_;
    
    # Handle class method call (XML::Simple compatibility)
    if (!ref($self)) {
        # Called as XMLHelper::XMLin() or XMLHelper->XMLin()
        my $temp_instance = $self->new();
        return $temp_instance->XMLin($source, %options);
    }
    
    # Validate input parameters
    unless (defined $source) {
        $self->_set_error("XMLin requires a source parameter");
        return undef if $self->{strict};
        croak "XMLin requires a source parameter";
    }
    
    # Determine source type
    my $source_type = $self->_determine_source_type($source);
    
    $self->_debug("XMLin called with source type: $source_type");
    $self->_debug("Options: " . join(", ", map { "$_=" . ($options{$_} // 'undef') } keys %options));
    
    # Prepare parameters for Python bridge
    my $params = {
        source => $source,
        source_type => $source_type,
        options => \%options
    };
    
    # Call Python bridge
    my $result = $self->call_python('xml', 'xml_in', $params);
    
    # Handle bridge communication errors
    unless ($result && ref($result) eq 'HASH') {
        my $error = "Bridge communication failed";
        $self->_set_error($error);
        return undef if $self->{strict};
        croak $error;
    }
    
    unless ($result->{success}) {
        my $error = $result->{error} || "Unknown XML parsing error";
        $self->_set_error($error);
        return undef if $self->{strict};
        croak "XML parsing failed: $error";
    }
    
    # Return the parsed data structure
    my $parsed_data = $result->{result};
    
    $self->_debug("XMLin successful, returned data type: " . ref($parsed_data));
    $self->{last_error} = undef;
    
    return $parsed_data;
}

# XMLout method for completeness (not used in your current codebase)
sub XMLout {
    my ($self, $data, %options) = @_;
    
    # Handle class method call
    if (!ref($self)) {
        my $temp_instance = $self->new();
        return $temp_instance->XMLout($data, %options);
    }
    
    unless (defined $data) {
        $self->_set_error("XMLout requires data to convert");
        return undef if $self->{strict};
        croak "XMLout requires data to convert";
    }
    
    $self->_debug("XMLout called with data type: " . ref($data));
    
    my $params = {
        data => $data,
        options => \%options
    };
    
    my $result = $self->call_python('xml', 'xml_out', $params);
    
    unless ($result && $result->{success}) {
        my $error = $result ? $result->{error} : "Bridge communication failed";
        $self->_set_error($error);
        return undef if $self->{strict};
        croak "XML generation failed: $error";
    }
    
    $self->{last_error} = undef;
    return $result->{result};
}

# Determine if source is file path, string, or filehandle
sub _determine_source_type {
    my ($self, $source) = @_;
    
    # Check if it's a file handle
    if (ref($source)) {
        return 'filehandle';
    }
    
    # Check if it looks like XML content (starts with < or whitespace then <)
    if ($source =~ /^\s*</) {
        return 'string';
    }
    
    # Check if it's a URL
    if ($source =~ /^https?:\/\//) {
        return 'url';
    }
    
    # Assume it's a file path
    return 'file';
}

# Error handling
sub _set_error {
    my ($self, $error) = @_;
    $self->{last_error} = $error;
}

sub get_last_error {
    my $self = shift;
    return $self->{last_error};
}

# XML::Simple compatibility methods
sub escape_value {
    my ($self, $value) = @_;
    
    # Basic XML escaping - delegate to Python for complex cases
    my $result = $self->call_python('xml', 'escape_xml', { value => $value });
    return $result && $result->{success} ? $result->{result} : $value;
}

sub unescape_value {
    my ($self, $value) = @_;
    
    my $result = $self->call_python('xml', 'unescape_xml', { value => $value });
    return $result && $result->{success} ? $result->{result} : $value;
}

# Override debug method to include XML-specific context
sub _debug {
    my ($self, $message) = @_;
    
    return unless $self->{debug};
    
    my $timestamp = scalar localtime;
    my $caller = (caller(1))[3] || 'XMLHelper';
    
    warn "[$timestamp] XMLHelper DEBUG ($caller): $message\n";
}

# Cleanup
sub DESTROY {
    my $self = shift;
    # Clear any cached data
    $self->{cache} = {} if $self->{cache};
    $self->SUPER::DESTROY() if $self->can('SUPER::DESTROY');
}

1;

__END__

=head1 NAME

XMLHelper - XML::Simple replacement for RHEL 9 migration

=head1 SYNOPSIS

    use XMLHelper;
    
    # Drop-in replacement for XML::Simple
    my $parser = XMLHelper->new();
    
    # Load XML template (your usage pattern)
    my $templateParser = new XMLHelper;
    my $ticketTemplate = $templateParser->XMLin($ticketFile, KeepRoot => 0);
    
    # Parse XML response (your usage pattern)
    my $parser = new XMLHelper;
    my $respData = $parser->XMLin($web_response->decoded_content);
    my $respContent = $parser->XMLin($respData->{content});

=head1 DESCRIPTION

XMLHelper provides a drop-in replacement for XML::Simple that works without 
CPAN dependencies by using Python XML processing underneath. It supports 
all XML::Simple functionality found in your existing scripts.

=head1 METHODS

=head2 new(%options)

Creates a new XMLHelper instance.

=head2 XMLin($source, %options)

Parses XML from file, string, URL, or filehandle. Supports all XML::Simple options.

Common options:
- KeepRoot => 0|1 (default 1)
- ForceArray => [] or regex
- KeyAttr => [] or string
- SuppressEmpty => '' or undef or 1

=head2 XMLout($data, %options)

Converts Perl data structure to XML string.

=head1 ERROR HANDLING

XMLHelper maintains XML::Simple's error handling behavior:
- Dies on errors by default
- Use eval{} blocks to catch errors
- Check get_last_error() for error details

=head1 COMPATIBILITY

This module is designed as a complete drop-in replacement for XML::Simple.
No code changes should be required in existing scripts.

=head1 SEE ALSO

L<CPANBridge>, L<XML::Simple>

=cut