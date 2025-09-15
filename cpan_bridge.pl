# File: CPANBridge.pm
package CPANBridge;

use strict;
use warnings;
use JSON;
use Carp;
use FindBin;
use File::Spec;

our $VERSION = '1.01';

# Global configuration
our $PYTHON_BRIDGE_SCRIPT = undef;
our $DEBUG_LEVEL = 0;
our $TIMEOUT = 60;
our $MAX_JSON_SIZE = 10_000_000;  # 10MB default
our $RETRY_COUNT = 3;
our $PYTHON_PATH = undef;

sub new {
    my ($class, %args) = @_;
    
    my $self = {
        debug => $args{debug} || $DEBUG_LEVEL,
        timeout => $args{timeout} || $TIMEOUT,
        max_json_size => $args{max_json_size} || $MAX_JSON_SIZE,
        retry_count => $args{retry_count} || $RETRY_COUNT,
        last_error => undef,
        last_python_output => undef,
        performance_stats => {},
    };
    
    bless $self, $class;
    
    # Initialize Python bridge script path if not set
    $self->_init_python_bridge() unless $PYTHON_BRIDGE_SCRIPT;
    
    return $self;
}

# Initialize the Python bridge script path
sub _init_python_bridge {
    my $self = shift;
    
    return if $PYTHON_BRIDGE_SCRIPT;
    
    # Search paths for the Python bridge script
    my @search_paths = (
        File::Spec->catfile($FindBin::Bin, 'python_helpers', 'cpan_bridge.py'),
        File::Spec->catfile($FindBin::Bin, '..', 'python_helpers', 'cpan_bridge.py'),
        File::Spec->catfile($FindBin::Bin, 'cpan_bridge.py'),
        '/opt/controlm/scripts/python_helpers/cpan_bridge.py',
        '/usr/local/scripts/python_helpers/cpan_bridge.py',
        './python_helpers/cpan_bridge.py',
    );
    
    # Check environment variable override
    if ($ENV{CPAN_BRIDGE_SCRIPT}) {
        unshift @search_paths, $ENV{CPAN_BRIDGE_SCRIPT};
    }
    
    for my $path (@search_paths) {
        if (-f $path && -r $path) {
            $PYTHON_BRIDGE_SCRIPT = $path;
            $self->_debug("Found Python bridge script at: $path");
            last;
        }
    }
    
    unless ($PYTHON_BRIDGE_SCRIPT) {
        croak "Cannot find cpan_bridge.py script. Searched in: " . join(', ', @search_paths);
    }
}

# Main method to call Python functions
sub call_python {
    my ($self, $module, $function, $params) = @_;
    
    croak "Module name required" unless $module;
    croak "Function name required" unless $function;
    
    $params ||= {};
    
    # Performance tracking
    my $start_time = time();
    
    # Check for large data
    my $json_size = length($self->_safe_json_encode($params));
    if ($json_size > $self->{max_json_size}) {
        $self->_debug("Large data detected ($json_size bytes), may be slow");
    }
    
    # Prepare request data
    my $request = {
        module => $module,
        function => $function,
        params => $params,
        timestamp => time(),
        perl_caller => (caller(1))[3] || 'unknown',
        request_id => $self->_generate_request_id(),
    };
    
    $self->_debug("Calling Python: $module->$function");
    $self->_debug("Request data: " . $self->_safe_json_encode($request)) if $self->{debug} > 2;
    
    # Execute with retry logic
    my $result = $self->_execute_with_retry($request);
    
    # Performance tracking
    my $duration = time() - $start_time;
    $self->{performance_stats}->{"$module.$function"} = {
        last_duration => $duration,
        call_count => ($self->{performance_stats}->{"$module.$function"}->{call_count} || 0) + 1,
    };
    
    # Process result
    if ($result && $result->{success}) {
        $self->_debug("Python call successful (${duration}s)");
        $self->{last_error} = undef;
        return $result;
    } else {
        my $error = $result ? $result->{error} : "Unknown Python execution error";
        $self->{last_error} = $error;
        $self->_debug("Python call failed: $error");
        
        return {
            success => 0,
            error => $error,
            module => $module,
            function => $function,
            duration => $duration,
        };
    }
}

# Execute with retry logic
sub _execute_with_retry {
    my ($self, $request) = @_;
    
    my $retry_count = $self->{retry_count};
    my $last_error;
    
    for my $attempt (1..$retry_count) {
        $self->_debug("Attempt $attempt of $retry_count");
        
        my $result = $self->_execute_python_bridge($request);
        
        if ($result && $result->{success}) {
            return $result;
        }
        
        $last_error = $result ? $result->{error} : "Unknown error";
        
        # Determine if error is retryable
        if ($self->_is_retryable_error($last_error)) {
            $self->_debug("Retryable error, waiting before retry: $last_error");
            sleep($attempt);  # Simple backoff
        } else {
            $self->_debug("Non-retryable error: $last_error");
            last;
        }
    }
    
    return {
        success => 0,
        error => "Failed after $retry_count attempts. Last error: $last_error"
    };
}

# Determine if an error is retryable
sub _is_retryable_error {
    my ($self, $error) = @_;
    
    my @retryable_patterns = (
        qr/timeout/i,
        qr/connection.*refused/i,
        qr/temporary.*failure/i,
        qr/resource.*unavailable/i,
        qr/database.*lock/i,
    );
    
    for my $pattern (@retryable_patterns) {
        return 1 if $error =~ $pattern;
    }
    
    return 0;
}

# Execute the Python bridge script
sub _execute_python_bridge {
    my ($self, $request) = @_;
    
    my $json_input = $self->_safe_json_encode($request);
    
    # Prepare command
    my $python_cmd = $self->_get_python_command();
    my $full_command = sprintf('%s "%s"', $python_cmd, $PYTHON_BRIDGE_SCRIPT);
    
    $self->_debug("Executing: $full_command");
    
    # Execute with timeout
    my $result = $self->_execute_with_timeout($full_command, $json_input);
    
    return $result;
}

# Execute command with timeout and input - FIXED VERSION
sub _execute_with_timeout {
    my ($self, $command, $input) = @_;
    
    my $output = '';
    
    eval {
        if ($^O eq 'MSWin32') {
            # Force file-based approach on Windows to avoid pipe deadlocks
            $self->_debug("Using Windows file-based approach");
            $output = $self->_execute_with_files($command, $input);
        } elsif (eval { require IPC::Open3; 1 }) {
            $self->_debug("Using IPC::Open3 method");
            $output = $self->_execute_with_open3($command, $input);
        } else {
            $self->_debug("Falling back to simple pipe method");
            $output = $self->_execute_with_pipe($command, $input);
        }
    };
    
    if ($@) {
        $self->_debug("Execution failed with error: $@");
        return {
            success => 0,
            error => "Execution failed: $@"
        };
    }
    
    $self->{last_python_output} = $output;
    
    # Parse JSON response
    my $result = $self->_safe_json_decode($output);
    
    return $result;
}

# File-based execution for Windows - FIXED VERSION
sub _execute_with_files {
    my ($self, $command, $input) = @_;
    
    require File::Temp;
    
    my ($temp_fh, $temp_file) = File::Temp::tempfile(SUFFIX => '.json', UNLINK => 1);
    print $temp_fh $input;
    close($temp_fh);
    
    $self->_debug("Created temp file: $temp_file");
    $self->_debug("Input length: " . length($input));
    
    # Execute with file redirection
    my $output = `$command < "$temp_file" 2>&1`;
    my $exit_code = $? >> 8;
    
    $self->_debug("Exit code: $exit_code");
    $self->_debug("Output length: " . length($output));
    $self->_debug("Output: [$output]") if $self->{debug} > 2;
    
    if ($exit_code != 0) {
        die "Python script failed with exit code $exit_code: $output";
    }
    
    return $output;
}

# IPC::Open3 execution for Unix systems - IMPROVED VERSION
sub _execute_with_open3 {
    my ($self, $command, $input) = @_;
    
    require IPC::Open3;
    require Symbol;
    
    my $timeout = $self->{timeout};
    my ($in_fh, $out_fh, $err_fh);
    
    $err_fh = Symbol::gensym();
    
    $self->_debug("Starting IPC::Open3 with command: $command");
    
    eval {
        local $SIG{ALRM} = sub { die "timeout\n" };
        alarm($timeout);
        
        my $pid = IPC::Open3::open3($in_fh, $out_fh, $err_fh, $command);
        $self->_debug("Process started with PID: $pid");
        
        # Send input and close stdin immediately to avoid deadlock
        print $in_fh $input;
        close($in_fh);
        $self->_debug("Input sent and stdin closed");
        
        # Read output
        my $output = do { local $/; <$out_fh> };
        my $error = do { local $/; <$err_fh> };
        
        close($out_fh);
        close($err_fh);
        
        waitpid($pid, 0);
        my $exit_code = $? >> 8;
        
        alarm(0);
        
        $self->_debug("Process completed with exit code: $exit_code");
        $self->_debug("Output length: " . length($output || ''));
        
        if ($exit_code != 0) {
            die "Python script failed with exit code $exit_code: $error";
        }
        
        return $output;
    };
    
    alarm(0);
    
    if ($@) {
        $self->_debug("IPC::Open3 failed: $@");
        die $@;
    }
}

# Simple pipe execution - fallback method
sub _execute_with_pipe {
    my ($self, $command, $input) = @_;
    
    # Use echo pipe for Unix systems
    my $output = `echo '$input' | $command`;
    my $exit_code = $? >> 8;
    
    if ($exit_code != 0) {
        die "Python script failed with exit code $exit_code";
    }
    
    return $output;
}

# Get appropriate Python command
sub _get_python_command {
    my $self = shift;
    
    # Use custom Python path if set
    return $PYTHON_PATH if $PYTHON_PATH;
    
    # Check environment variable
    return $ENV{PYTHON_EXECUTABLE} if $ENV{PYTHON_EXECUTABLE};
    
    # Try different Python executables in order of preference
    my @python_commands = (
        'python3',
        'python',
        '/usr/bin/python3',
        '/usr/bin/python',
        '/usr/local/bin/python3',
        '/opt/python/bin/python3',
    );
    
    for my $cmd (@python_commands) {
        # Test if command exists and works
        my $test_result = `$cmd --version 2>&1`;
        if ($? == 0) {
            $self->_debug("Using Python command: $cmd");
            return $cmd;
        }
    }
    
    croak "No working Python interpreter found. Tried: " . join(', ', @python_commands);
}

# Generate unique request ID for tracking
sub _generate_request_id {
    my $self = shift;
    return sprintf("%d_%d_%d", time(), $$, int(rand(1000)));
}

# Safe JSON encoding with error handling
sub _safe_json_encode {
    my ($self, $data) = @_;
    
    my $json;
    eval {
        $json = encode_json($data);
    };
    
    if ($@) {
        croak "JSON encoding failed: $@";
    }
    
    return $json;
}

# Safe JSON decoding with error handling
sub _safe_json_decode {
    my ($self, $json_string) = @_;
    
    return { success => 0, error => "Empty response" } unless $json_string;
    
    # Clean up the JSON string
    $json_string =~ s/^\s+|\s+$//g;
    
    my $data;
    eval {
        $data = decode_json($json_string);
    };
    
    if ($@) {
        return {
            success => 0,
            error => "JSON decode failed: $@",
            raw_output => $json_string
        };
    }
    
    return $data;
}

# Debug logging
sub _debug {
    my ($self, $message) = @_;
    
    return unless $self->{debug};
    
    my $timestamp = scalar localtime;
    my $caller = (caller(2))[3] || (caller(1))[3] || 'unknown';
    
    warn "[$timestamp] CPANBridge DEBUG ($caller): $message\n";
}

# Utility methods
sub get_last_error {
    my $self = shift;
    return $self->{last_error};
}

sub get_last_python_output {
    my $self = shift;
    return $self->{last_python_output};
}

sub get_performance_stats {
    my $self = shift;
    return $self->{performance_stats};
}

sub set_debug {
    my ($self, $level) = @_;
    $self->{debug} = $level;
    $DEBUG_LEVEL = $level;
}

sub set_timeout {
    my ($self, $timeout) = @_;
    $self->{timeout} = $timeout;
}

sub set_max_json_size {
    my ($self, $size) = @_;
    $self->{max_json_size} = $size;
}

sub set_retry_count {
    my ($self, $count) = @_;
    $self->{retry_count} = $count;
}

sub set_python_bridge_script {
    my ($class_or_self, $path) = @_;
    
    croak "Python bridge script path required" unless $path;
    croak "Python bridge script not found: $path" unless -f $path;
    croak "Python bridge script not readable: $path" unless -r $path;
    
    $PYTHON_BRIDGE_SCRIPT = $path;
}

sub set_python_path {
    my ($class_or_self, $path) = @_;
    
    croak "Python path required" unless $path;
    
    # Test the Python executable
    my $test_result = `$path --version 2>&1`;
    croak "Python executable not working: $path" if $? != 0;
    
    $PYTHON_PATH = $path;
}

sub test_python_bridge {
    my $self = shift;
    
    $self->_debug("Testing Python bridge connection...");
    
    my $result = $self->call_python('test', 'ping', { message => 'test' });
    
    if ($result && $result->{success}) {
        $self->_debug("Python bridge test successful");
        return 1;
    } else {
        my $error = $result ? $result->{error} : "Unknown error";
        $self->_debug("Python bridge test failed: $error");
        return 0;
    }
}

sub check_python_module {
    my ($self, $module_name) = @_;
    
    my $result = $self->call_python('test', 'check_module', { module => $module_name });
    
    return $result && $result->{success} && $result->{result};
}

sub clear_performance_stats {
    my $self = shift;
    $self->{performance_stats} = {};
}

# Cleanup
sub DESTROY {
    my $self = shift;
    # Any cleanup needed
}

1;

__END__

=head1 NAME

CPANBridge - Base class for CPAN module replacements using Python

=head1 SYNOPSIS

    use CPANBridge;
    
    my $bridge = CPANBridge->new(debug => 1);
    
    my $result = $bridge->call_python('module_name', 'function_name', \%params);
    
    if ($result->{success}) {
        print "Result: " . $result->{result} . "\n";
    } else {
        print "Error: " . $result->{error} . "\n";
    }

=head1 DESCRIPTION

CPANBridge provides a base class for creating Perl modules that replace CPAN 
dependencies by calling equivalent Python functions. It handles communication 
between Perl and Python, JSON serialization, error handling, and timeout management.

This version includes fixes for Windows pipe communication issues and improved
error handling for production use.

=head1 METHODS

See the main documentation for method descriptions.

=head1 PLATFORM SUPPORT

- Windows: Uses temporary files to avoid pipe deadlocks
- Linux/Unix: Uses IPC::Open3 for better process control
- Both: Automatic fallback mechanisms for maximum compatibility

=head1 SEE ALSO

L<DBIHelper>, L<XMLHelper>, L<HTTPHelper>

=cut