package OpenSSHHelper;

=head1 NAME

OpenSSHHelper - Net::OpenSSH Replacement using Python paramiko backend

=head1 SYNOPSIS

    use OpenSSHHelper;

    # Create SSH connection
    my $ssh = OpenSSHHelper->new(
        host     => 'remote.host.com',
        user     => 'username',
        port     => 22,              # optional, default 22
        timeout  => 30,              # optional, default 30
        password => 'secret',        # OR
        key_path => '/path/to/key'   # for key-based auth
    );

    # Check for connection errors
    if ($ssh->error) {
        die "Connection failed: " . $ssh->error;
    }

    # Upload file via SCP
    my $result = $ssh->scp_put('/local/file.txt', '/remote/path/file.txt');

    # Upload with permissions
    $result = $ssh->scp_put(
        { perm => oct('0644'), umask => oct('0022') },
        '/local/file.txt',
        '/remote/path/file.txt'
    );

    # Check for transfer errors
    if (!$result) {
        warn "Upload failed: " . $ssh->error;
    }

    # Disconnect
    $ssh->disconnect();

=head1 DESCRIPTION

Drop-in replacement for Net::OpenSSH using Python paramiko backend.
Provides SSH connectivity and SCP file transfer capabilities.

Based on Net::OpenSSH usage analysis from mi_ftp_unix_fw.pl:
- Only implements required methods: new(), scp_put(), error(), disconnect()
- Constructor returns object even on connection failure (error via ->error())
- Supports password and key-based authentication
- File permissions and umask options for scp_put()

=cut

use strict;
use warnings;
use base 'CPANBridge';
use Carp qw(croak carp);

our $VERSION = '1.0.0';

=head1 METHODS

=head2 new(%params)

Create SSH connection (mimics Net::OpenSSH->new())

Parameters:
    host     => Remote hostname/IP (required)
    user     => SSH username (required)
    port     => SSH port (default: 22)
    timeout  => Connection timeout in seconds (default: 30)
    password => Password authentication (optional)
    key_path => Private key file path (optional)

Returns: OpenSSHHelper object (even on connection failure)
         Check ->error() for connection errors

Like Net::OpenSSH, constructor doesn't die on failure.
Connection errors are retrieved via ->error() method.

=cut

sub new {
    my $class = shift;
    $class = ref($class) || $class;

    # Parse parameters (hash or hashref)
    my %params;
    if (@_ == 1 && ref($_[0]) eq 'HASH') {
        %params = %{$_[0]};
    } else {
        %params = @_;
    }

    # Extract SSH connection parameters
    my $host     = delete $params{host}     || croak "host parameter is required";
    my $user     = delete $params{user}     || croak "user parameter is required";
    my $port     = delete $params{port}     || 22;
    my $timeout  = delete $params{timeout}  || 30;
    my $password = delete $params{password};
    my $key_path = delete $params{key_path};

    # Create base object
    my $self = $class->SUPER::new();

    # Store connection parameters
    $self->{_ssh_params} = {
        host     => $host,
        user     => $user,
        port     => $port,
        timeout  => $timeout,
        password => $password,
        key_path => $key_path,
    };

    # Initialize error state
    $self->{_error} = undef;
    $self->{_connection_id} = undef;
    $self->{_connected} = 0;

    # Attempt connection via Python backend
    my $result = $self->call_python('openssh', 'new', {
        host     => $host,
        user     => $user,
        port     => $port,
        timeout  => $timeout,
        password => $password,
        key_path => $key_path,
    });

    if (!$result->{success}) {
        # Python call failed
        $self->{_error} = "Failed to create SSH connection: " . ($result->{error} || 'unknown error');
        return $self;  # Return object with error set
    }

    # Extract connection info
    my $conn_info = $result->{result};
    $self->{_connection_id} = $conn_info->{connection_id};
    $self->{_connected} = $conn_info->{connected} || 0;

    # If connection failed, retrieve error
    if (!$self->{_connected}) {
        my $error_result = $self->call_python('openssh', 'get_error', {
            connection_id => $self->{_connection_id}
        });

        if ($error_result->{success}) {
            $self->{_error} = $error_result->{result};
        } else {
            $self->{_error} = "Connection failed (error details unavailable)";
        }
    }

    return $self;
}

=head2 scp_put($local_file, $remote_file)

=head2 scp_put(\%options, $local_file, $remote_file)

Upload file via SCP (mimics Net::OpenSSH->scp_put())

Parameters:
    \%options    => Optional hashref with:
                    - perm: File permissions (octal)
                    - umask: File creation mask (octal)
    $local_file  => Local file path
    $remote_file => Remote file path

Returns: True on success, false/undef on failure
         Use ->error() to get error message

Examples:
    $ssh->scp_put('/local/file.txt', '/remote/file.txt');

    $ssh->scp_put(
        { perm => oct('0644') },
        '/local/file.txt',
        '/remote/file.txt'
    );

=cut

sub scp_put {
    my $self = shift;

    # Parse arguments: either (options, local, remote) or (local, remote)
    my ($options, $local_file, $remote_file);

    if (@_ == 3) {
        # Options provided
        ($options, $local_file, $remote_file) = @_;
        if (ref($options) ne 'HASH') {
            croak "First argument must be a hashref when 3 arguments provided";
        }
    } elsif (@_ == 2) {
        # No options
        ($local_file, $remote_file) = @_;
        $options = {};
    } else {
        croak "scp_put requires 2 or 3 arguments";
    }

    # Check connection
    if (!$self->{_connection_id}) {
        $self->{_error} = "Not connected";
        return undef;
    }

    # Clear previous error
    $self->{_error} = undef;

    # Call Python backend
    my $result = $self->call_python('openssh', 'scp_put', {
        connection_id => $self->{_connection_id},
        local_file    => $local_file,
        remote_file   => $remote_file,
        options       => $options
    });

    if (!$result->{success}) {
        $self->{_error} = "scp_put failed: " . ($result->{error} || 'unknown error');
        return undef;
    }

    my $transfer_result = $result->{result};

    if (!$transfer_result) {
        # Transfer failed - retrieve error
        my $error_result = $self->call_python('openssh', 'get_error', {
            connection_id => $self->{_connection_id}
        });

        if ($error_result->{success}) {
            $self->{_error} = $error_result->{result};
        } else {
            $self->{_error} = "Transfer failed (error details unavailable)";
        }

        return undef;
    }

    # Success (return 1 like Net::OpenSSH)
    return 1;
}

=head2 error()

Get last error message (mimics Net::OpenSSH->error())

Returns: Error string or undef if no error

Examples:
    if ($ssh->error) {
        die "Connection error: " . $ssh->error;
    }

    if (!$ssh->scp_put($local, $remote)) {
        warn "Upload failed: " . $ssh->error;
    }

=cut

sub error {
    my $self = shift;
    return $self->{_error};
}

=head2 disconnect()

Close SSH connection (mimics Net::OpenSSH->disconnect())

Safe to call multiple times.

=cut

sub disconnect {
    my $self = shift;

    return 1 unless $self->{_connection_id};  # Already disconnected

    # Call Python backend
    my $result = $self->call_python('openssh', 'disconnect', {
        connection_id => $self->{_connection_id}
    });

    # Clear connection state
    $self->{_connection_id} = undef;
    $self->{_connected} = 0;

    return 1;
}

=head2 DESTROY

Cleanup on object destruction

=cut

sub DESTROY {
    my $self = shift;

    # Auto-disconnect on destruction
    eval {
        $self->disconnect() if $self->{_connection_id};
    };
}

=head1 COMPATIBILITY NAMESPACE

To use as drop-in replacement for Net::OpenSSH, simply:

    use OpenSSHHelper;

And then use the Net::OpenSSH namespace:

    my $ssh = Net::OpenSSH->new(%params);

This works because OpenSSHHelper provides a compatibility shim.

=cut

# Provide Net::OpenSSH namespace for compatibility
package Net::OpenSSH;

sub new {
    shift;  # Discard class name
    return OpenSSHHelper->new(@_);
}

1;

=head1 DEPENDENCIES

Requires:
- CPANBridge.pm - Base class for Python bridge
- Python paramiko library (install: pip install paramiko)

=head1 BASED ON

Net::OpenSSH usage analysis from mi_ftp_unix_fw.pl
See Documentation/OpenSSH.txt for complete analysis

=head1 AUTHOR

Generated as part of Perl to Python migration project

=cut
