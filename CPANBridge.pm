# File: CPANBridge.pm
package CPANBridge;

use strict;
use warnings;
use JSON::PP;
use Carp;
use FindBin;
use File::Spec;
use IO::Socket::UNIX;
use IO::Socket::INET;
use Time::HiRes qw(time sleep);
use Encode qw(encode decode);

our $VERSION = '2.00';

# Global configuration
our $PYTHON_BRIDGE_SCRIPT = undef;
our $DEBUG_LEVEL = 0;
our $TIMEOUT = 60;
our $MAX_JSON_SIZE = 10_000_000;  # 10MB default
our $RETRY_COUNT = 3;
our $PYTHON_PATH = undef;

# Daemon configuration
our $DAEMON_MODE = $ENV{CPAN_BRIDGE_DAEMON} // 1;          # Enable daemon by default
our $FALLBACK_ENABLED = $ENV{CPAN_BRIDGE_FALLBACK} // 1;   # Enable fallback by default
our $DAEMON_SOCKET = $ENV{CPAN_BRIDGE_SOCKET} || _get_default_socket_path();
our $DAEMON_TIMEOUT = $ENV{CPAN_BRIDGE_DAEMON_TIMEOUT} || 30;
our $DAEMON_STARTUP_TIMEOUT = $ENV{CPAN_BRIDGE_STARTUP_TIMEOUT} || 10;
our $DAEMON_SCRIPT = undef;

# Get platform-appropriate default socket path
sub _get_default_socket_path {
    if ($^O eq 'MSWin32') {
        # Native Windows: Default to named pipe style, will be overridden by socket info file
        return '\\\\.\\pipe\\cpan_bridge';
    } elsif ($^O eq 'msys') {
        # MSYS: Use Unix-style paths but Windows-style process management
        return '/tmp/cpan_bridge.sock';
    } else {
        # Unix-like: Use traditional Unix domain socket
        return '/tmp/cpan_bridge.sock';
    }
}


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
        client_version => $VERSION,
    };

    $self->_debug("Calling Python: $module->$function");
    $self->_debug("Request data: " . $self->_safe_json_encode($request)) if $self->{debug} > 2;

    # Try daemon mode first, fall back to process mode on failure
    my $result;
    if ($DAEMON_MODE) {
        $result = $self->_try_daemon_call($request);

        # If daemon call failed and fallback is enabled, try process mode
        if (!$result->{success} && $FALLBACK_ENABLED) {
            $self->_debug("Daemon call failed, falling back to process mode");
            $result = $self->_execute_with_retry($request);
        }
    } else {
        # Direct process mode
        $result = $self->_execute_with_retry($request);
    }
    
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
        if ($^O eq 'MSWin32' || $^O eq 'msys') {
            # Force file-based approach on Windows/MSYS to avoid pipe deadlocks
            $self->_debug("Using Windows/MSYS file-based approach");
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
# ===== DAEMON COMMUNICATION METHODS =====

# Try to call function via daemon
sub _try_daemon_call {
    my ($self, $request) = @_;

    # Try daemon communication up to 3 times
    for my $attempt (1..3) {
        $self->_debug("Daemon attempt $attempt of 3");

        # Ensure daemon is running
        unless ($self->_ensure_daemon_running()) {
            $self->_debug("Daemon not available for attempt $attempt");
            next if $attempt < 3;
            return {
                success => 0,
                error => "Daemon not available after 3 attempts",
                daemon_error => 1
            };
        }

        # Try to connect and send request
        my $result = $self->_send_daemon_request($request);
        return $result if $result->{success};

        # If connection failed, daemon might be dead
        if ($result->{error} && $result->{error} =~ /Connection refused|No such file/) {
            $self->_debug("Daemon appears to be dead, will try to restart");
            # Don't immediately retry - let next iteration handle restart
        }
    }

    return {
        success => 0,
        error => "Daemon communication failed after 3 attempts",
        daemon_error => 1
    };
}

# Ensure daemon is running
sub _ensure_daemon_running {
    my $self = shift;

    # Check if daemon socket exists and is responsive
    return 1 if $self->_ping_daemon();

    # Try to start daemon
    $self->_debug("Daemon not responsive, attempting to start");
    return $self->_start_daemon();
}

# Ping daemon to check if it's alive
sub _ping_daemon {
    my $self = shift;

    # Cross-platform daemon detection
    my $socket_available = $self->_check_daemon_socket_availability();
    return 0 unless $socket_available;

    my $ping_successful = 0;

    eval {
        my $socket = $self->_create_daemon_socket();
        return unless $socket;

        # Send ping request
        my $ping_request = $self->_safe_json_encode({
            module => 'test',
            function => 'ping',
            params => {},
            timestamp => time()
        });

        my $utf8_ping = encode('utf-8', $ping_request);
        $socket->print($utf8_ping);
        $socket->shutdown(1);  # Close write end

        # Read response with timeout
        my $response = '';
        eval {
            local $SIG{ALRM} = sub { die "timeout" };
            alarm(2);
            while (my $line = <$socket>) {
                $response .= $line;
            }
            alarm(0);
        };

        $socket->close();

        # Decode UTF-8 response
        $response = decode('utf-8', $response) if $response;

        if ($response) {
            my $result = $self->_safe_json_decode($response);
            if ($result && $result->{success}) {
                $ping_successful = 1;
                $self->_debug("Daemon ping successful");
            } else {
                $self->_debug("Daemon ping failed: invalid response");
            }
        } else {
            $self->_debug("Daemon ping failed: empty response");
        }
    };

    if ($@) {
        $self->_debug("Daemon ping failed: $@");
    }

    return $ping_successful;
}

# Check if daemon socket is available (cross-platform)
sub _check_daemon_socket_availability {
    my $self = shift;

    if ($^O eq 'MSWin32' || $^O eq 'msys') {
        # Windows/MSYS: Check for socket info file or try to read existing socket info
        my $socket_info_file = 'cpan_bridge_socket.txt';

        if (-f $socket_info_file) {
            $self->_debug("Found Windows socket info file: $socket_info_file");
            return 1;
        }

        # Check if DAEMON_SOCKET looks like TCP format (host:port)
        if ($DAEMON_SOCKET =~ /^(.+):(\d+)$/) {
            $self->_debug("Windows TCP socket format detected: $DAEMON_SOCKET");
            return 1;
        }

        $self->_debug("No Windows daemon socket info found");
        return 0;
    } else {
        # Unix-like: Check for Unix domain socket file
        if (-S $DAEMON_SOCKET) {
            $self->_debug("Unix domain socket found: $DAEMON_SOCKET");
            return 1;
        }

        $self->_debug("No Unix domain socket found at: $DAEMON_SOCKET");
        return 0;
    }
}

# Create appropriate socket connection (cross-platform)
sub _create_daemon_socket {
    my $self = shift;

    if ($^O eq 'MSWin32' || $^O eq 'msys') {
        # Windows/MSYS: Use TCP socket
        my $socket_info = $self->_get_windows_socket_info();
        return undef unless $socket_info;

        my ($host, $port) = @$socket_info;
        $self->_debug("Connecting to Windows/MSYS TCP socket: $host:$port");

        return IO::Socket::INET->new(
            PeerAddr => $host,
            PeerPort => $port,
            Proto    => 'tcp',
            Timeout  => 2
        );
    } else {
        # Unix-like: Use Unix domain socket
        $self->_debug("Connecting to Unix domain socket: $DAEMON_SOCKET");

        return IO::Socket::UNIX->new(
            Peer => $DAEMON_SOCKET,
            Type => SOCK_STREAM,
            Timeout => 2
        );
    }
}

# Get Windows socket info (host and port)
sub _get_windows_socket_info {
    my $self = shift;

    # Try to read from socket info file first
    my $socket_info_file = 'cpan_bridge_socket.txt';
    my $socket_path = $DAEMON_SOCKET;

    if (-f $socket_info_file) {
        eval {
            open my $fh, '<', $socket_info_file or die "Cannot read socket info: $!";
            $socket_path = <$fh>;
            chomp $socket_path if $socket_path;
            close $fh;
            $self->_debug("Read socket info from file: $socket_path");
        };

        if ($@) {
            $self->_debug("Error reading socket info file: $@");
            return undef;
        }
    }

    # Parse TCP socket format (host:port)
    if ($socket_path && $socket_path =~ /^(.+):(\d+)$/) {
        my ($host, $port) = ($1, $2);
        $self->_debug("Parsed Windows socket info: $host:$port");
        return [$host, $port];
    }

    $self->_debug("Invalid Windows socket format: $socket_path");
    return undef;
}

# Create daemon socket with extended timeout for requests
sub _create_daemon_socket_with_timeout {
    my $self = shift;

    if ($^O eq 'MSWin32'|| $^O eq 'msys') {
        # Native Windows: Use TCP socket with daemon timeout
        my $socket_info = $self->_get_windows_socket_info();
        return undef unless $socket_info;

        my ($host, $port) = @$socket_info;
        $self->_debug("Connecting to Windows TCP socket with timeout: $host:$port");

        return IO::Socket::INET->new(
            PeerAddr => $host,
            PeerPort => $port,
            Proto    => 'tcp',
            Timeout  => $DAEMON_TIMEOUT
        );
    } else {
        # Unix-like: Use Unix domain socket with daemon timeout
        $self->_debug("Connecting to Unix domain socket with timeout: $DAEMON_SOCKET");

        return IO::Socket::UNIX->new(
            Peer => $DAEMON_SOCKET,
            Type => SOCK_STREAM,
            Timeout => $DAEMON_TIMEOUT
        );
    }
}

# Start daemon process
sub _start_daemon {
    my $self = shift;

    my $daemon_script = $self->_find_daemon_script();
    return 0 unless $daemon_script;

    $self->_debug("Starting daemon: $daemon_script");

    # Platform-specific daemon startup
    my $pid;
    if ($^O eq 'MSWin32') {
        # Native Windows: Use system() with START command for background execution
        my $python_exe = $self->_get_python_executable();
        my $command = qq{start /B "$python_exe" "$daemon_script"};
        $self->_debug("Windows daemon command: $command");

        my $result = system($command);
        if ($result != 0) {
            $self->_debug("Failed to start Windows daemon: $result");
            return 0;
        }
        $pid = "background";  # We don't get actual PID on Windows with START
    } else {
        # Unix/MSYS: Use fork() for proper daemon backgrounding
        $pid = fork();
        if (!defined $pid) {
            $self->_debug("Failed to fork daemon process: $!");
            return 0;
        }

        if ($pid == 0) {
            # Child process - start daemon
            # Close standard handles to detach
            close STDIN;
            close STDOUT;
            close STDERR;

            # Execute daemon
            exec($self->_get_python_executable(), $daemon_script);
            exit(1);  # Should never reach here
        }
    }

    # Parent process - wait for daemon to start
    $self->_debug("Daemon process started with PID $pid, waiting for socket...");

    for my $i (1..$DAEMON_STARTUP_TIMEOUT) {
        sleep(1);
        if ($self->_check_daemon_socket_availability() && $self->_ping_daemon()) {
            $self->_debug("Daemon started successfully");
            return 1;
        }
    }

    $self->_debug("Daemon failed to start within timeout");
    return 0;
}

# Find daemon script
sub _find_daemon_script {
    my $self = shift;

    return $DAEMON_SCRIPT if $DAEMON_SCRIPT;

    # Search paths for daemon script
    my @search_paths = (
        File::Spec->catfile($FindBin::Bin, 'python_helpers', 'cpan_daemon.py'),
        File::Spec->catfile($FindBin::Bin, '..', 'python_helpers', 'cpan_daemon.py'),
        File::Spec->catfile($FindBin::Bin, 'cpan_daemon.py'),
        '/opt/controlm/scripts/python_helpers/cpan_daemon.py',
        '/usr/local/scripts/python_helpers/cpan_daemon.py',
        './python_helpers/cpan_daemon.py',
    );

    # Check environment variable override
    if ($ENV{CPAN_BRIDGE_DAEMON_SCRIPT}) {
        unshift @search_paths, $ENV{CPAN_BRIDGE_DAEMON_SCRIPT};
    }

    for my $path (@search_paths) {
        if (-f $path && -r $path) {
            $DAEMON_SCRIPT = $path;
            $self->_debug("Found daemon script at: $path");
            return $path;
        }
    }

    $self->_debug("Daemon script not found. Searched: " . join(', ', @search_paths));
    return undef;
}

# Send request to daemon
sub _send_daemon_request {
    my ($self, $request) = @_;

    eval {
        # Use cross-platform socket creation
        my $socket = $self->_create_daemon_socket_with_timeout();

        unless ($socket) {
            return {
                success => 0,
                error => "Failed to connect to daemon: $!",
                daemon_error => 1
            };
        }

        # Send request
        my $request_json = $self->_safe_json_encode($request);
        my $utf8_json = encode('utf-8', $request_json);
        $socket->print($utf8_json);
        $socket->shutdown(1);  # Close write end

        # Read response
        my $response = '';
        while (my $line = <$socket>) {
            $response .= $line;
        }

        # Decode UTF-8 response
        $response = decode('utf-8', $response) if $response;

        $socket->close();

        unless ($response) {
            return {
                success => 0,
                error => "Empty response from daemon",
                daemon_error => 1
            };
        }

        # Parse response
        my $result = $self->_safe_json_decode($response);
        unless ($result) {
            return {
                success => 0,
                error => "Invalid JSON response from daemon",
                daemon_error => 1
            };
        }

        return $result;

    } or do {
        my $error = $@ || 'Unknown error';
        return {
            success => 0,
            error => "Daemon communication error: $error",
            daemon_error => 1
        };
    };
}

# Get Python executable
sub _get_python_executable {
    my $self = shift;

    # Use custom Python path if set
    return $PYTHON_PATH if $PYTHON_PATH;

    # Check environment variable
    return $ENV{PYTHON_EXECUTABLE} if $ENV{PYTHON_EXECUTABLE};

    # Platform-specific Python executable search order
    my @python_commands;
    if ($^O eq 'MSWin32') {
        # Windows: prefer py launcher, then standard names
        @python_commands = (
            'py',           # Python Launcher (recommended for Windows)
            'python',       # Standard Python
            'python.exe',   # Explicit .exe
            'python3',      # Unix-style (some Windows installs)
            'python3.exe'   # Unix-style with .exe
        );
    } elsif ($^O eq 'msys') {
        # MSYS: hybrid approach - Unix names work but also try Windows style
        @python_commands = (
            'python3',      # MSYS typically has Unix-style names
            'python',       # Generic fallback
            'py',           # Windows py launcher might work
            'python.exe'    # Windows executable
        );
    } else {
        # Unix/Linux/macOS: standard Unix approach
        @python_commands = (
            'python3',
            'python',
            '/usr/bin/python3',
            '/usr/bin/python',
            '/usr/local/bin/python3',
            '/usr/local/bin/python'
        );
    }

    # Try each command in order
    for my $python (@python_commands) {
        my $path;
        if ($python =~ m{^/}) {
            # Absolute path - check directly
            if (-x $python) {
                $self->_debug("Found Python executable: $python");
                return $python;
            }
        } else {
            # Relative command - use which/where
            if ($^O eq 'MSWin32') {
                # Windows: use 'where' command
                $path = `where $python 2>nul`;
            } else {
                # Unix-like: use 'which' command
                $path = `which $python 2>/dev/null`;
            }
            chomp $path;
            if ($path && -x $path) {
                $self->_debug("Found Python executable: $python (at $path)");
                return $python;
            }
        }
    }

    # No Python found - this will cause an error
    die "No Python executable found. Please install Python or set PYTHON_EXECUTABLE environment variable.";
}

# ===== END DAEMON METHODS =====

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