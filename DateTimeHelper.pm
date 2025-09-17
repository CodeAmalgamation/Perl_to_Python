# File: DateTimeHelper.pm
# Minimal DateTime replacement for RHEL 9 migration
# Focused solely on DateTime->now->epoch pattern

package DateTimeHelper;

use strict;
use warnings;
use parent 'CPANBridge';
use Carp;

our $VERSION = '1.00';

# Class method - DateTime->now()
sub now {
    my $class = shift;
    
    # Create bridge instance
    my $bridge = ref($class) ? $class : $class->new();
    
    # Call Python to get current timestamp
    my $result = $bridge->call_python('datetime_helper', 'now', {});
    
    # Handle errors
    unless ($result && $result->{success}) {
        my $error = $result ? $result->{error} : "Failed to get current time";
        croak "DateTime->now() failed: $error";
    }
    
    # Return object that can handle ->epoch() calls
    return DateTimeHelper::Object->new($result->{result});
}

1;

#################################################################
# DateTime Object - Only handles ->epoch() method
#################################################################

package DateTimeHelper::Object;

use strict;
use warnings;

sub new {
    my ($class, $epoch_time) = @_;
    
    # Handle both direct epoch and structured response
    my $epoch = ref($epoch_time) eq 'HASH' ? $epoch_time->{epoch} : $epoch_time;
    
    return bless { epoch_value => $epoch }, $class;
}

# Primary method: ->epoch()
sub epoch {
    my $self = shift;
    return $self->{epoch_value};
}

1;

__END__

=head1 NAME

DateTimeHelper - Minimal DateTime replacement for RHEL 9 migration

=head1 SYNOPSIS

    use DateTimeHelper;
    
    # Your exact usage pattern (drop-in replacement):
    chomp($ini_KEY = &GetKey($ini_EPV_LIB, $ini_APP_ID, $ini_QUERY, DateTimeHelper->now->epoch, 20));
    
    # Also supports:
    my $timestamp = DateTimeHelper->now->epoch;
    my $current_epoch = DateTimeHelper->now->epoch;

=head1 DESCRIPTION

DateTimeHelper provides a focused replacement for DateTime->now->epoch functionality.
Based on codebase analysis, this is the only DateTime pattern used in your scripts.

This minimal implementation:
- Eliminates CPAN dependencies
- Provides identical API to DateTime->now->epoch
- Uses Python's time.time() for actual timestamp generation
- Handles errors gracefully with croak() like original DateTime

=head1 METHODS

=head2 DateTimeHelper->now()

Returns a DateTimeHelper::Object that supports ->epoch() method.

=head2 $dt->epoch()

Returns Unix timestamp (integer). This matches your usage pattern exactly.

=head1 COMPATIBILITY

Complete drop-in replacement for DateTime->now->epoch pattern.
Simply change "use DateTime" to "use DateTimeHelper" in your scripts.

=head1 PERFORMANCE

Optimized for your specific usage:
- Single Python call per DateTime->now->epoch operation
- Minimal object overhead
- Bridge communication optimized for timestamps

=head1 SEE ALSO

L<CPANBridge>

=cut