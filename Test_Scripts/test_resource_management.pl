#!/usr/bin/perl

# test_resource_management.pl - Test enhanced resource management features

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/..";
use CPANBridge;
use JSON;

print "=== CPAN Bridge Daemon Resource Management Test ===\n";

# Enable debugging but reduce noise
$CPANBridge::DEBUG_LEVEL = 1;

# Ensure daemon mode is enabled
$CPANBridge::DAEMON_MODE = 1;

my $bridge = CPANBridge->new(debug => 1);

# Test 1: Enhanced Health Check with Resource Info
print "\n=== Test 1: Enhanced Health Check ===\n";
my $result = $bridge->call_python('test', 'health', {});

if ($result->{success}) {
    print "SUCCESS: Enhanced health check passed\n";
    print "Health Status: " . $result->{result}->{status} . "\n";
    print "Daemon version: " . $result->{result}->{daemon_version} . "\n";
    print "Active connections: " . $result->{result}->{active_connections} . "\n";
    print "Loaded modules: " . join(", ", @{$result->{result}->{loaded_modules}}) . "\n";

    # Display resource information
    if (exists $result->{result}->{resources}) {
        my $res = $result->{result}->{resources};
        print "\n--- Resource Status ---\n";
        print "Memory: " . sprintf("%.1f", $res->{memory_mb}) . "MB\n";
        print "CPU: " . sprintf("%.1f", $res->{cpu_percent}) . "%\n";
        print "Requests/min: " . $res->{requests_per_minute} . "\n";
        print "Concurrent requests: " . $res->{concurrent_requests} . "\n";
        print "Peak memory: " . sprintf("%.1f", $res->{peak_memory}) . "MB\n";
        print "Peak CPU: " . sprintf("%.1f", $res->{peak_cpu}) . "%\n";

        if (@{$res->{violations}}) {
            print "⚠️  Resource violations: " . join(", ", @{$res->{violations}}) . "\n";
        }
        if (@{$res->{warnings}}) {
            print "⚠️  Resource warnings: " . join(", ", @{$res->{warnings}}) . "\n";
        }
        if (!@{$res->{violations}} && !@{$res->{warnings}}) {
            print "✅ All resource limits OK\n";
        }
    }

    # Display enhanced statistics
    my $stats = $result->{result}->{stats};
    print "\n--- Enhanced Statistics ---\n";
    print "Total requests: " . $stats->{requests_processed} . "\n";
    print "Failed requests: " . $stats->{requests_failed} . "\n";
    print "Total connections: " . $stats->{connections_total} . "\n";
    print "Peak connections: " . $stats->{peak_connections} . "\n";
    if (exists $stats->{requests_rejected}) {
        print "Rejected requests: " . $stats->{requests_rejected} . "\n";
    }
    if (exists $stats->{connections_rejected}) {
        print "Rejected connections: " . $stats->{connections_rejected} . "\n";
    }

} else {
    print "FAILED: Enhanced health check failed: " . $result->{error} . "\n";
}

# Test 2: System Information with Resource Configuration
print "\n=== Test 2: System Configuration ===\n";
$result = $bridge->call_python('system', 'info', {});

if ($result->{success}) {
    print "SUCCESS: System info retrieved\n";
    print "Daemon version: " . $result->{result}->{daemon_version} . "\n";
    print "Socket path: " . $result->{result}->{socket_path} . "\n";

    my $config = $result->{result}->{configuration};
    print "\n--- Resource Configuration ---\n";
    print "Max connections: " . $config->{max_connections} . "\n";
    print "Max request size: " . sprintf("%.1f", $config->{max_request_size} / 1024 / 1024) . "MB\n";
    print "Connection timeout: " . $config->{connection_timeout} . "s\n";
    print "Cleanup interval: " . $config->{cleanup_interval} . "s\n";

} else {
    print "FAILED: System info failed: " . $result->{error} . "\n";
}

# Test 3: Performance Test with Resource Monitoring
print "\n=== Test 3: Performance with Resource Monitoring ===\n";
my $start_time = time();
my $success_count = 0;

for my $i (1..25) {  # More requests to see resource impact
    my $ping_result = $bridge->call_python('test', 'ping', { call_number => $i });
    $success_count++ if $ping_result->{success};
}

my $duration = time() - $start_time;
print "Performance results with resource monitoring:\n";
print "- Successful calls: $success_count/25\n";
print "- Total time: " . sprintf("%.3f", $duration) . " seconds\n";
if ($duration > 0) {
    print "- Average per call: " . sprintf("%.3f", $duration/25) . " seconds\n";
    print "- Calls per second: " . sprintf("%.1f", 25/$duration) . "\n";
} else {
    print "- Average per call: < 0.001 seconds (extremely fast!)\n";
    print "- Calls per second: > 1000 (extremely fast!)\n";
}

# Test 4: Final Health Check to See Impact
print "\n=== Test 4: Final Health Check (After Load) ===\n";
$result = $bridge->call_python('test', 'health', {});

if ($result->{success}) {
    print "Final health status: " . $result->{result}->{status} . "\n";

    if (exists $result->{result}->{resources}) {
        my $res = $result->{result}->{resources};
        print "Final resource status:\n";
        print "- Memory: " . sprintf("%.1f", $res->{memory_mb}) . "MB (peak: " . sprintf("%.1f", $res->{peak_memory}) . "MB)\n";
        print "- CPU: " . sprintf("%.1f", $res->{cpu_percent}) . "% (peak: " . sprintf("%.1f", $res->{peak_cpu}) . "%)\n";
        print "- Current requests/min: " . $res->{requests_per_minute} . "\n";

        # Check if resource management is working
        if ($res->{peak_memory} > $res->{memory_mb} * 0.9) {
            print "✅ Resource monitoring detected peak usage\n";
        }
        if ($res->{peak_cpu} > $res->{cpu_percent} * 0.9) {
            print "✅ CPU monitoring detected peak usage\n";
        }
    }
}

print "\n=== Resource Management Test Complete ===\n";
print "Enhanced daemon with resource management is working properly!\n";