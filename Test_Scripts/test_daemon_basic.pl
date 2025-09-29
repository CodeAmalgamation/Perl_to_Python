#!/usr/bin/perl

# test_daemon_basic.pl - Basic test of daemon functionality

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/..";
use CPANBridge;

print "=== CPAN Bridge Daemon Basic Test ===\n";

# Enable debugging
$CPANBridge::DEBUG_LEVEL = 2;

# Test daemon mode (default)
print "Testing daemon mode...\n";

my $bridge = CPANBridge->new(debug => 2);

# Test 1: Basic ping test
print "\n=== Test 1: Daemon Ping ===\n";
my $result = $bridge->call_python('test', 'ping', {});

if ($result->{success}) {
    print "SUCCESS: Daemon ping successful\n";
    print "Response: " . $bridge->_safe_json_encode($result) . "\n";
} else {
    print "FAILED: Daemon ping failed: " . $result->{error} . "\n";
}

# Test 2: Health check
print "\n=== Test 2: Health Check ===\n";
$result = $bridge->call_python('test', 'health', {});

if ($result->{success}) {
    print "SUCCESS: Health check passed\n";
    print "Status: " . $result->{result}->{status} . "\n";
    print "Uptime: " . $result->{result}->{uptime} . " seconds\n";
    print "Loaded modules: " . join(", ", @{$result->{result}->{loaded_modules}}) . "\n";
} else {
    print "FAILED: Health check failed: " . $result->{error} . "\n";
}

# Test 3: System info
print "\n=== Test 3: System Info ===\n";
$result = $bridge->call_python('system', 'info', {});

if ($result->{success}) {
    print "SUCCESS: System info retrieved\n";
    print "Daemon version: " . $result->{result}->{daemon_version} . "\n";
    print "Python version: " . $result->{result}->{python_version} . "\n";
    print "Socket path: " . $result->{result}->{socket_path} . "\n";
} else {
    print "FAILED: System info failed: " . $result->{error} . "\n";
}

# Test 4: Test database module if available
print "\n=== Test 4: Database Module Test ===\n";
$result = $bridge->call_python('database', 'connect', {
    dsn => 'dbi:Oracle:test',
    username => 'test_user',
    password => 'test_password'
});

if ($result->{success}) {
    print "SUCCESS: Database module accessible via daemon\n";
    print "Response: " . $bridge->_safe_json_encode($result) . "\n";
} else {
    print "INFO: Database test failed (expected): " . $result->{error} . "\n";
}

# Test 5: Fallback mode
print "\n=== Test 5: Process Mode Fallback ===\n";
$CPANBridge::DAEMON_MODE = 0;  # Disable daemon mode

my $bridge2 = CPANBridge->new(debug => 2);
$result = $bridge2->call_python('test', 'ping', {});

if ($result->{success}) {
    print "SUCCESS: Process mode fallback working\n";
} else {
    print "INFO: Process mode test (expected to work with existing bridge): " . $result->{error} . "\n";
}

print "\n=== Daemon Basic Test Complete ===\n";
print "Note: Some failures are expected if daemon cannot connect to actual databases.\n";
print "The important tests are ping, health, and system info.\n";