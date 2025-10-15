#!/usr/bin/perl
# memory_pressure_test.pl - Test daemon behavior under memory pressure
#
# Tests daemon's memory monitoring and throttling under heavy payload conditions

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/..";
use CPANBridge;
use Time::HiRes qw(time sleep);

print "Memory Pressure Test - Daemon Memory Management\n";
print "=" x 70 . "\n\n";

# Get baseline metrics
print "Getting baseline metrics...\n";
my $bridge = CPANBridge->new();
my $baseline = $bridge->call_python('system', 'metrics', {});
if ($baseline && $baseline->{success}) {
    my $res = $baseline->{result}->{resource_status};
    printf "Baseline: %.1f MB memory, %.1f%% CPU\n\n",
        $res->{memory_mb}, $res->{cpu_percent};
}

# Test 1: Small payloads (1KB each) - baseline
print "Test 1: Baseline - 100 requests with 1KB payloads\n";
run_memory_test(100, 1024, "1KB");

sleep(5);

# Test 2: Medium payloads (100KB each)
print "\nTest 2: Medium load - 50 requests with 100KB payloads\n";
run_memory_test(50, 100 * 1024, "100KB");

sleep(5);

# Test 3: Large payloads (1MB each)
print "\nTest 3: Heavy load - 25 requests with 1MB payloads\n";
run_memory_test(25, 1024 * 1024, "1MB");

sleep(5);

# Test 4: Very large payloads (5MB each) - stress test
print "\nTest 4: Extreme load - 10 requests with 5MB payloads\n";
run_memory_test(10, 5 * 1024 * 1024, "5MB");

sleep(5);

# Test 5: Burst of medium payloads (rapid fire)
print "\nTest 5: Burst test - 100 requests with 500KB payloads (rapid)\n";
run_memory_test(100, 500 * 1024, "500KB", 0.1);

print "\n" . "=" x 70 . "\n";
print "Memory pressure test complete!\n";

# Get final metrics
print "\nFinal daemon state:\n";
my $final = $bridge->call_python('system', 'metrics', {});
if ($final && $final->{success}) {
    my $res = $final->{result}->{resource_status};
    printf "Memory: %.1f MB, CPU: %.1f%%, Concurrent: %d, Rate: %d/min\n",
        $res->{memory_mb}, $res->{cpu_percent},
        $res->{concurrent_requests}, $res->{requests_per_minute};
}

sub run_memory_test {
    my ($num_requests, $payload_size, $label, $delay) = @_;
    $delay //= 0.5;  # Default 500ms between requests

    my $success = 0;
    my $failed = 0;
    my $start = time();

    # Create large payload
    my $payload = 'X' x $payload_size;

    for my $i (1..$num_requests) {
        eval {
            my $b = CPANBridge->new();
            my $result = $b->call_python('test', 'ping', {
                data => $payload,
                request_id => "mem_test_${i}"
            });

            if ($result && ref($result) eq 'HASH' && $result->{message}) {
                $success++;
            } else {
                $failed++;
            }
        };
        if ($@) {
            $failed++;
            print "  ERROR on request $i: $@\n";
        }

        # Progress indicator
        if ($i % 10 == 0 || $i == $num_requests) {
            my $elapsed = time() - $start;
            printf "  [%d/%d] Success: %d, Failed: %d (%.1fs elapsed)\n",
                $i, $num_requests, $success, $failed, $elapsed;
        }

        sleep($delay);
    }

    my $total_time = time() - $start;
    my $total = $success + $failed;

    printf "  Results: %d requests in %.1fs\n", $total, $total_time;
    printf "  Success: %d (%.1f%%), Failed: %d\n",
        $success, ($success/$total*100), $failed;

    # Get daemon metrics after this test
    eval {
        my $b = CPANBridge->new();
        my $result = $b->call_python('system', 'metrics', {});
        if ($result && $result->{success}) {
            my $res = $result->{result}->{resource_status};
            printf "  Daemon memory: %.1f MB (%.1f%% CPU)\n",
                $res->{memory_mb}, $res->{cpu_percent};

            # Check for memory warnings
            if ($res->{memory_mb} > 800) {
                print "  ⚠️  WARNING: Memory usage high (>800 MB)\n";
            }
            if ($res->{memory_mb} > 1024) {
                print "  🚨 CRITICAL: Memory limit exceeded!\n";
            }
        }
    };
}
