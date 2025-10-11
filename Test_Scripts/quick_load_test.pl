#!/usr/bin/perl
# quick_load_test.pl - Quick load test to verify throttling (5 minutes)
#
# Simplified version for quick testing of throttling behavior

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/..";
use CPANBridge;
use Time::HiRes qw(time sleep);
use threads;
use threads::shared;

my $success :shared = 0;
my $failed :shared = 0;

print "Quick Load Test - Throttling Verification\n";
print "=" x 60 . "\n\n";

# Test 1: Baseline (20 concurrent for 15 seconds)
print "Test 1: Baseline (20 concurrent threads, 15s)\n";
run_test(20, 15);

# Test 2: At threshold (80 concurrent for 15 seconds)
print "\nTest 2: Warning Threshold (80 concurrent, 15s)\n";
run_test(80, 15);

# Test 3: Over limit (120 concurrent for 15 seconds)
print "\nTest 3: Over Limit (120 concurrent, 15s - should throttle)\n";
run_test(120, 15);

# Test 4: Recovery (10 concurrent for 10 seconds)
print "\nTest 4: Recovery (10 concurrent, 10s)\n";
run_test(10, 10);

print "\n" . "=" x 60 . "\n";
print "Quick load test complete!\n";

sub run_test {
    my ($concurrent, $duration) = @_;

    $success = 0;
    $failed = 0;

    my $start = time();
    my $end = $start + $duration;
    my @threads;

    # Start workers
    for (1..$concurrent) {
        push @threads, threads->create(sub {
            while (time() < $end) {
                eval {
                    my $bridge = CPANBridge->new();
                    my $result = $bridge->call_python('test', 'ping', {});
                    if ($result && $result->{success}) {
                        lock($success); $success++;
                    } else {
                        lock($failed); $failed++;
                    }
                };
                if ($@) {
                    lock($failed); $failed++;
                }
                sleep(0.05);  # 50ms delay
            }
        });
    }

    # Monitor
    while (time() < $end) {
        sleep(3);
        my $elapsed = time() - $start;
        my $rate = $success / $elapsed * 60;
        print sprintf("  [%.0fs] Success: %d (%.0f/min), Failed: %d\n",
            $elapsed, $success, $rate, $failed);
    }

    # Wait for completion
    $_->join() for @threads;

    my $total_time = time() - $start;
    my $total = $success + $failed;
    my $rate = $success / $total_time;

    print sprintf("  Total: %d requests in %.1fs (%.1f req/sec)\n",
        $total, $total_time, $rate);
    print sprintf("  Success: %d (%.1f%%), Failed: %d\n",
        $success, ($success/$total*100), $failed);

    # Get daemon metrics
    eval {
        my $bridge = CPANBridge->new();
        my $result = $bridge->call_python('system', 'metrics', {});
        if ($result && $result->{success}) {
            my $res = $result->{result}->{resource_status};
            print sprintf("  Daemon: %.1f MB, %.1f%% CPU, %d concurrent, %d/min\n",
                $res->{memory_mb}, $res->{cpu_percent},
                $res->{concurrent_requests}, $res->{requests_per_minute});
        }
    };
}
