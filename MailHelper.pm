package MailHelper;

use strict;
use warnings;
use CPANBridge;
use File::Basename;
use Carp;

our $VERSION = '1.0';

# Compatibility with Mail::Sender
our $NO_X_MAILER = 1;
our $Error = '';

sub new {
    my ($class, %args) = @_;
    
    my $self = {
        bridge => CPANBridge->new(debug => $args{debug} || 0),
        smtp => $args{smtp} || 'localhost',
        from => $args{from},
        to => $args{to},
        subject => $args{subject},
        last_error => undef,
        _multipart_data => {},
        _attachments => [],
    };
    
    bless $self, $class;
    return $self;
}

# Mail::Sender compatibility - method chaining style
sub OpenMultipart {
    my ($self, $params) = @_;
    
    # Store multipart headers
    $self->{_multipart_data} = {
        smtp => $params->{smtp} || $self->{smtp} || 'localhost',
        from => $params->{from} || $self->{from},
        to => $params->{to} || $self->{to},
        subject => $params->{subject} || $self->{subject},
        headers => $params->{headers} || {},
        multipart => $params->{multipart} || 'mixed',
        boundary => $params->{boundary},
    };
    
    # Clear any previous attachments
    $self->{_attachments} = [];
    
    return $self;  # Enable method chaining
}

sub Attach {
    my ($self, $params) = @_;
    
    unless (exists $params->{file}) {
        $Error = "No file specified for attachment";
        $self->{last_error} = $Error;
        croak $Error;
    }
    
    # Store attachment info
    push @{$self->{_attachments}}, {
        file => $params->{file},
        description => $params->{description} || "Attached file",
        ctype => $params->{ctype} || 'application/octet-stream',
        encoding => $params->{encoding} || 'base64',
        disposition => $params->{disposition} || 'attachment; filename=' . basename($params->{file}),
        name => $params->{name} || basename($params->{file}),
    };
    
    return $self;  # Enable method chaining
}

sub Body {
    my ($self, $params) = @_;
    
    # Store body content
    if (ref $params eq 'HASH') {
        $self->{_body} = $params->{msg} || $params->{body} || '';
        $self->{_body_encoding} = $params->{encoding} || 'quoted-printable';
    } else {
        $self->{_body} = $params;
        $self->{_body_encoding} = 'quoted-printable';
    }
    
    return $self;  # Enable method chaining
}

sub Close {
    my $self = shift;
    
    # Validate we have required data
    unless ($self->{_multipart_data}->{from}) {
        $Error = "From address required";
        $self->{last_error} = $Error;
        croak $Error;
    }
    
    unless ($self->{_multipart_data}->{to}) {
        $Error = "To address required";
        $self->{last_error} = $Error;
        croak $Error;
    }
    
    # Prepare data for Python
    my $email_data = {
        smtp_host => $self->{_multipart_data}->{smtp},
        from => $self->{_multipart_data}->{from},
        to => $self->{_multipart_data}->{to},
        subject => $self->{_multipart_data}->{subject} || '',
        body => $self->{_body} || '',
        body_encoding => $self->{_body_encoding} || 'quoted-printable',
        attachments => $self->{_attachments},
        headers => $self->{_multipart_data}->{headers} || {},
        multipart_type => $self->{_multipart_data}->{multipart} || 'mixed',
    };
    
    # Send via bridge
    my $result = $self->{bridge}->call_python('email_helper', 'send_multipart', $email_data);
    
    if (!$result->{success}) {
        $Error = $result->{error};
        $self->{last_error} = $Error;
        croak $Error;
    }
    
    return $self;
}

# Alternative methods for simple sending (Mail::Sender compatibility)
sub MailFile {
    my ($self, $params) = @_;
    
    # Simple file sending
    my $email_data = {
        smtp_host => $params->{smtp} || $self->{smtp} || 'localhost',
        from => $params->{from} || $self->{from},
        to => $params->{to} || $self->{to},
        subject => $params->{subject} || $self->{subject},
        msg => $params->{msg} || '',
        file => $params->{file},
    };
    
    unless ($email_data->{file}) {
        $Error = "No file specified";
        $self->{last_error} = $Error;
        return -1;
    }
    
    my $result = $self->{bridge}->call_python('email_helper', 'send_with_file', $email_data);
    
    if (!$result->{success}) {
        $Error = $result->{error};
        $self->{last_error} = $Error;
        return -1;
    }
    
    return 1;
}

sub MailMsg {
    my ($self, $params) = @_;
    
    # Simple message sending
    my $email_data = {
        smtp_host => $params->{smtp} || $self->{smtp} || 'localhost',
        from => $params->{from} || $self->{from},
        to => $params->{to} || $self->{to},
        subject => $params->{subject} || $self->{subject},
        msg => $params->{msg} || '',
    };
    
    my $result = $self->{bridge}->call_python('email_helper', 'send_simple', $email_data);
    
    if (!$result->{success}) {
        $Error = $result->{error};
        $self->{last_error} = $Error;
        return -1;
    }
    
    return 1;
}

# Utility methods
sub GetError {
    my $self = shift;
    return ref($self) ? $self->{last_error} : $Error;
}

sub DESTROY {
    # Cleanup if needed
}

1;
