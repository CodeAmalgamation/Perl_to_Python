#!/usr/bin/perl
# load_test_throttling.pl - Comprehensive load test for CPAN Bridge daemon throttling
#
# Tests:
# 1. Baseline performance (low load)
# 2. Concurrent request limits (100 concurrent)
# 3. Request rate limits (2000/min)
# 4. Memory pressure monitoring
# 5. Throttling behavior under violations
# 6. Recovery after throttling

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/..";
use CPANBridge;
use Time::HiRes qw(time sleep);
use threads;
use threads::shared;
use POSIX qw(strftime);

# Shared counters
my $total_requests :shared = 0;
my $successful_requests :shared = 0;
my $failed_requests :shared = 0;
my $throttled_requests :shared = 0;

# Configuration
my $TEST_DURATION = 60;  # 60 seconds per test phase
my $VERBOSE = $ENV{LOAD_TEST_VERBOSE} || 0;

print "=" x 80 . "\n";
print "CPAN Bridge Daemon - Throttling Load Test\n";
print "=" x 80 . "\n";
print "Test Configuration:\n";
print "  - MAX_CONCURRENT_REQUESTS: 100\n";
print "  - MAX_REQUESTS_PER_MINUTE: 2000\n";
print "  - MAX_MEMORY_MB: 1024\n";
print "  - Test duration per phase: $TEST_DURATION seconds\n";
print "=" x 80 . "\n\n";

# Phase 1: Baseline Performance Test
print_phase_header("Phase 1: Baseline Performance (10 concurrent)");
run_load_test(
    concurrent => 10,
    duration => 30,
    description => "Establish baseline with light load"
);

# Phase 2: Moderate Load (50 concurrent)
print_phase_header("Phase 2: Moderate Load (50 concurrent)");
run_load_test(
    concurrent => 50,
    duration => 30,
    description => "Test moderate concurrent load"
);

# Phase 3: At Warning Threshold (80 concurrent - 80% of limit)
print_phase_header("Phase 3: Warning Threshold (80 concurrent)");
run_load_test(
    concurrent => 80,
    duration => 30,
    description => "Test at 80% warning threshold"
);

# Phase 4: At Violation Threshold (100 concurrent - exactly at limit)
print_phase_header("Phase 4: Violation Threshold (100 concurrent)");
run_load_test(
    concurrent => 100,
    duration => 30,
    description => "Test at exact concurrent limit"
);

# Phase 5: Over Limit - Trigger Throttling (150 concurrent)
print_phase_header("Phase 5: Throttling Test (150 concurrent - 50% over limit)");
run_load_test(
    concurrent => 150,
    duration => 30,
    description => "Intentionally exceed limits to trigger throttling"
);

# Phase 6: Request Rate Test (2000/min exactly)
print_phase_header("Phase 6: Request Rate Limit (2000/min)");
run_rate_limit_test(
    target_rate => 2000,
    duration => 60,
    description => "Test exact request rate limit"
);

# Phase 7: Request Rate Burst (3000/min - 50% over limit)
print_phase_header("Phase 7: Request Rate Burst (3000/min)");
run_rate_limit_test(
    target_rate => 3000,
    duration => 60,
    description => "Burst test to trigger rate limiting"
);

# Phase 8: Memory Pressure Test
print_phase_header("Phase 8: Memory Pressure Test");
run_memory_pressure_test(
    duration => 30,
    description => "Test with large payloads"
);

# Phase 9: Recovery Test
print_phase_header("Phase 9: Recovery After Throttling");
run_load_test(
    concurrent => 10,
    duration => 20,
    description => "Verify daemon recovers from throttling"
);

# Final Summary
print_final_summary();

exit 0;

#================================================================
# TEST FUNCTIONS
#================================================================

sub run_load_test {
    my %args = @_;

    my $concurrent = $args{concurrent} || 10;
    my $duration = $args{duration} || 30;
    my $desc = $args{description} || "Load test";

    print "  Description: $desc\n";
    print "  Concurrent threads: $concurrent\n";
    print "  Duration: $duration seconds\n\n";

    # Reset counters
    {
        lock($total_requests);
        lock($successful_requests);
        lock($failed_requests);
        lock($throttled_requests);
        $total_requests = 0;
        $successful_requests = 0;
        $failed_requests = 0;
        $throttled_requests = 0;
    }

    my $start_time = time();
    my $end_time = $start_time + $duration;
    my @threads;

    # Get initial metrics
    my $initial_metrics = get_daemon_metrics();
    print_metrics("Initial metrics", $initial_metrics);

    # Spawn worker threads
    print "  Starting $concurrent worker threads...\n";
    for (my $i = 0; $i < $concurrent; $i++) {
        my $thread = threads->create(\&worker_thread, $end_time, $i);
        push @threads, $thread;
    }

    # Monitor progress
    my $last_report = time();
    while (time() < $end_time) {
        sleep(2);

        if (time() - $last_report >= 5) {
            my $elapsed = time() - $start_time;
            my $rate = $total_requests / $elapsed * 60;

            print sprintf("  [%.0fs] Requests: %d (%.0f/min), Success: %d, Failed: %d, Throttled: %d\n",
                $elapsed, $total_requests, $rate, $successful_requests, $failed_requests, $throttled_requests);

            $last_report = time();
        }
    }

    # Wait for all threads to complete
    print "  Waiting for threads to complete...\n";
    foreach my $thread (@threads) {
        $thread->join();
    }

    my $actual_duration = time() - $start_time;

    # Get final metrics
    my $final_metrics = get_daemon_metrics();
    print_metrics("Final metrics", $final_metrics);

    # Calculate statistics
    my $requests_per_sec = $total_requests / $actual_duration;
    my $requests_per_min = $requests_per_sec * 60;
    my $success_rate = $total_requests > 0 ? ($successful_requests / $total_requests * 100) : 0;
    my $throttle_rate = $total_requests > 0 ? ($throttled_requests / $total_requests * 100) : 0;

    print "\n  Results:\n";
    print "  --------\n";
    print sprintf("  Total requests:      %d\n", $total_requests);
    print sprintf("  Successful:          %d (%.1f%%)\n", $successful_requests, $success_rate);
    print sprintf("  Failed:              %d\n", $failed_requests);
    print sprintf("  Throttled:           %d (%.1f%%)\n", $throttled_requests, $throttle_rate);
    print sprintf("  Throughput:          %.1f req/sec (%.0f req/min)\n", $requests_per_sec, $requests_per_min);
    print sprintf("  Avg latency:         %.0f ms\n", ($actual_duration / $total_requests * 1000)) if $total_requests > 0;
    print "\n";

    # Check for resource violations
    if ($final_metrics && $final_metrics->{resource_status}) {
        my $res = $final_metrics->{resource_status};
        if ($res->{violations} && @{$res->{violations}}) {
            print "  ⚠️  RESOURCE VIOLATIONS DETECTED:\n";
            foreach my $violation (@{$res->{violations}}) {
                print "     - $violation\n";
            }
            print "\n";
        }
        if ($res->{warnings} && @{$res->{warnings}}) {
            print "  ⚠️  WARNINGS:\n";
            foreach my $warning (@{$res->{warnings}}) {
                print "     - $warning\n";
            }
            print "\n";
        }
    }

    sleep(2);  # Brief pause between tests
}

sub run_rate_limit_test {
    my %args = @_;

    my $target_rate = $args{target_rate} || 1000;  # requests per minute
    my $duration = $args{duration} || 60;
    my $desc = $args{description} || "Rate limit test";

    print "  Description: $desc\n";
    print "  Target rate: $target_rate requests/minute\n";
    print "  Duration: $duration seconds\n\n";

    # Reset counters
    {
        lock($total_requests);
        lock($successful_requests);
        lock($failed_requests);
        lock($throttled_requests);
        $total_requests = 0;
        $successful_requests = 0;
        $failed_requests = 0;
        $throttled_requests = 0;
    }

    my $start_time = time();
    my $end_time = $start_time + $duration;

    # Calculate delay between requests
    my $requests_per_sec = $target_rate / 60;
    my $delay = 1.0 / $requests_per_sec;

    print sprintf("  Sending requests every %.3f seconds (%.1f req/sec)\n", $delay, $requests_per_sec);

    my $initial_metrics = get_daemon_metrics();
    print_metrics("Initial metrics", $initial_metrics);

    my $request_count = 0;
    my $last_report = time();

    while (time() < $end_time) {
        my $req_start = time();

        # Make request
        make_test_request("rate_test_$request_count");
        $request_count++;

        # Report every 10 seconds
        if (time() - $last_report >= 10) {
            my $elapsed = time() - $start_time;
            my $actual_rate = $total_requests / $elapsed * 60;

            print sprintf("  [%.0fs] Requests: %d (%.0f/min target: %d/min), Success: %d, Throttled: %d\n",
                $elapsed, $total_requests, $actual_rate, $target_rate, $successful_requests, $throttled_requests);

            $last_report = time();
        }

        # Maintain rate
        my $elapsed = time() - $req_start;
        my $sleep_time = $delay - $elapsed;
        sleep($sleep_time) if $sleep_time > 0;
    }

    my $actual_duration = time() - $start_time;
    my $final_metrics = get_daemon_metrics();
    print_metrics("Final metrics", $final_metrics);

    # Calculate statistics
    my $actual_rate = $total_requests / $actual_duration * 60;
    my $success_rate = $total_requests > 0 ? ($successful_requests / $total_requests * 100) : 0;
    my $throttle_rate = $total_requests > 0 ? ($throttled_requests / $total_requests * 100) : 0;

    print "\n  Results:\n";
    print "  --------\n";
    print sprintf("  Total requests:      %d\n", $total_requests);
    print sprintf("  Target rate:         %d req/min\n", $target_rate);
    print sprintf("  Actual rate:         %.0f req/min\n", $actual_rate);
    print sprintf("  Rate accuracy:       %.1f%%\n", ($actual_rate / $target_rate * 100));
    print sprintf("  Successful:          %d (%.1f%%)\n", $successful_requests, $success_rate);
    print sprintf("  Throttled:           %d (%.1f%%)\n", $throttled_requests, $throttle_rate);
    print "\n";

    sleep(2);
}

sub run_memory_pressure_test {
    my %args = @_;

    my $duration = $args{duration} || 30;
    my $desc = $args{description} || "Memory pressure test";

    print "  Description: $desc\n";
    print "  Duration: $duration seconds\n";
    print "  Payload size: ~1MB per request\n\n";

    # Reset counters
    {
        lock($total_requests);
        lock($successful_requests);
        lock($failed_requests);
        $total_requests = 0;
        $successful_requests = 0;
        $failed_requests = 0;
    }

    my $start_time = time();
    my $end_time = $start_time + $duration;

    my $initial_metrics = get_daemon_metrics();
    print_metrics("Initial metrics", $initial_metrics);

    my $initial_memory = $initial_metrics->{resource_status}->{memory_mb} || 0;

    # Send requests with large payloads
    my $request_count = 0;
    while (time() < $end_time) {
        # Create large payload (~1MB)
        my $large_data = "X" x (1024 * 1024);

        make_test_request("memory_test_$request_count", { large_data => $large_data });
        $request_count++;

        sleep(0.5);  # 2 requests per second
    }

    my $final_metrics = get_daemon_metrics();
    print_metrics("Final metrics", $final_metrics);

    my $final_memory = $final_metrics->{resource_status}->{memory_mb} || 0;
    my $memory_delta = $final_memory - $initial_memory;

    print "\n  Results:\n";
    print "  --------\n";
    print sprintf("  Total requests:      %d\n", $total_requests);
    print sprintf("  Initial memory:      %.1f MB\n", $initial_memory);
    print sprintf("  Final memory:        %.1f MB\n", $final_memory);
    print sprintf("  Memory increase:     %.1f MB\n", $memory_delta);
    print sprintf("  Peak memory:         %.1f MB\n", $final_metrics->{resource_status}->{peak_memory} || 0);
    print "\n";

    sleep(2);
}

#================================================================
# WORKER FUNCTIONS
#================================================================

sub worker_thread {
    my ($end_time, $thread_id) = @_;

    my $request_count = 0;

    while (time() < $end_time) {
        make_test_request("thread_${thread_id}_req_${request_count}");
        $request_count++;

        # Small random delay to simulate real traffic
        sleep(0.01 + rand(0.09));  # 10-100ms
    }

    return $request_count;
}

sub make_test_request {
    my ($request_id, $extra_data) = @_;

    {
        lock($total_requests);
        $total_requests++;
    }

    eval {
        my $bridge = CPANBridge->new();

        my $params = {
            request_id => $request_id,
            timestamp => time(),
            %{$extra_data || {}}
        };

        my $result = $bridge->call_python('test', 'ping', $params);

        if ($result && $result->{success}) {
            lock($successful_requests);
            $successful_requests++;
        } else {
            lock($failed_requests);
            $failed_requests++;

            # Check if throttled
            if ($result && $result->{error} && $result->{error} =~ /throttl|limit|resource/i) {
                lock($throttled_requests);
                $throttled_requests++;
            }
        }
    };

    if ($@) {
        lock($failed_requests);
        $failed_requests++;

        if ($@ =~ /throttl|limit|resource/i) {
            lock($throttled_requests);
            $throttled_requests++;
        }

        print "  ERROR: $@\n" if $VERBOSE;
    }
}

sub get_daemon_metrics {
    eval {
        my $bridge = CPANBridge->new();
        my $result = $bridge->call_python('system', 'metrics', {});
        return $result->{result} if $result && $result->{success};
    };
    return undef;
}

#================================================================
# DISPLAY FUNCTIONS
#================================================================

sub print_phase_header {
    my $title = shift;
    print "\n";
    print "=" x 80 . "\n";
    print "$title\n";
    print "=" x 80 . "\n";
}

sub print_metrics {
    my ($label, $metrics) = @_;

    return unless $metrics;

    print "\n  $label:\n";

    if ($metrics->{resource_status}) {
        my $res = $metrics->{resource_status};
        print sprintf("    Memory:        %.1f MB (peak: %.1f MB)\n",
            $res->{memory_mb} || 0, $res->{peak_memory} || 0);
        print sprintf("    CPU:           %.1f%% (peak: %.1f%%)\n",
            $res->{cpu_percent} || 0, $res->{peak_cpu} || 0);
        print sprintf("    Concurrent:    %d\n", $res->{concurrent_requests} || 0);
        print sprintf("    Rate:          %d/min\n", $res->{requests_per_minute} || 0);
    }

    if ($metrics->{performance_metrics}) {
        my $perf = $metrics->{performance_metrics};
        print sprintf("    Total reqs:    %d\n", $perf->{total_requests} || 0);
        print sprintf("    Success rate:  %.1f%%\n",
            (1 - ($perf->{error_rate} || 0)) * 100);
    }
    print "\n";
}

sub print_final_summary {
    print "\n";
    print "=" x 80 . "\n";
    print "LOAD TEST COMPLETE\n";
    print "=" x 80 . "\n";

    my $final_metrics = get_daemon_metrics();

    if ($final_metrics) {
        print "\nDaemon Final State:\n";
        print_metrics("Summary", $final_metrics);

        if ($final_metrics->{resource_status}) {
            my $res = $final_metrics->{resource_status};

            print "Peak Resource Usage:\n";
            print sprintf("  Peak Memory:     %.1f MB (limit: 1024 MB)\n", $res->{peak_memory} || 0);
            print sprintf("  Peak CPU:        %.1f%% (limit: 200%%)\n", $res->{peak_cpu} || 0);
            print "\n";
        }

        if ($final_metrics->{performance_metrics}) {
            my $perf = $final_metrics->{performance_metrics};

            print "Overall Performance:\n";
            print sprintf("  Total Requests:     %d\n", $perf->{total_requests} || 0);
            print sprintf("  Successful:         %d\n", $perf->{successful_requests} || 0);
            print sprintf("  Failed:             %d\n", $perf->{failed_requests} || 0);
            print sprintf("  Success Rate:       %.2f%%\n", (1 - ($perf->{error_rate} || 0)) * 100);
            print sprintf("  Avg Response Time:  %.0f ms\n", ($perf->{avg_response_time} || 0) * 1000);
            print sprintf("  P95 Response Time:  %.0f ms\n", ($perf->{p95_response_time} || 0) * 1000);
            print sprintf("  P99 Response Time:  %.0f ms\n", ($perf->{p99_response_time} || 0) * 1000);
            print "\n";
        }
    }

    print "Test completed at: " . strftime("%Y-%m-%d %H:%M:%S", localtime()) . "\n";
    print "=" x 80 . "\n";
}
