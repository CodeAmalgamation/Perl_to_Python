#!/usr/bin/perl
# extreme_stress_test.pl - Push daemon to memory and CPU limits
#
# Combines concurrent threads + large payloads + high request rate

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
my $throttled :shared = 0;

print "Extreme Stress Test - Push Daemon to Limits\n";
print "=" x 70 . "\n";
print "Goal: Trigger memory and CPU violations\n\n";

# Get baseline
my $bridge = CPANBridge->new();
my $baseline = $bridge->call_python('system', 'metrics', {});
if ($baseline && $baseline->{resource_status}) {
    my $res = $baseline->{resource_status};
    printf "Baseline: %.1f MB memory, %.1f%% CPU\n\n",
        $res->{memory_mb}, $res->{cpu_percent};
}

# Test 1: Concurrent threads with medium payloads
print "Test 1: Warm-up - 30 threads × 500KB payloads (30s)\n";
print "  Expected: Increase memory and CPU usage\n";
run_concurrent_test(30, 500 * 1024, 30, "500KB");

sleep(5);
print_metrics("After warm-up");

# Test 2: More threads + larger payloads
print "\nTest 2: Ramp-up - 60 threads × 1MB payloads (30s)\n";
print "  Expected: Higher memory usage, possible warnings\n";
run_concurrent_test(60, 1024 * 1024, 30, "1MB");

sleep(5);
print_metrics("After ramp-up");

# Test 3: Heavy concurrent load
print "\nTest 3: Heavy load - 100 threads × 1MB payloads (45s)\n";
print "  Expected: Approach or exceed memory limit (1024 MB)\n";
run_concurrent_test(100, 1024 * 1024, 45, "1MB");

sleep(5);
print_metrics("After heavy load");

# Test 4: Extreme - max threads + large payloads
print "\nTest 4: EXTREME - 150 threads × 2MB payloads (60s)\n";
print "  Expected: Memory violations, CPU throttling\n";
run_concurrent_test(150, 2 * 1024 * 1024, 60, "2MB");

sleep(5);
print_metrics("After extreme load");

# Test 5: Recovery check
print "\nTest 5: Recovery - 10 threads × 10KB payloads (20s)\n";
run_concurrent_test(10, 10 * 1024, 20, "10KB");

print "\n" . "=" x 70 . "\n";
print "Extreme stress test complete!\n\n";

my $total = $success + $failed;
printf "Total requests: %d\n", $total;
printf "Success: %d (%.1f%%)\n", $success, ($total > 0 ? $success/$total*100 : 0);
printf "Failed: %d (%.1f%%)\n", $failed, ($total > 0 ? $failed/$total*100 : 0);
printf "Throttled: %d\n\n", $throttled;

print_metrics("Final state");

sub run_concurrent_test {
    my ($num_threads, $payload_size, $duration, $label) = @_;

    my $test_success :shared = 0;
    my $test_failed :shared = 0;

    my $start = time();
    my $end = $start + $duration;
    my @threads;

    # Spawn worker threads
    for my $i (1..$num_threads) {
        push @threads, threads->create(sub {
            my $thread_id = $i;
            my $payload = 'X' x $payload_size;
            my $count = 0;

            while (time() < $end) {
                eval {
                    my $req_start = time();
                    my $b = CPANBridge->new();
                    my $result = $b->call_python('test', 'ping', {
                        data => $payload,
                        thread_id => $thread_id,
                        request_num => $count
                    });

                    my $elapsed = time() - $req_start;

                    if ($result && ref($result) eq 'HASH' && $result->{message}) {
                        { lock($success); $success++; }
                        { lock($test_success); $test_success++; }

                        # Detect throttling (>500ms response time)
                        if ($elapsed > 0.5) {
                            lock($throttled); $throttled++;
                        }
                    } else {
                        { lock($failed); $failed++; }
                        { lock($test_failed); $test_failed++; }
                    }
                };
                if ($@) {
                    { lock($failed); $failed++; }
                    { lock($test_failed); $test_failed++; }
                }

                $count++;
                sleep(0.05 + rand(0.15));  # 50-200ms between requests
            }

            return $count;
        });
    }

    # Monitor progress
    my $last_report = time();
    while (time() < $end) {
        if (time() - $last_report >= 5) {
            my $elapsed = time() - $start;
            my $rate = $test_success / ($elapsed || 1) * 60;
            printf "  [%.0fs] Success: %d (%.0f/min), Failed: %d, Throttled: %d\n",
                $elapsed, $test_success, $rate, $test_failed, $throttled;
            $last_report = time();

            # Check daemon state
            eval {
                my $b = CPANBridge->new();
                my $m = $b->call_python('system', 'metrics', {});
                if ($m && $m->{resource_status}) {
                    my $r = $m->{resource_status};
                    printf "    Daemon: %.1f MB, %.1f%% CPU, %d concurrent\n",
                        $r->{memory_mb}, $r->{cpu_percent}, $r->{concurrent_requests};
                }
            };
        }
        sleep(1);
    }

    # Wait for all threads
    my $total_requests = 0;
    for my $t (@threads) {
        $total_requests += $t->join();
    }

    my $total_time = time() - $start;
    printf "  Completed: %d requests in %.1fs\n", $total_requests, $total_time;
    printf "  Success: %d, Failed: %d\n", $test_success, $test_failed;
}

sub print_metrics {
    my $label = shift;

    eval {
        my $b = CPANBridge->new();
        my $result = $b->call_python('system', 'metrics', {});
        if ($result && $result->{resource_status}) {
            my $res = $result->{resource_status};

            print "\n[$label]\n";
            printf "  Memory: %.1f MB (peak: %.1f MB) - %.1f%% of limit\n",
                $res->{memory_mb}, $res->{peak_memory},
                ($res->{peak_memory} / 1024 * 100);
            printf "  CPU: %.1f%% (peak: %.1f%%)\n",
                $res->{cpu_percent}, $res->{peak_cpu};
            printf "  Concurrent: %d, Rate: %d/min\n",
                $res->{concurrent_requests}, $res->{requests_per_minute};

            if (@{$res->{warnings}}) {
                print "  ⚠️  WARNINGS: " . join(", ", @{$res->{warnings}}) . "\n";
            }
            if (@{$res->{violations}}) {
                print "  🚨 VIOLATIONS: " . join(", ", @{$res->{violations}}) . "\n";
            }
        }
    };
}
