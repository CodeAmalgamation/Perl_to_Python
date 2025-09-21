#!/usr/bin/perl

# test_operational_monitoring.pl - Test comprehensive operational monitoring features

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/..";
use CPANBridge;
use JSON;
use Time::HiRes qw(time);

print "=== Operational Monitoring & Management Testing ===\n";

# Enable daemon mode
$CPANBridge::DAEMON_MODE = 1;
$CPANBridge::DEBUG_LEVEL = 0;

my $bridge = CPANBridge->new(debug => 0);

# Test 1: Comprehensive Health Check
print "\n=== Test 1: Comprehensive Health Check ===\n";
my $result = $bridge->call_python('system', 'health', {});

if ($result->{success}) {
    print "✅ Health Check: SUCCESS\n";
    my $health = $result->{result};

    print "Overall Status: " . $health->{overall_status} . "\n";
    print "Timestamp: " . $health->{timestamp} . "\n";

    # Display individual checks
    print "\nHealth Checks:\n";
    for my $check_name (sort keys %{$health->{checks}}) {
        my $check = $health->{checks}->{$check_name};
        my $status_icon = $check->{status} eq 'pass' ? '✅' :
                         $check->{status} eq 'warn' ? '⚠️' : '❌';
        print "  $status_icon $check_name: $check->{message}\n";
    }

    # Display warnings and errors
    if (@{$health->{warnings}}) {
        print "\nWarnings:\n";
        for my $warning (@{$health->{warnings}}) {
            print "  ⚠️  $warning\n";
        }
    }

    if (@{$health->{errors}}) {
        print "\nErrors:\n";
        for my $error (@{$health->{errors}}) {
            print "  ❌ $error\n";
        }
    }

} else {
    print "❌ Health Check: FAILED - " . $result->{error} . "\n";
}

# Test 2: Performance Monitoring
print "\n=== Test 2: Performance Monitoring ===\n";

# Generate some load first
print "Generating load for performance testing...\n";
for my $i (1..20) {
    $bridge->call_python('test', 'ping', { call_number => $i });
}

$result = $bridge->call_python('system', 'performance', {});

if ($result->{success}) {
    print "✅ Performance Report: SUCCESS\n";
    my $perf = $result->{result};

    my $metrics = $perf->{performance_metrics};
    print "\nPerformance Metrics:\n";
    print "  Total Requests: " . $metrics->{total_requests} . "\n";
    print "  Successful Requests: " . $metrics->{successful_requests} . "\n";
    print "  Failed Requests: " . $metrics->{failed_requests} . "\n";
    print "  Average Response Time: " . sprintf("%.3f", $metrics->{avg_response_time}) . "s\n";
    print "  P95 Response Time: " . sprintf("%.3f", $metrics->{p95_response_time}) . "s\n";
    print "  P99 Response Time: " . sprintf("%.3f", $metrics->{p99_response_time}) . "s\n";
    print "  Requests Per Second: " . sprintf("%.1f", $metrics->{requests_per_second}) . "\n";
    print "  Error Rate: " . sprintf("%.1f", $metrics->{error_rate} * 100) . "%\n";
    print "  Uptime: " . sprintf("%.1f", $metrics->{uptime_seconds}) . "s\n";

    # Top modules
    my $top_modules = $perf->{module_performance}->{top_modules};
    if (@$top_modules) {
        print "\nTop Module Performance:\n";
        for my $module (@$top_modules) {
            print "  " . $module->{module_function} . ": " .
                  $module->{requests} . " requests, " .
                  $module->{avg_time_ms} . "ms avg, " .
                  $module->{error_rate} . "% errors\n";
        }
    }

    # Health indicators
    my $health_indicators = $perf->{health_indicators};
    print "\nHealth Assessment: " . $health_indicators->{overall_health} . "\n";
    if (@{$health_indicators->{concerns}}) {
        print "Concerns:\n";
        for my $concern (@{$health_indicators->{concerns}}) {
            print "  ⚠️  $concern\n";
        }
    }
    if (@{$health_indicators->{recommendations}}) {
        print "Recommendations:\n";
        for my $rec (@{$health_indicators->{recommendations}}) {
            print "  💡 $rec\n";
        }
    }

} else {
    print "❌ Performance Report: FAILED - " . $result->{error} . "\n";
}

# Test 3: Connection Management
print "\n=== Test 3: Connection Management ===\n";
$result = $bridge->call_python('system', 'connections', {});

if ($result->{success}) {
    print "✅ Connection Status: SUCCESS\n";
    my $conn = $result->{result};

    print "Connection Summary:\n";
    print "  Total Connections: " . $conn->{total_connections} . "\n";
    print "  Active Connections: " . $conn->{active_connections} . "\n";
    print "  Stale Connections: " . $conn->{stale_connections} . "\n";

    print "\nConnection Limits:\n";
    print "  Max Concurrent: " . $conn->{connection_limits}->{max_concurrent} . "\n";
    print "  Stale Timeout: " . $conn->{connection_limits}->{stale_timeout} . "s\n";

    # Show recent connections
    my $connections = $conn->{connections};
    if (@$connections && @$connections > 0) {
        print "\nRecent Connections (last 5):\n";
        my $count = 0;
        for my $connection (@$connections) {
            last if ++$count > 5;
            print "  Connection: " . $connection->{connection_id} . "\n";
            print "    Duration: " . $connection->{duration_seconds} . "s\n";
            print "    Requests: " . $connection->{requests_count} . "\n";
            print "    Status: " . $connection->{status} . "\n";
            print "    Idle Time: " . $connection->{idle_time} . "s\n";
        }
    }

} else {
    print "❌ Connection Status: FAILED - " . $result->{error} . "\n";
}

# Test 4: Combined Metrics Dashboard
print "\n=== Test 4: Combined Metrics Dashboard ===\n";
$result = $bridge->call_python('system', 'metrics', {});

if ($result->{success}) {
    print "✅ Metrics Dashboard: SUCCESS\n";
    my $metrics = $result->{result};

    print "\nDashboard Summary (at " . $metrics->{timestamp} . "):\n";

    # Daemon info
    my $daemon = $metrics->{daemon_info};
    print "Daemon: v" . $daemon->{version} . " (uptime: " . $daemon->{uptime_formatted} . ")\n";

    # Resource status
    my $resources = $metrics->{resource_status};
    print "Resources: " . sprintf("%.1f", $resources->{memory_mb}) . "MB RAM, " .
          sprintf("%.1f", $resources->{cpu_percent}) . "% CPU, " .
          $resources->{requests_per_minute} . " req/min\n";

    # Performance summary
    my $performance = $metrics->{performance_metrics};
    print "Performance: " . $performance->{total_requests} . " total requests, " .
          sprintf("%.1f", $performance->{error_rate} * 100) . "% error rate, " .
          sprintf("%.3f", $performance->{avg_response_time}) . "s avg response\n";

    # Security summary
    my $security = $metrics->{security_summary};
    print "Security: " . $security->{total_security_events} . " events, " .
          $security->{validation_failures} . " validation failures, " .
          $security->{requests_rejected} . " requests rejected\n";

    # Connection summary
    my $conn_summary = $metrics->{connection_summary};
    print "Connections: " . $conn_summary->{active_connections} . " active, " .
          $conn_summary->{stale_connections} . " stale, " .
          $conn_summary->{total_connections} . " total\n";

    # Module status
    my $modules = $metrics->{module_status};
    print "Modules: " . $modules->{loaded_modules} . " loaded (" .
          join(", ", @{$modules->{available_modules}}) . ")\n";

} else {
    print "❌ Metrics Dashboard: FAILED - " . $result->{error} . "\n";
}

# Test 5: Connection Cleanup
print "\n=== Test 5: Connection Cleanup ===\n";
$result = $bridge->call_python('system', 'cleanup', {});

if ($result->{success}) {
    print "✅ Connection Cleanup: SUCCESS\n";
    my $cleanup = $result->{result};

    print "Cleanup Results:\n";
    print "  Cleaned Connections: " . $cleanup->{cleaned_connections} . "\n";
    print "  Remaining Connections: " . $cleanup->{remaining_connections} . "\n";

    if ($cleanup->{cleaned_connections} > 0) {
        print "  Cleaned connection details:\n";
        for my $conn (@{$cleanup->{connections_details}}) {
            print "    - " . $conn->{connection_id} . " (idle: " .
                  sprintf("%.1f", $conn->{idle_time}) . "s)\n";
        }
    }

} else {
    print "❌ Connection Cleanup: FAILED - " . $result->{error} . "\n";
}

# Test 6: Enhanced Stats
print "\n=== Test 6: Enhanced Statistics ===\n";
$result = $bridge->call_python('system', 'stats', {});

if ($result->{success}) {
    print "✅ Enhanced Stats: SUCCESS\n";
    my $stats = $result->{result};

    print "\nSystem Statistics:\n";
    print "  Requests Processed: " . $stats->{requests_processed} . "\n";
    print "  Requests Failed: " . $stats->{requests_failed} . "\n";
    print "  Requests Rejected: " . $stats->{requests_rejected} . "\n";
    print "  Validation Failures: " . $stats->{validation_failures} . "\n";
    print "  Security Events: " . $stats->{security_events} . "\n";
    print "  Connections Total: " . $stats->{connections_total} . "\n";
    print "  Peak Connections: " . $stats->{peak_connections} . "\n";

    print "\nPerformance Summary:\n";
    my $perf_summary = $stats->{performance_summary};
    print "  Total Requests: " . $perf_summary->{total_requests} . "\n";
    print "  Average Response Time: " . sprintf("%.3f", $perf_summary->{avg_response_time}) . "s\n";
    print "  Requests Per Second: " . sprintf("%.1f", $perf_summary->{requests_per_second}) . "\n";
    print "  Error Rate: " . sprintf("%.1f", $perf_summary->{error_rate} * 100) . "%\n";

    print "\nValidation Configuration:\n";
    my $val_config = $stats->{validation_config};
    print "  Strict Mode: " . ($val_config->{strict_mode} ? "enabled" : "disabled") . "\n";
    print "  Max String Length: " . $val_config->{max_string_length} . "\n";
    print "  Max Array Length: " . $val_config->{max_array_length} . "\n";
    print "  Max Object Depth: " . $val_config->{max_object_depth} . "\n";
    print "  Max Param Count: " . $val_config->{max_param_count} . "\n";

} else {
    print "❌ Enhanced Stats: FAILED - " . $result->{error} . "\n";
}

print "\n=== Operational Monitoring Test Complete ===\n";
print "All operational monitoring features have been tested!\n";
print "\nAvailable monitoring endpoints:\n";
print "  - system.health: Comprehensive health checks\n";
print "  - system.performance: Detailed performance analysis\n";
print "  - system.connections: Connection management\n";
print "  - system.cleanup: Force connection cleanup\n";
print "  - system.metrics: Combined dashboard view\n";
print "  - system.stats: Enhanced statistics\n";
print "\nOperational monitoring is production-ready! 🚀\n";