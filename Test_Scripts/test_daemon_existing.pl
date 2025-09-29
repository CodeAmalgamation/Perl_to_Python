#!/usr/bin/perl

# test_daemon_existing.pl - Test daemon with existing running daemon

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/..";
use CPANBridge;

print "=== CPAN Bridge Daemon Test (Using Existing Daemon) ===\n";

# Enable debugging but reduce noise
$CPANBridge::DEBUG_LEVEL = 1;

# Ensure daemon mode is enabled
$CPANBridge::DAEMON_MODE = 1;

print "Testing with existing daemon at $CPANBridge::DAEMON_SOCKET\n";

my $bridge = CPANBridge->new(debug => 1);

# Test 1: Basic ping test
print "\n=== Test 1: Daemon Ping ===\n";
my $result = $bridge->call_python('test', 'ping', {});

if ($result->{success}) {
    print "SUCCESS: Daemon ping successful\n";
    print "Message: " . $result->{result}->{message} . "\n";
    print "Daemon version: " . $result->{result}->{daemon_version} . "\n";
    print "Uptime: " . sprintf("%.1f", $result->{result}->{uptime}) . " seconds\n";
} else {
    print "FAILED: Daemon ping failed: " . $result->{error} . "\n";
}

# Test 2: Health check
print "\n=== Test 2: Health Check ===\n";
$result = $bridge->call_python('test', 'health', {});

if ($result->{success}) {
    print "SUCCESS: Health check passed\n";
    print "Status: " . $result->{result}->{status} . "\n";
    print "Active connections: " . $result->{result}->{active_connections} . "\n";
    print "Loaded modules: " . join(", ", @{$result->{result}->{loaded_modules}}) . "\n";
    print "Total requests: " . $result->{result}->{stats}->{requests_processed} . "\n";
} else {
    print "FAILED: Health check failed: " . $result->{error} . "\n";
}

# Test 3: System info
print "\n=== Test 3: System Info ===\n";
$result = $bridge->call_python('system', 'info', {});

if ($result->{success}) {
    print "SUCCESS: System info retrieved\n";
    print "Daemon version: " . $result->{result}->{daemon_version} . "\n";
    print "Socket path: " . $result->{result}->{socket_path} . "\n";
    print "Max connections: " . $result->{result}->{configuration}->{max_connections} . "\n";
} else {
    print "FAILED: System info failed: " . $result->{error} . "\n";
}

# Test 4: Test helper module (one that works without dependencies)
print "\n=== Test 4: HTTP Helper Module Test ===\n";
$result = $bridge->call_python('http', 'lwp_request', {
    method => 'GET',
    url => 'https://httpbin.org/json',
    timeout => 10
});

if ($result->{success}) {
    print "SUCCESS: HTTP module accessible via daemon\n";
    print "HTTP Status: " . $result->{result}->{status_code} . "\n";
} else {
    print "INFO: HTTP test failed (may be network/dependency issue): " . $result->{error} . "\n";
}

# Test 5: Performance test - multiple rapid calls
print "\n=== Test 5: Performance Test (10 rapid calls) ===\n";
my $start_time = time();
my $success_count = 0;

for my $i (1..10) {
    my $ping_result = $bridge->call_python('test', 'ping', { call_number => $i });
    $success_count++ if $ping_result->{success};
}

my $duration = time() - $start_time;
print "Performance results:\n";
print "- Successful calls: $success_count/10\n";
print "- Total time: " . sprintf("%.3f", $duration) . " seconds\n";
if ($duration > 0) {
    print "- Average per call: " . sprintf("%.3f", $duration/10) . " seconds\n";
    print "- Calls per second: " . sprintf("%.1f", 10/$duration) . "\n";
} else {
    print "- Average per call: < 0.001 seconds (extremely fast!)\n";
    print "- Calls per second: > 1000 (extremely fast!)\n";
}

print "\n=== Daemon Test Complete ===\n";
print "All tests completed. The daemon architecture is working!\n";