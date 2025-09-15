# File: ExcelHelper.pm
package ExcelHelper;

use strict;
use warnings;
use CPANBridge;
use Carp;

our $VERSION = '1.00';

# Main ExcelHelper class - Excel::Writer::XLSX replacement
package ExcelHelper;
use strict;
use warnings;
use base 'CPANBridge';

sub new {
    my ($class, $filename, %args) = @_;
    
    croak "Filename required for Excel workbook" unless $filename;
    
    my $self = $class->SUPER::new(%args);
    
    # Excel::Writer::XLSX specific configuration
    $self->{filename} = $filename;
    $self->{worksheets} = [];
    $self->{formats} = {};
    $self->{workbook_id} = undef;
    $self->{closed} = 0;
    
    # Initialize workbook via Python backend
    $self->_create_workbook();
    
    return $self;
}

# Initialize Excel workbook
sub _create_workbook {
    my $self = shift;
    
    # Create workbook via Python backend
    my $result = $self->call_python('excel', 'create_workbook', {
        filename => $self->{filename}
    });
    
    if ($result->{success}) {
        $self->{workbook_id} = $result->{result}->{workbook_id};
    } else {
        croak "Failed to create Excel workbook: " . $result->{error};
    }
}

# Add worksheet (your pattern)
sub add_worksheet {
    my ($self, $name) = @_;
    
    croak "Workbook is closed" if $self->{closed};
    
    $name ||= '';  # Default worksheet name
    
    # Create worksheet via Python backend
    my $result = $self->call_python('excel', 'add_worksheet', {
        workbook_id => $self->{workbook_id},
        name => $name
    });
    
    if ($result->{success}) {
        my $worksheet = ExcelHelper::Worksheet->new($self, $result->{result}->{worksheet_id}, $name);
        push @{$self->{worksheets}}, $worksheet;
        return $worksheet;
    } else {
        croak "Failed to add worksheet: " . $result->{error};
    }
}

# Add format (your pattern)
sub add_format {
    my ($self, %properties) = @_;
    
    croak "Workbook is closed" if $self->{closed};
    
    # Create format via Python backend
    my $result = $self->call_python('excel', 'add_format', {
        workbook_id => $self->{workbook_id},
        properties => \%properties
    });
    
    if ($result->{success}) {
        my $format = ExcelHelper::Format->new($self, $result->{result}->{format_id}, \%properties);
        my $format_id = $result->{result}->{format_id};
        $self->{formats}->{$format_id} = $format;
        return $format;
    } else {
        croak "Failed to add format: " . $result->{error};
    }
}

# Close workbook (your pattern)
sub close {
    my $self = shift;
    
    return if $self->{closed};
    
    # Close workbook via Python backend
    my $result = $self->call_python('excel', 'close_workbook', {
        workbook_id => $self->{workbook_id}
    });
    
    $self->{closed} = 1;
    
    if (!$result->{success}) {
        warn "Warning: Failed to close Excel workbook cleanly: " . $result->{error};
    }
    
    return $result->{success};
}

# Cleanup on destruction
sub DESTROY {
    my $self = shift;
    $self->close() unless $self->{closed};
}

# Worksheet class
package ExcelHelper::Worksheet;
use strict;
use warnings;

sub new {
    my ($class, $workbook, $worksheet_id, $name) = @_;
    
    my $self = {
        workbook => $workbook,
        worksheet_id => $worksheet_id,
        name => $name || '',
    };
    
    return bless $self, $class;
}

# Write cell data (your main pattern)
sub write {
    my ($self, $row, $col, $data, $format) = @_;
    
    croak "Workbook is closed" if $self->{workbook}->{closed};
    
    # Prepare write parameters
    my $params = {
        workbook_id => $self->{workbook}->{workbook_id},
        worksheet_id => $self->{worksheet_id},
        row => $row,
        col => $col,
        data => $data,
    };
    
    # Add format if provided
    if ($format && ref($format) eq 'ExcelHelper::Format') {
        $params->{format_id} = $format->{format_id};
    }
    
    # Write cell via Python backend
    my $result = $self->{workbook}->call_python('excel', 'write_cell', $params);
    
    if (!$result->{success}) {
        croak "Failed to write cell: " . $result->{error};
    }
    
    return 1;
}

# Additional write methods for compatibility
sub write_string {
    my ($self, $row, $col, $string, $format) = @_;
    return $self->write($row, $col, $string, $format);
}

sub write_number {
    my ($self, $row, $col, $number, $format) = @_;
    return $self->write($row, $col, $number, $format);
}

sub write_formula {
    my ($self, $row, $col, $formula, $format) = @_;
    return $self->write($row, $col, $formula, $format);
}

# Format class
package ExcelHelper::Format;
use strict;
use warnings;

sub new {
    my ($class, $workbook, $format_id, $properties) = @_;
    
    my $self = {
        workbook => $workbook,
        format_id => $format_id,
        properties => $properties || {},
    };
    
    return bless $self, $class;
}

# Format methods (your pattern)
sub set_bold {
    my ($self, $bold) = @_;
    $bold = 1 unless defined $bold;
    $self->_set_property('bold', $bold);
}

sub set_color {
    my ($self, $color) = @_;
    $self->_set_property('font_color', $color);
}

sub set_bg_color {
    my ($self, $color) = @_;
    $self->_set_property('bg_color', $color);
}

sub set_align {
    my ($self, $alignment) = @_;
    $self->_set_property('align', $alignment);
}

sub set_border {
    my ($self, $border) = @_;
    $self->_set_property('border', $border);
}

sub set_num_format {
    my ($self, $format) = @_;
    $self->_set_property('num_format', $format);
}

# Internal method to set format properties
sub _set_property {
    my ($self, $property, $value) = @_;
    
    $self->{properties}->{$property} = $value;
    
    # Update format via Python backend
    my $result = $self->{workbook}->call_python('excel', 'update_format', {
        workbook_id => $self->{workbook}->{workbook_id},
        format_id => $self->{format_id},
        property => $property,
        value => $value
    });
    
    if (!$result->{success}) {
        warn "Warning: Failed to update format property: " . $result->{error};
    }
    
    return $self;  # Allow method chaining
}

# Export compatibility
package ExcelHelper;

sub import {
    my $class = shift;
    my $caller = caller;
    
    # Create Excel::Writer::XLSX compatibility
    {
        no strict 'refs';
        *{"${caller}::Excel::Writer::XLSX::new"} = sub {
            shift;  # Remove class name
            return ExcelHelper->new(@_);
        };
    }
}

1;

__END__

=head1 NAME

ExcelHelper - Excel::Writer::XLSX replacement using Python backend

=head1 SYNOPSIS

    # Replace: require Excel::Writer::XLSX;
    use ExcelHelper;
    
    # Your existing code works unchanged:
    my $workbook = Excel::Writer::XLSX->new($file);
    my $worksheet = $workbook->add_worksheet();
    
    my $hdrFormat = $workbook->add_format();
    $hdrFormat->set_bold();
    $hdrFormat->set_color('black');
    $hdrFormat->set_bg_color('gray');
    $hdrFormat->set_align('center');
    
    my $x = $y = 0;
    my @keys = sort keys %{$data->[0]};
    for my $header (@keys) {
        $worksheet->write($y, $x++, $header, $hdrFormat);
    }
    
    for my $row (@{$data}) {
        $x = 0;
        ++$y;
        $worksheet->write($y, $x++, $_) for @{$row}{@keys};
    }
    
    $workbook->close();

=head1 DESCRIPTION

ExcelHelper provides a drop-in replacement for Excel::Writer::XLSX by routing
Excel operations through a Python backend that uses openpyxl or xlsxwriter.

Supports all patterns from your usage analysis:
- Workbook creation with filename
- Single worksheet addition
- Cell formatting (bold, colors, alignment)
- Cell writing with write() method
- Structured data export workflows
- Proper workbook closing

=head1 METHODS

All Excel::Writer::XLSX methods from your analysis are supported:
- new() with filename parameter
- add_worksheet() for worksheet creation
- add_format() for cell formatting
- write() for cell data
- close() for file finalization

Format methods:
- set_bold(), set_color(), set_bg_color(), set_align()

=head1 MIGRATION

For your exportToExcel subroutine:
- Change 'require Excel::Writer::XLSX;' to 'use ExcelHelper;'

All existing code works without modification.

=head1 SEE ALSO

L<CPANBridge>, L<Excel::Writer::XLSX>

=cut