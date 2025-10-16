# File: HTTPHelper.pm
package HTTPHelper;

use strict;
use warnings;
use CPANBridge;
use Carp;

our $VERSION = '1.00';

# HTTP::Request compatibility class
package HTTPHelper::Request;
use strict;
use warnings;

sub new {
    my ($class, $method, $url) = @_;
    
    my $self = {
        method => uc($method || 'GET'),
        url => $url,
        headers => {},
        content => '',
    };
    
    return bless $self, $class;
}

sub content_type {
    my ($self, $type) = @_;
    
    if (defined $type) {
        $self->{headers}->{'Content-Type'} = $type;
        return $self;
    }
    
    return $self->{headers}->{'Content-Type'};
}

sub content {
    my ($self, $content) = @_;
    
    if (defined $content) {
        $self->{content} = $content;
        return $self;
    }
    
    return $self->{content};
}

sub header {
    my ($self, $name, $value) = @_;
    
    if (defined $value) {
        $self->{headers}->{$name} = $value;
        return $self;
    }
    
    return $self->{headers}->{$name};
}

# HTTP::Response compatibility class  
package HTTPHelper::Response;
use strict;
use warnings;

sub new {
    my ($class, $response_data) = @_;
    
    my $self = {
        %{$response_data || {}},
        _headers => {},
    };
    
    # Parse headers if provided
    if ($response_data->{headers}) {
        $self->{_headers} = $response_data->{headers};
    }
    
    return bless $self, $class;
}

sub is_success { 
    my $self = shift; 
    return $self->{success} || ($self->{status_code} && $self->{status_code} >= 200 && $self->{status_code} < 300);
}

sub code { 
    my $self = shift; 
    return $self->{status_code} || ($self->is_success() ? 200 : 500);
}

sub status_line { 
    my $self = shift; 
    return $self->{status_line} || ($self->code() . " " . ($self->{reason} || "Unknown"));
}

sub message { 
    my $self = shift; 
    return $self->{reason} || $self->{error} || "OK";
}

sub content { 
    my $self = shift; 
    return $self->{content} || $self->{body} || "";
}

sub decoded_content {
    my $self = shift;
    return $self->content();  # For your usage, content and decoded_content are the same
}

# Main HTTPHelper class - LWP::UserAgent replacement
package HTTPHelper;
use strict;
use warnings;
use base 'CPANBridge';

sub new {
    my ($class, %args) = @_;
    
    my $self = $class->SUPER::new(%args);
    
    # LWP::UserAgent specific configuration
    $self->{agent} = $args{agent} || 'LWP::UserAgent/6.00';  # Default LWP agent string
    $self->{timeout} = $args{timeout} || 180;  # Default LWP timeout
    $self->{max_redirect} = $args{max_redirect} || 7;
    $self->{ssl_verify_hostname} = $ENV{PERL_LWP_SSL_VERIFY_HOSTNAME} // 1;
    
    return $self;
}

# Configuration methods (from your usage analysis)
sub agent {
    my $self = shift;
    if (@_) {
        $self->{agent} = shift;
        return $self;
    }
    return $self->{agent};
}

sub timeout {
    my $self = shift;
    if (@_) {
        $self->{timeout} = shift;
        return $self;
    }
    return $self->{timeout};
}

# Main request method (supports your HTTP::Request pattern)
sub request {
    my ($self, $request_obj) = @_;
    
    croak "HTTP::Request object required" unless $request_obj;
    croak "Invalid request object" unless ref($request_obj) eq 'HTTPHelper::Request';
    
    # Extract request details
    my $method = $request_obj->{method};
    my $url = $request_obj->{url};
    my $headers = $request_obj->{headers} || {};
    my $content = $request_obj->{content} || '';
    
    # Add User-Agent header
    $headers->{'User-Agent'} = $self->{agent};
    
    # Prepare request parameters for Python backend
    my $params = {
        method => $method,
        url => $url,
        headers => $headers,
        timeout => $self->{timeout},
        verify_ssl => $self->{ssl_verify_hostname},
    };
    
    # Add content for POST requests
    if ($content) {
        $params->{content} = $content;
        
        # If content type is form-encoded, treat as form data
        if (($headers->{'Content-Type'} || '') eq 'application/x-www-form-urlencoded') {
            $params->{form_encoded_content} = $content;
        }
    }
    
    # Make the request via Python
    my $result = $self->call_python('http_helper', 'lwp_request', $params);

    # Return response regardless of success status
    # HTTP errors (404, 500, etc.) are valid responses that should be returned
    return HTTPHelper::Response->new($result);
}

# Direct GET method
sub get {
    my ($self, $url, %args) = @_;
    
    croak "URL required" unless $url;
    
    # Prepare request parameters
    my $params = {
        method => 'GET',
        url => $url,
        headers => {
            'User-Agent' => $self->{agent},
            %{$args{headers} || {}},
        },
        timeout => $self->{timeout},
        verify_ssl => $self->{ssl_verify_hostname},
    };
    
    # Make the request via Python
    my $result = $self->call_python('http_helper', 'lwp_request', $params);

    # Return response regardless of success status
    # HTTP errors (404, 500, etc.) are valid responses that should be returned
    return HTTPHelper::Response->new($result);
}

# Direct POST method (from your HpsmTicket.pm usage)
sub post {
    my ($self, $url, $data_or_args, %extra_args) = @_;

    croak "URL required" unless $url;

    # Handle LWP::UserAgent pattern: $ua->post($url, \%form_data)
    # Check if second argument is a hashref (LWP form data pattern)
    my %args;
    if (ref($data_or_args) eq 'HASH') {
        # Convert hashref to form-encoded string
        my @pairs;
        while (my ($key, $value) = each %$data_or_args) {
            # Simple URL encoding for form parameters
            my $encoded_key = _uri_escape($key);
            my $encoded_value = _uri_escape($value);
            push @pairs, "$encoded_key=$encoded_value";
        }
        my $form_content = join('&', @pairs);

        # Set up args for form-encoded POST
        %args = (
            Content_Type => 'application/x-www-form-urlencoded',
            Content => $form_content,
            %extra_args  # Allow additional args after hashref
        );
    } else {
        # Standard named parameter pattern: $ua->post($url, Content => ..., Content_Type => ...)
        %args = ($data_or_args, %extra_args);
    }

    # Prepare request parameters
    my $params = {
        method => 'POST',
        url => $url,
        headers => {
            'User-Agent' => $self->{agent},
            %{$args{headers} || {}},
        },
        timeout => $self->{timeout},
        verify_ssl => $self->{ssl_verify_hostname},
    };

    # Handle Content_Type parameter (your usage pattern)
    if ($args{Content_Type}) {
        $params->{headers}->{'Content-Type'} = $args{Content_Type};
    }

    # Handle Content parameter (your usage pattern)
    if (defined $args{Content}) {
        $params->{content} = $args{Content};

        # If content type is form-encoded, mark it appropriately
        if (($params->{headers}->{'Content-Type'} || '') eq 'application/x-www-form-urlencoded') {
            $params->{form_encoded_content} = $args{Content};
        }
    }
    
    # Make the request via Python
    my $result = $self->call_python('http_helper', 'lwp_request', $params);

    # Return response regardless of success status
    # HTTP errors (404, 500, etc.) are valid responses that should be returned
    return HTTPHelper::Response->new($result);
}

# WWW::Mechanize compatibility methods
sub get_mechanize {
    my ($self, $url) = @_;
    
    croak "URL required" unless $url;
    
    # Make a simple GET request
    my $response = $self->get($url);
    
    # Store response for status() method
    $self->{_last_response} = $response;
    
    return $response->is_success();
}

sub status {
    my $self = shift;
    
    if ($self->{_last_response}) {
        return $self->{_last_response}->code();
    }
    
    return undef;
}

# Helper function for URL encoding (simple implementation for form data)
sub _uri_escape {
    my $str = shift;
    return '' unless defined $str;

    # Encode special characters for application/x-www-form-urlencoded
    # This is a simplified version - for production use, could use URI::Escape if available
    $str =~ s/([^A-Za-z0-9\-_.~])/sprintf("%%%02X", ord($1))/ge;

    return $str;
}

# WWW::Mechanize compatibility wrapper class
package HTTPHelper::Mechanize;
use strict;
use warnings;
use Carp;
use base 'HTTPHelper';

sub new {
    my ($class, %args) = @_;
    
    # Handle WWW::Mechanize constructor parameters
    my $agent = $args{agent} || 'WWW::Mechanize/1.0';
    my $autocheck = $args{autocheck} // 1;  # Default to 1 (opposite of your usage)
    
    my $self = HTTPHelper->new(
        agent => $agent,
        autocheck => $autocheck,
        %args
    );
    
    $self->{autocheck} = $autocheck;
    
    return bless $self, $class;
}

sub get {
    my ($self, $url) = @_;
    
    croak "URL required" unless $url;
    
    # Make the request
    my $response = $self->SUPER::get($url);
    
    # Store for status() method
    $self->{_last_response} = $response;
    
    # Handle autocheck behavior
    if ($self->{autocheck} && !$response->is_success()) {
        croak "GET $url failed: " . $response->status_line();
    }
    
    return $response;
}

sub status {
    my $self = shift;
    
    if ($self->{_last_response}) {
        return $self->{_last_response}->code();
    }
    
    return undef;
}

# Export compatibility
package HTTPHelper;

sub import {
    my $class = shift;
    my $caller = caller;
    
    # Create LWP::UserAgent compatibility
    {
        no strict 'refs';
        *{"${caller}::LWP::UserAgent::new"} = sub {
            shift;  # Remove class name
            return HTTPHelper->new(@_);
        };
        
        # Create HTTP::Request compatibility
        *{"${caller}::HTTP::Request::new"} = sub {
            shift;  # Remove class name
            return HTTPHelper::Request->new(@_);
        };
        
        # Create WWW::Mechanize compatibility
        *{"${caller}::WWW::Mechanize::new"} = sub {
            shift;  # Remove class name
            return HTTPHelper::Mechanize->new(@_);
        };
    }
}

1;

__END__

=head1 NAME

HTTPHelper - LWP::UserAgent and WWW::Mechanize replacement using Python backend

=head1 SYNOPSIS

    # LWP::UserAgent replacement
    use HTTPHelper;  # Instead of: use LWP::UserAgent;
    
    my $ua = LWP::UserAgent->new();
    $ua->agent("MyApp/1.0 " . $ua->agent);
    $ua->timeout(30);
    
    # HTTP::Request pattern (30166mi_job_starter.pl style)
    my $web_request = HTTP::Request->new(POST => $URL);
    $web_request->content_type('application/x-www-form-urlencoded');
    $web_request->content($content_string);
    my $response = $ua->request($web_request);
    
    # Direct POST pattern (HpsmTicket.pm style)  
    my $web_response = $ua->post($URL, 
      Content_Type => 'application/x-www-form-urlencoded', 
      Content => $ticket);
    
    # WWW::Mechanize replacement
    use HTTPHelper;  # Instead of: use WWW::Mechanize;
    
    my $mech = WWW::Mechanize->new(agent => "Mozilla/6.0", autocheck => 0);
    $mech->get($wls_url);
    my $status = $mech->status();
    
    # Response handling (both LWP and Mechanize)
    if ($response->is_success) {
        my $content = $response->decoded_content;
    } else {
        my $error = $response->status_line;
    }

=head1 DESCRIPTION

HTTPHelper provides drop-in replacements for both LWP::UserAgent and WWW::Mechanize
by routing HTTP operations through a Python backend that uses only standard
library modules.

Supports all the patterns from your usage analysis:
- LWP::UserAgent: Constructor, agent(), timeout(), request(), post(), full response handling
- WWW::Mechanize: Simple constructor, get(), status() for server health checking
- HTTP::Request: Object creation, content_type(), content()
- SSL verification via environment variables

=head1 LWP::USERAGENT COMPATIBILITY

All patterns from your analysis are supported:
- Simple constructor with no parameters  
- agent() and timeout() configuration
- HTTP::Request object creation and usage
- POST with Content_Type and Content parameters
- Full response object compatibility

=head1 WWW::MECHANIZE COMPATIBILITY

Supports your simple usage patterns:
- Constructor with agent and autocheck parameters
- get() method for HTTP requests
- status() method for HTTP status codes
- WebSphere server health checking workflow

=head1 MIGRATION

Change only the use statements in your scripts:
- Replace 'use LWP::UserAgent;' with 'use HTTPHelper;'
- Replace 'use HTTP::Request;' with 'use HTTPHelper;'
- Replace 'use WWW::Mechanize;' with 'use HTTPHelper;'

All existing code works without modification.

=head1 FILES REQUIRED

This module requires:
- CPANBridge.pm (base bridge class)
- python_helpers/cpan_bridge.py (Python router)
- python_helpers/helpers/http.py (HTTP backend)

=head1 SEE ALSO

L<CPANBridge>, L<LWP::UserAgent>, L<WWW::Mechanize>, L<HTTP::Request>

=cut