# File: SFTPHelper.pm
package SFTPHelper;

use strict;
use warnings;
use CPANBridge;
use Carp;

our $VERSION = '1.00';

# Main SFTPHelper class - Net::SFTP::Foreign replacement
package SFTPHelper;
use strict;
use warnings;
use base 'CPANBridge';

sub new {
    my $class = shift;
    my %args;

    # Handle Net::SFTP::Foreign calling pattern: new($host, %options)
    if (@_ && $_[0] && !ref($_[0]) && $_[0] !~ /^(host|user|password|port|timeout|more)$/) {
        # First argument is host (positional)
        my $host = shift;
        %args = @_;
        $args{host} = $host;
    } else {
        # Named parameters only: new(host => $host, ...)
        %args = @_;
    }

    my $self = $class->SUPER::new(%args);

    # Net::SFTP::Foreign specific configuration
    $self->{host} = $args{host} || '';
    $self->{user} = $args{user} || '';
    $self->{password} = $args{password} || '';
    $self->{port} = $args{port} || 22;
    $self->{timeout} = $args{timeout} || 60;
    $self->{more} = $args{more} || [];
    $self->{connected} = 0;
    $self->{current_dir} = undef;
    $self->{last_error} = undef;

    # Parse SSH options from 'more' parameter
    $self->{ssh_options} = $self->_parse_ssh_options($args{more});

    # Establish connection
    $self->_connect();

    return $self;
}

# Parse SSH options from more parameter (your IdentityFile pattern)
sub _parse_ssh_options {
    my ($self, $more_options) = @_;
    
    my $ssh_opts = {};
    
    if ($more_options && ref($more_options) eq 'ARRAY') {
        for (my $i = 0; $i < @$more_options; $i += 2) {
            if ($more_options->[$i] eq '-o' && $i + 1 < @$more_options) {
                my $option = $more_options->[$i + 1];
                if ($option =~ /^IdentityFile=(.+)$/) {
                    $ssh_opts->{identity_file} = $1;
                } elsif ($option =~ /^(\w+)=(.+)$/) {
                    $ssh_opts->{lc($1)} = $2;
                }
            }
        }
    }
    
    return $ssh_opts;
}

# Establish SFTP connection
sub _connect {
    my $self = shift;
    
    croak "Host required for SFTP connection" unless $self->{host};
    croak "User required for SFTP connection" unless $self->{user};
    
    # Prepare connection parameters
    my $params = {
        host => $self->{host},
        user => $self->{user},
        port => $self->{port},
        timeout => $self->{timeout},
    };
    
    # Add authentication
    if ($self->{password}) {
        $params->{password} = $self->{password};
    }
    
    # Add SSH options (IdentityFile, etc.)
    if ($self->{ssh_options} && %{$self->{ssh_options}}) {
        $params->{ssh_options} = $self->{ssh_options};
    }
    
    # Add 'more' parameter for SSH options (matches sftp.py new() function)
    if ($self->{more} && @{$self->{more}}) {
        $params->{more} = $self->{more};
    }

    # Connect via Python backend using 'new' function
    my $result = $self->call_python('sftp', 'new', $params);

    if ($result->{success}) {
        $self->{connected} = 1;
        $self->{session_id} = $result->{result}->{session_id};
        $self->{current_dir} = $result->{result}->{initial_dir} || '/';
        $self->{last_error} = undef;
    } else {
        # Connection failed - set error but don't die (Net::SFTP::Foreign pattern)
        $self->{connected} = 0;
        $self->{session_id} = undef;
        $self->{current_dir} = undef;
        $self->{last_error} = "SFTP connection failed: $result->{error}";
    }
}

# File upload operation (your main usage pattern)
sub put {
    my ($self, $local_file, $remote_file) = @_;
    
    croak "Not connected to SFTP server" unless $self->{connected};
    croak "Local file path required" unless $local_file;
    croak "Remote file path required" unless $remote_file;
    
    # Prepare put parameters
    my $params = {
        session_id => $self->{session_id},
        local_file => $local_file,
        remote_file => $remote_file,
    };
    
    # Execute put operation via Python backend
    my $result = $self->call_python('sftp', 'put', $params);

    # Result is wrapped: {success => 1, result => {...}} or {success => 0, error => ...}
    if ($result->{success}) {
        # Success case
        $self->{last_error} = undef;
        return 1;  # Success
    } else {
        # Error case
        $self->{last_error} = $result->{error};
        return 0;  # Failure
    }
}

# Directory listing with pattern support (your ls usage)
sub ls {
    my $self = shift;

    croak "Not connected to SFTP server" unless $self->{connected};

    # Handle different calling patterns
    # ls() - list current directory
    # ls($dir) - list specific directory
    # ls(wanted => qr/pattern/) - list with pattern in current dir
    # ls($dir, wanted => qr/pattern/) - list with pattern in specific dir

    my $dir_to_list;
    my $wanted_pattern;

    # Parse arguments
    if (@_ == 0) {
        # ls() - no arguments
        $dir_to_list = $self->{current_dir};
    } elsif (@_ == 1 && !ref($_[0])) {
        # ls($dir) - single directory argument
        $dir_to_list = $_[0];
    } elsif (@_ == 1 && ref($_[0]) eq 'Regexp') {
        # ls(qr/pattern/) - single regex argument (unusual but possible)
        $dir_to_list = $self->{current_dir};
        $wanted_pattern = $_[0];
    } elsif (@_ % 2 == 0) {
        # Even number of args - it's a hash
        my %args = @_;
        $dir_to_list = $self->{current_dir};
        $wanted_pattern = $args{wanted};
    } elsif (@_ >= 2 && @_ % 2 == 1) {
        # Odd number >= 3: $dir, key => value, ...
        $dir_to_list = shift;
        my %args = @_;
        $wanted_pattern = $args{wanted};
    } else {
        # Fallback
        $dir_to_list = $self->{current_dir};
    }
    
    # Prepare ls parameters
    my $params = {
        session_id => $self->{session_id},
        remote_dir => $dir_to_list,
    };
    
    # Convert regex pattern to string for Python
    if ($wanted_pattern) {
        if (ref($wanted_pattern) eq 'Regexp') {
            my $pattern_str = "$wanted_pattern";
            $pattern_str =~ s/^\(\?\^?:?//;  # Remove (?^: prefix
            $pattern_str =~ s/\)$//;         # Remove trailing )
            $pattern_str =~ s/^\(\?\-xism://; # Remove (?-xism: prefix
            $params->{wanted} = $pattern_str;
        } else {
            $params->{wanted} = $wanted_pattern;
        }
    }
    
    # Execute ls operation via Python backend
    my $result = $self->call_python('sftp', 'ls', $params);

    # Result is wrapped: {success => 1, result => [entries]} or {success => 0, error => ...}
    # Note: result is directly the array, not {entries: [...]}
    if ($result->{success}) {
        # Success case
        $self->{last_error} = undef;
        return $result->{result};  # Returns array ref of file entries directly
    } else {
        # Error case
        $self->{last_error} = $result->{error};
        return [];  # Return empty list on error
    }
}

# File rename operation (your rename workflow)
sub rename {
    my ($self, $old_name, $new_name, %args) = @_;
    
    croak "Not connected to SFTP server" unless $self->{connected};
    croak "Old filename required" unless $old_name;
    croak "New filename required" unless $new_name;
    
    # Prepare rename parameters
    my $params = {
        session_id => $self->{session_id},
        old_name => $old_name,
        new_name => $new_name,
        overwrite => $args{overwrite} || 0,
    };
    
    # Execute rename operation via Python backend
    my $result = $self->call_python('sftp', 'rename', $params);

    # Result is wrapped: {success => 1, result => {...}} or {success => 0, error => ...}
    if ($result->{success}) {
        # Success case
        $self->{last_error} = undef;
        return 1;  # Success
    } else {
        # Error case
        $self->{last_error} = $result->{error};
        return 0;  # Failure
    }
}

# Change working directory (your setcwd usage)
sub setcwd {
    my ($self, $remote_dir) = @_;
    
    croak "Not connected to SFTP server" unless $self->{connected};
    croak "Remote directory required" unless $remote_dir;
    
    # Prepare setcwd parameters
    my $params = {
        session_id => $self->{session_id},
        remote_dir => $remote_dir,
    };
    
    # Execute setcwd operation via Python backend
    my $result = $self->call_python('sftp', 'setcwd', $params);

    # Result is wrapped: {success => 1, result => {...}} or {success => 0, error => ...}
    if ($result->{success}) {
        # Success case
        $self->{current_dir} = $result->{result}->{current_dir};
        $self->{last_error} = undef;
        return 1;  # Success
    } else {
        # Error case
        $self->{last_error} = $result->{error};
        return 0;  # Failure
    }
}

# Get current working directory (your cwd usage)
sub cwd {
    my $self = shift;
    
    croak "Not connected to SFTP server" unless $self->{connected};
    
    return $self->{current_dir};
}

# Error handling (your $sftp->error pattern)
sub error {
    my $self = shift;
    
    return $self->{last_error};
}

# Check if connection is active
sub is_connected {
    my $self = shift;
    
    return $self->{connected};
}

# Disconnect (cleanup)
sub disconnect {
    my $self = shift;
    
    return unless $self->{connected};
    
    # Disconnect via Python backend
    my $params = {
        session_id => $self->{session_id},
    };
    
    my $result = $self->call_python('sftp', 'disconnect', $params);
    
    $self->{connected} = 0;
    $self->{session_id} = undef;
    $self->{current_dir} = undef;
    
    return $result->{success} || 1;  # Always return success for compatibility
}

# Additional operations that might be needed
sub get {
    my ($self, $remote_file, $local_file) = @_;
    
    croak "Not connected to SFTP server" unless $self->{connected};
    croak "Remote file path required" unless $remote_file;
    croak "Local file path required" unless $local_file;
    
    my $params = {
        session_id => $self->{session_id},
        remote_file => $remote_file,
        local_file => $local_file,
    };
    
    my $result = $self->call_python('sftp', 'get', $params);

    # Result is wrapped: {success => 1, result => {...}} or {success => 0, error => ...}
    if ($result->{success}) {
        # Success case
        $self->{last_error} = undef;
        return 1;
    } else {
        # Error case
        $self->{last_error} = $result->{error};
        return 0;
    }
}

sub mkdir {
    my ($self, $remote_dir) = @_;

    croak "Not connected to SFTP server" unless $self->{connected};
    croak "Remote directory required" unless $remote_dir;

    my $params = {
        session_id => $self->{session_id},
        remote_dir => $remote_dir,
    };

    my $result = $self->call_python('sftp', 'mkdir', $params);

    # Result is wrapped: {success => 1, result => {...}} or {success => 0, error => ...}
    if ($result->{success}) {
        # Success case
        $self->{last_error} = undef;
        return 1;
    } else {
        # Error case
        $self->{last_error} = $result->{error};
        return 0;
    }
}

sub remove {
    my ($self, $remote_file) = @_;

    croak "Not connected to SFTP server" unless $self->{connected};
    croak "Remote file required" unless $remote_file;

    my $params = {
        session_id => $self->{session_id},
        remote_file => $remote_file,
    };

    my $result = $self->call_python('sftp', 'remove', $params);

    # Result is wrapped: {success => 1, result => {...}} or {success => 0, error => ...}
    if ($result->{success}) {
        # Success case
        $self->{last_error} = undef;
        return 1;
    } else {
        # Error case
        $self->{last_error} = $result->{error};
        return 0;
    }
}

# Cleanup on destruction
sub DESTROY {
    my $self = shift;
    $self->disconnect() if $self->{connected};
}

# Export compatibility
sub import {
    my $class = shift;
    my $caller = caller;
    
    # Create Net::SFTP::Foreign compatibility
    {
        no strict 'refs';
        *{"${caller}::Net::SFTP::Foreign::new"} = sub {
            shift;  # Remove class name
            return SFTPHelper->new(@_);
        };
    }
}

1;

__END__

=head1 NAME

SFTPHelper - Net::SFTP::Foreign replacement using Python backend

=head1 SYNOPSIS

    # Replace: use Net::SFTP::Foreign;
    use SFTPHelper;
    
    # Your existing code works unchanged:
    @sftp_args = ( host => $rHost , user => $rUser , timeout => $timeOut ) ;
    if ( $rPass !~ /IdentityFile|keyed/i ) { 
        push @sftp_args, ( password => $rPass );
    }
    if ( $rPort !~ /^NONE$/ ) { 
        push @sftp_args, ( port => $rPort );
    }
    if ( $idFile !~ /^NONE$/ ) {
        $idFile = "IdentityFile="."$idFile" ; 
        @moreOptions = ( "-o", "$idFile" ) ; 
        push @sftp_args, ( more => [@moreOptions]) ;
    }
    
    $sftp = Net::SFTP::Foreign->new( @sftp_args );
    $sftp->error and die "unable to connect to remote host $rHost: " . $sftp->error;
    
    # File operations
    $sftp->put("$lFile", "$rFile") or die "SFTP failed: " . $sftp->error;
    $sftp->setcwd($rDir) or die "Failed to change directory: " . $sftp->error;
    $sftp->rename("$tempFile", "$finalFile", overwrite => 1) or die "Rename failed: " . $sftp->error;
    
    # Directory listing with patterns
    $ls = $sftp->ls( wanted => qr/$rFile/);
    for $e (@$ls) { print "$e->{longname}\n"; }

=head1 DESCRIPTION

SFTPHelper provides a drop-in replacement for Net::SFTP::Foreign by routing
SFTP operations through a Python backend that uses paramiko or other SFTP libraries.

Supports all patterns from your usage analysis:
- Password and SSH key authentication
- IdentityFile via more => ["-o", "IdentityFile=path"] 
- put(), ls(), rename(), setcwd(), cwd()
- Regex patterns in ls() operations
- Rename-after-upload workflows
- Comprehensive error handling

=head1 METHODS

All Net::SFTP::Foreign methods from your analysis are supported:
- new() with host, user, password, port, timeout, more parameters
- put() for file uploads
- ls() with wanted regex patterns
- rename() with overwrite option
- setcwd() and cwd() for directory operations
- error() for error messages

=head1 MIGRATION

Change only the use statement:
- Replace 'use Net::SFTP::Foreign;' with 'use SFTPHelper;'

All existing code works without modification.

=head1 SEE ALSO

L<CPANBridge>, L<Net::SFTP::Foreign>

=cut