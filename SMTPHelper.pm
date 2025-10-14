# File: SMTPHelper.pm
# Net::SMTP replacement for RHEL 9 migration
# Provides drop-in compatibility with Net::SMTP using Python smtplib backend

package Net::SMTP;

use strict;
use warnings;
use parent 'CPANBridge';
use Carp;

our $VERSION = '1.00';

=head1 NAME

SMTPHelper - Net::SMTP replacement using Python smtplib backend

=head1 SYNOPSIS

    use SMTPHelper;  # Overrides Net::SMTP namespace

    # Your existing Net::SMTP code works unchanged:
    my $smtp = Net::SMTP->new('sslmsmtp', Timeout => 30, Debug => 0)
        or die "with error $!";

    $smtp->mail("sender@domain.com");
    $smtp->to("recipient@domain.com");
    $smtp->data();
    $smtp->datasend("To: recipient@domain.com\n");
    $smtp->datasend("From: sender@domain.com\n");
    $smtp->datasend("Subject: Test Email\n");
    $smtp->datasend("\n");
    foreach my $line (@body) {
        $smtp->datasend($line);
    }
    $smtp->datasend();  # Flush and send
    $smtp->quit();

=head1 DESCRIPTION

SMTPHelper provides a drop-in replacement for Net::SMTP that works without
CPAN dependencies by routing operations through Python's smtplib module.

This implementation:
- Maintains connection state across method calls using daemon connection pooling
- Supports all Net::SMTP methods used in production code
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

    # Extract Net::SMTP constructor parameters
    my $port = $args{Port} || 25;
    my $timeout = $args{Timeout} || 30;
    my $debug = $args{Debug} || 0;
    my $localhost = $args{Hello} || $args{LocalAddr} || undef;

    # Call Python backend to create SMTP connection
    my $result = $self->call_python('smtp_helper', 'new', {
        host => $host,
        port => $port,
        timeout => $timeout,
        debug => $debug,
        localhost => $localhost
    });

    # Handle connection failure (match Net::SMTP behavior)
    unless ($result && $result->{success}) {
        my $error = $result ? $result->{error} : "Connection failed";
        $! = $error;
        return undef;
    }

    # Store connection ID for subsequent method calls
    $self->{_connection_id} = $result->{connection_id};
    $self->{_host} = $host;
    $self->{_port} = $port;

    return $self;
}

=head2 mail($sender)

Set the sender address for the email.

    $smtp->mail("sender@domain.com");

Returns true on success, false on failure.

=cut

sub mail {
    my ($self, $sender) = @_;

    unless (defined $sender) {
        carp "mail() requires sender address";
        return 0;
    }

    unless ($self->{_connection_id}) {
        carp "mail() called on closed connection";
        return 0;
    }

    my $result = $self->call_python('smtp_helper', 'mail', {
        connection_id => $self->{_connection_id},
        sender => $sender
    });

    unless ($result && $result->{success}) {
        my $error = $result ? $result->{error} : "mail() failed";
        carp $error;
        return 0;
    }

    return 1;
}

=head2 to($recipient)

Add a recipient address for the email.

    $smtp->to("recipient@domain.com");

Returns true on success, false on failure.

=cut

sub to {
    my ($self, $recipient) = @_;

    unless (defined $recipient) {
        carp "to() requires recipient address";
        return 0;
    }

    unless ($self->{_connection_id}) {
        carp "to() called on closed connection";
        return 0;
    }

    my $result = $self->call_python('smtp_helper', 'to', {
        connection_id => $self->{_connection_id},
        recipient => $recipient
    });

    unless ($result && $result->{success}) {
        my $error = $result ? $result->{error} : "to() failed";
        carp $error;
        return 0;
    }

    return 1;
}

=head2 data()

Start the message data transmission.

    $smtp->data();

Must be called after mail() and to(), before datasend().
Returns true on success, false on failure.

=cut

sub data {
    my $self = shift;

    unless ($self->{_connection_id}) {
        carp "data() called on closed connection";
        return 0;
    }

    my $result = $self->call_python('smtp_helper', 'data', {
        connection_id => $self->{_connection_id}
    });

    unless ($result && $result->{success}) {
        my $error = $result ? $result->{error} : "data() failed";
        carp $error;
        return 0;
    }

    return 1;
}

=head2 datasend($data)

Send message data. Can be called multiple times to build the message.
Call with no arguments to flush the buffer and complete the message.

    $smtp->datasend("To: recipient@domain.com\n");
    $smtp->datasend("From: sender@domain.com\n");
    $smtp->datasend("Subject: Test\n");
    $smtp->datasend("\n");
    $smtp->datasend("Body content");
    $smtp->datasend();  # Flush and send

Returns true on success, false on failure.

=cut

sub datasend {
    my ($self, $data) = @_;

    unless ($self->{_connection_id}) {
        carp "datasend() called on closed connection";
        return 0;
    }

    # Call Python backend with data (undef = flush)
    my $result = $self->call_python('smtp_helper', 'datasend', {
        connection_id => $self->{_connection_id},
        data => $data
    });

    unless ($result && $result->{success}) {
        my $error = $result ? $result->{error} : "datasend() failed";
        carp $error;
        return 0;
    }

    return 1;
}

=head2 quit()

Close the SMTP connection and clean up resources.

    $smtp->quit();

Returns true on success, false on failure.
After calling quit(), the connection object cannot be reused.

=cut

sub quit {
    my $self = shift;

    # Allow quit on already closed connection (idempotent)
    return 1 unless $self->{_connection_id};

    my $result = $self->call_python('smtp_helper', 'quit', {
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

This module provides 100% API compatibility with Net::SMTP for the methods
used in production code:

- new($host, %options)
- mail($sender)
- to($recipient)
- data()
- datasend($data)
- quit()

Error handling matches Net::SMTP behavior:
- Constructor returns undef on failure and sets $!
- Methods return false on failure and issue warnings via carp

=head1 PRODUCTION USAGE

From 30165CbiWasCtl.pl:

    foreach my $who ( @{$recipient} ) {
        my $smtp = Net::SMTP->new('sslmsmtp', Timeout => 30, Debug => 0)
            || die("with error $!");

        $smtp->mail("SLM-ReleaseManagement\@ChasePaymentech.com");
        $smtp->to("${who}\@paymentech.com");
        $smtp->data();
        $smtp->datasend("To: ${who}\@paymentech.com\n");
        $smtp->datasend("From: SLM-ReleaseManagement\@chasepaymentech.com\n");
        $smtp->datasend("Subject: $email_subject\n");
        $smtp->datasend("\n");
        foreach my $e_line ( @{$email_body} ) {
            $smtp->datasend("$e_line");
        }
        $smtp->datasend();
        $smtp->quit();
    }

This code works unchanged with SMTPHelper.

=head1 ARCHITECTURE

SMTPHelper uses the CPAN Bridge daemon for persistent connection management:

1. new() creates a connection and returns a unique connection_id
2. Connection state is maintained in Python backend connection pool
3. All methods pass connection_id to identify their connection
4. Connections auto-cleanup after 5 minutes of inactivity
5. quit() explicitly removes connection from pool

This architecture ensures:
- Multiple datasend() calls work on the same SMTP session
- Connection state persists across Perl -> Python bridge calls
- Proper resource cleanup even if quit() is not called

=head1 SEE ALSO

L<CPANBridge>, L<Net::SMTP>

=head1 AUTHOR

CPAN Bridge Migration Project

=cut

1;

__END__
