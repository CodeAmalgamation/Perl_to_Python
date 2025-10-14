# File: FTPHelper.pm
# Net::FTP replacement for RHEL 9 migration
# Provides drop-in compatibility with Net::FTP using Python ftplib backend

package Net::FTP;

use strict;
use warnings;
use parent 'CPANBridge';
use Carp;

our $VERSION = '1.00';

=head1 NAME

FTPHelper - Net::FTP replacement using Python ftplib backend

=head1 SYNOPSIS

    use FTPHelper;  # Overrides Net::FTP namespace

    # Your existing Net::FTP code works unchanged:
    my $ftp = Net::FTP->new('ftp.example.com', Debug => 0, Timeout => 60)
        or die "Cannot connect: $!";

    $ftp->login('username', 'password')
        or die "Cannot login: ", $ftp->message;

    $ftp->cwd('/pub/files')
        or die "Cannot change directory: ", $ftp->message;

    $ftp->binary();
    $ftp->get('remote.txt', 'local.txt')
        or die "Get failed: ", $ftp->message;

    $ftp->put('local.txt', 'remote.txt')
        or die "Put failed: ", $ftp->message;

    $ftp->quit();

=head1 DESCRIPTION

FTPHelper provides a drop-in replacement for Net::FTP that works without
CPAN dependencies by routing operations through Python's ftplib module.

This implementation:
- Maintains connection state across method calls using daemon connection pooling
- Supports all Net::FTP methods used in production code
- Preserves exact API compatibility including error handling
- Uses CPAN Bridge daemon for persistent connections

=head1 METHODS

=cut

sub new {
    my ($class, $host, %args) = @_;

    # Handle case where new() is called on an object instead of a class
    $class = ref($class) || $class;

    # Validate required parameters
    unless (defined $host) {
        $! = "No host specified";
        return undef;
    }

    # Create CPANBridge instance
    my $self = $class->SUPER::new();

    # Extract Net::FTP constructor parameters
    my $debug = $args{Debug} || 0;
    my $timeout = $args{Timeout} || 60;

    # Call Python backend to create FTP connection
    my $result = $self->call_python('ftp_helper', 'new', {
        host => $host,
        debug => $debug,
        timeout => $timeout
    });

    # Handle connection failure (match Net::FTP behavior)
    unless ($result && $result->{success}) {
        my $error = $result ? $result->{error} : "Connection failed";
        $! = $error;
        return undef;
    }

    # Store connection ID for subsequent method calls
    $self->{_connection_id} = $result->{connection_id};
    $self->{_host} = $host;

    return $self;
}

=head2 login($user, $password)

Authenticate with the FTP server.

    $ftp->login('username', 'password')
        or die "Login failed: ", $ftp->message;

Returns true on success, false on failure.

=cut

sub login {
    my ($self, $user, $password) = @_;

    unless (defined $user && defined $password) {
        carp "login() requires username and password";
        return 0;
    }

    unless ($self->{_connection_id}) {
        carp "login() called on closed connection";
        return 0;
    }

    my $result = $self->call_python('ftp_helper', 'login', {
        connection_id => $self->{_connection_id},
        user => $user,
        password => $password
    });

    unless ($result && $result->{success}) {
        my $error = $result ? $result->{error} : "login() failed";
        carp $error;
        return 0;
    }

    return 1;
}

=head2 cwd($directory)

Change working directory on the FTP server.

    $ftp->cwd('/pub/files')
        or die "Cannot change directory: ", $ftp->message;

Returns true on success, false on failure.

=cut

sub cwd {
    my ($self, $directory) = @_;

    unless (defined $directory) {
        carp "cwd() requires directory path";
        return 0;
    }

    unless ($self->{_connection_id}) {
        carp "cwd() called on closed connection";
        return 0;
    }

    my $result = $self->call_python('ftp_helper', 'cwd', {
        connection_id => $self->{_connection_id},
        directory => $directory
    });

    unless ($result && $result->{success}) {
        my $error = $result ? $result->{error} : "cwd() failed";
        carp $error;
        return 0;
    }

    return 1;
}

=head2 pwd()

Get current working directory on the FTP server.

    my $dir = $ftp->pwd()
        or die "PWD failed: ", $ftp->message;

Returns directory path on success, undef on failure.

=cut

sub pwd {
    my $self = shift;

    unless ($self->{_connection_id}) {
        carp "pwd() called on closed connection";
        return undef;
    }

    my $result = $self->call_python('ftp_helper', 'pwd', {
        connection_id => $self->{_connection_id}
    });

    unless ($result && $result->{success}) {
        my $error = $result ? $result->{error} : "pwd() failed";
        carp $error;
        return undef;
    }

    return $result->{directory};
}

=head2 dir([$path])

Get directory listing from the FTP server.

    my @files = $ftp->dir()
        or die "Directory listing failed: ", $ftp->message;

    my @files = $ftp->dir('/pub')
        or die "Directory listing failed: ", $ftp->message;

Returns list of files in list context, array reference in scalar context.
Returns empty list on failure.

=cut

sub dir {
    my ($self, $path) = @_;

    unless ($self->{_connection_id}) {
        carp "dir() called on closed connection";
        return wantarray ? () : [];
    }

    my $result = $self->call_python('ftp_helper', 'dir', {
        connection_id => $self->{_connection_id},
        path => $path || ""
    });

    unless ($result && $result->{success}) {
        my $error = $result ? $result->{error} : "dir() failed";
        carp $error;
        return wantarray ? () : [];
    }

    my @listing = @{$result->{listing}};
    return wantarray ? @listing : \@listing;
}

=head2 binary()

Set transfer mode to binary (TYPE I).

    $ftp->binary()
        or die "Cannot set binary mode: ", $ftp->message;

Returns true on success, false on failure.

=cut

sub binary {
    my $self = shift;

    unless ($self->{_connection_id}) {
        carp "binary() called on closed connection";
        return 0;
    }

    my $result = $self->call_python('ftp_helper', 'binary', {
        connection_id => $self->{_connection_id}
    });

    unless ($result && $result->{success}) {
        my $error = $result ? $result->{error} : "binary() failed";
        carp $error;
        return 0;
    }

    return 1;
}

=head2 ascii()

Set transfer mode to ASCII (TYPE A).

    $ftp->ascii()
        or die "Cannot set ASCII mode: ", $ftp->message;

Returns true on success, false on failure.

=cut

sub ascii {
    my $self = shift;

    unless ($self->{_connection_id}) {
        carp "ascii() called on closed connection";
        return 0;
    }

    my $result = $self->call_python('ftp_helper', 'ascii', {
        connection_id => $self->{_connection_id}
    });

    unless ($result && $result->{success}) {
        my $error = $result ? $result->{error} : "ascii() failed";
        carp $error;
        return 0;
    }

    return 1;
}

=head2 get($remote_file [, $local_file])

Download a file from the FTP server.

    $ftp->get('remote.txt', 'local.txt')
        or die "Download failed: ", $ftp->message;

    # Local file defaults to remote filename
    $ftp->get('remote.txt')
        or die "Download failed: ", $ftp->message;

Returns true on success, false on failure.

=cut

sub get {
    my ($self, $remote_file, $local_file) = @_;

    unless (defined $remote_file) {
        carp "get() requires remote file path";
        return 0;
    }

    unless ($self->{_connection_id}) {
        carp "get() called on closed connection";
        return 0;
    }

    my $result = $self->call_python('ftp_helper', 'get', {
        connection_id => $self->{_connection_id},
        remote_file => $remote_file,
        local_file => $local_file
    });

    unless ($result && $result->{success}) {
        my $error = $result ? $result->{error} : "get() failed";
        carp $error;
        return 0;
    }

    return 1;
}

=head2 put($local_file [, $remote_file])

Upload a file to the FTP server.

    $ftp->put('local.txt', 'remote.txt')
        or die "Upload failed: ", $ftp->message;

    # Remote file defaults to local filename
    $ftp->put('local.txt')
        or die "Upload failed: ", $ftp->message;

Returns true on success, false on failure.

=cut

sub put {
    my ($self, $local_file, $remote_file) = @_;

    unless (defined $local_file) {
        carp "put() requires local file path";
        return 0;
    }

    unless ($self->{_connection_id}) {
        carp "put() called on closed connection";
        return 0;
    }

    my $result = $self->call_python('ftp_helper', 'put', {
        connection_id => $self->{_connection_id},
        local_file => $local_file,
        remote_file => $remote_file
    });

    unless ($result && $result->{success}) {
        my $error = $result ? $result->{error} : "put() failed";
        carp $error;
        return 0;
    }

    return 1;
}

=head2 delete($remote_file)

Delete a file on the FTP server.

    $ftp->delete('remote.txt')
        or die "Delete failed: ", $ftp->message;

Returns true on success, false on failure.

=cut

sub delete {
    my ($self, $remote_file) = @_;

    unless (defined $remote_file) {
        carp "delete() requires remote file path";
        return 0;
    }

    unless ($self->{_connection_id}) {
        carp "delete() called on closed connection";
        return 0;
    }

    my $result = $self->call_python('ftp_helper', 'delete', {
        connection_id => $self->{_connection_id},
        remote_file => $remote_file
    });

    unless ($result && $result->{success}) {
        my $error = $result ? $result->{error} : "delete() failed";
        carp $error;
        return 0;
    }

    return 1;
}

=head2 rename($old_name, $new_name)

Rename a file on the FTP server.

    $ftp->rename('old.txt', 'new.txt')
        or die "Rename failed: ", $ftp->message;

Returns true on success, false on failure.

=cut

sub rename {
    my ($self, $old_name, $new_name) = @_;

    unless (defined $old_name && defined $new_name) {
        carp "rename() requires old and new file names";
        return 0;
    }

    unless ($self->{_connection_id}) {
        carp "rename() called on closed connection";
        return 0;
    }

    my $result = $self->call_python('ftp_helper', 'rename', {
        connection_id => $self->{_connection_id},
        old_name => $old_name,
        new_name => $new_name
    });

    unless ($result && $result->{success}) {
        my $error = $result ? $result->{error} : "rename() failed";
        carp $error;
        return 0;
    }

    return 1;
}

=head2 message()

Get last FTP server response message.

    my $msg = $ftp->message;

Returns the last response from the FTP server.

=cut

sub message {
    my $self = shift;

    unless ($self->{_connection_id}) {
        return "";
    }

    my $result = $self->call_python('ftp_helper', 'message', {
        connection_id => $self->{_connection_id}
    });

    if ($result && $result->{success}) {
        return $result->{message} || "";
    }

    return "";
}

=head2 quit()

Close the FTP connection and clean up resources.

    $ftp->quit();

Returns true on success, false on failure.
After calling quit(), the connection object cannot be reused.

=cut

sub quit {
    my $self = shift;

    # Allow quit on already closed connection (idempotent)
    return 1 unless $self->{_connection_id};

    my $result = $self->call_python('ftp_helper', 'quit', {
        connection_id => $self->{_connection_id}
    });

    # Mark connection as closed
    delete $self->{_connection_id};

    # quit() should always succeed even on errors
    return 1;
}

=head2 DESTROY

Automatic cleanup when object goes out of scope.
Ensures connection is properly closed even if quit() wasn't called.

=cut

sub DESTROY {
    my $self = shift;

    # Close connection if still open
    if ($self->{_connection_id}) {
        eval { $self->quit(); };
    }

    # Call parent destructor
    $self->SUPER::DESTROY() if $self->can('SUPER::DESTROY');
}

=head1 COMPATIBILITY

This module provides 100% API compatibility with Net::FTP for the methods
used in production code:

- new($host, %options)
- login($user, $password)
- cwd($directory)
- pwd()
- dir([$path])
- binary()
- ascii()
- get($remote_file, $local_file)
- put($local_file, $remote_file)
- delete($remote_file)
- rename($old_name, $new_name)
- message()
- quit()

Error handling matches Net::FTP behavior:
- Constructor returns undef on failure and sets $!
- Methods return false on failure and issue warnings via carp
- message() returns last server response

=head1 PRODUCTION USAGE

From CommonControlmSubs.pm:

    $ftp = Net::FTP->new( $server, Debug => 1 );
    if ( $ftp == NULL ) {
        &log_msg( "Could not connect to server.\n" );
        $myrc = 9;
    }

    if ( $ftp->login( $login, $password ) ) {
        if ( $ftp->cwd( $directory ) ) {
            if ( $ftp->get( $file ) ) {
                &log_msg( "FTP File retrieved successfully.\n" );
            } else {
                &log_msg( "Could not retrieve $file.\n" );
                $myrc = 4;
            }
        } else {
            &log_msg( "Could not change directory to $directory\n" );
            $myrc = 6;
        }
    } else {
        &log_msg( "Could not login with user: [$login] and password: [$password].\n" );
        $myrc = 7;
    }

    $ftp->quit();

This code works unchanged with FTPHelper.

=head1 ARCHITECTURE

FTPHelper uses the CPAN Bridge daemon for persistent connection management:

1. new() creates a connection and returns a unique connection_id
2. Connection state is maintained in Python backend connection pool
3. All methods pass connection_id to identify their connection
4. Connections auto-cleanup after 5 minutes of inactivity
5. quit() explicitly removes connection from pool

This architecture ensures:
- Connection state persists across Perl -> Python bridge calls
- Transfer mode (binary/ascii) is maintained
- Proper resource cleanup even if quit() is not called
- Thread-safe connection management

=head1 SEE ALSO

L<CPANBridge>, L<Net::FTP>

=head1 AUTHOR

CPAN Bridge Migration Project

=cut

1;

__END__
