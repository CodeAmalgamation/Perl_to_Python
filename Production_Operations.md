# CPAN Bridge Daemon - Production Operations Guide

**A comprehensive guide for monitoring, troubleshooting, and maintaining the CPAN Bridge daemon in production environments.**

---

## 📋 Table of Contents

1. [Quick Start](#quick-start)
2. [Daily Operations](#daily-operations)
3. [Monitoring Dashboard](#monitoring-dashboard)
4. [Health Checks](#health-checks)
5. [Performance Monitoring](#performance-monitoring)
6. [Troubleshooting Guide](#troubleshooting-guide)
7. [Maintenance Tasks](#maintenance-tasks)
8. [Alert Thresholds](#alert-thresholds)
9. [Emergency Procedures](#emergency-procedures)

---

## 🚀 Quick Start

### Essential Commands

```bash
# Check if daemon is running
ps aux | grep cpan_daemon

# Start daemon
python python_helpers/cpan_daemon.py &

# Quick health check
perl -e 'use CPANBridge; my $bridge = CPANBridge->new(); $CPANBridge::DAEMON_MODE = 1; my $r = $bridge->call_python("system", "health", {}); print $r->{result}->{overall_status} . "\n";'

# View daemon logs
tail -f /tmp/cpan_daemon.log

# Emergency shutdown
pkill -f cpan_daemon.py
```

### Key Files to Monitor

```
/tmp/cpan_daemon.log          # Main daemon logs
/tmp/cpan_security.log        # Security event logs
/tmp/cpan_bridge.sock         # Unix socket file
```

---

## 📊 Daily Operations

### Morning Health Check (5 minutes)

```bash
# 1. Check daemon status
ps aux | grep cpan_daemon | grep -v grep
# Expected: Should show running Python process

# 2. Quick health overview
perl -e '
use lib "."; use CPANBridge;
my $bridge = CPANBridge->new();
$CPANBridge::DAEMON_MODE = 1;
my $r = $bridge->call_python("system", "metrics", {});
if ($r->{success}) {
    my $m = $r->{result};
    print "=== DAILY STATUS REPORT ===\n";
    print "Health: " . $m->{daemon_info}->{uptime_formatted} . " uptime\n";
    print "Performance: " . $m->{performance_metrics}->{total_requests} . " requests, " .
          sprintf("%.1f", $m->{performance_metrics}->{error_rate} * 100) . "% errors\n";
    print "Resources: " . sprintf("%.1f", $m->{resource_status}->{memory_mb}) . "MB RAM, " .
          sprintf("%.1f", $m->{resource_status}->{cpu_percent}) . "% CPU\n";
    print "Connections: " . $m->{connection_summary}->{active_connections} . " active\n";
    print "Security: " . $m->{security_summary}->{total_security_events} . " events\n";
}'

# 3. Check for errors in logs
tail -50 /tmp/cpan_daemon.log | grep -i error | wc -l
# Expected: 0 or very low number

# 4. Check security events
tail -20 /tmp/cpan_security.log | grep -c "SECURITY ALERT"
# Expected: 0 unless under attack
```

### Weekly Maintenance (10 minutes)

```bash
# 1. Review performance trends
perl -e '
use lib "."; use CPANBridge;
my $bridge = CPANBridge->new();
$CPANBridge::DAEMON_MODE = 1;
my $r = $bridge->call_python("system", "performance", {});
if ($r->{success}) {
    my $p = $r->{result};
    print "=== WEEKLY PERFORMANCE REVIEW ===\n";
    print "Total Requests: " . $p->{performance_metrics}->{total_requests} . "\n";
    print "Average Response Time: " . sprintf("%.3f", $p->{performance_metrics}->{avg_response_time}) . "s\n";
    print "P95 Response Time: " . sprintf("%.3f", $p->{performance_metrics}->{p95_response_time}) . "s\n";
    print "Requests Per Second: " . sprintf("%.1f", $p->{performance_metrics}->{requests_per_second}) . "\n";

    print "\nTop Modules:\n";
    for my $mod (@{$p->{module_performance}->{top_modules}}) {
        printf "  %s: %d requests, %.2fms avg\n",
               $mod->{module_function}, $mod->{requests}, $mod->{avg_time_ms};
    }

    if (@{$p->{health_indicators}->{recommendations}}) {
        print "\nRecommendations:\n";
        for (@{$p->{health_indicators}->{recommendations}}) {
            print "  • $_\n";
        }
    }
}'

# 2. Clean up old connections
perl -e 'use lib "."; use CPANBridge; my $bridge = CPANBridge->new(); $CPANBridge::DAEMON_MODE = 1; my $r = $bridge->call_python("system", "cleanup", {}); print "Cleaned " . $r->{result}->{cleaned_connections} . " stale connections\n";'

# 3. Archive old logs (if needed)
# mv /tmp/cpan_daemon.log /tmp/cpan_daemon_$(date +%Y%m%d).log
# mv /tmp/cpan_security.log /tmp/cpan_security_$(date +%Y%m%d).log
```

---

## 🖥 Monitoring Dashboard

### Real-Time Dashboard Command

```bash
# Complete operational dashboard
perl -e '
use lib "."; use CPANBridge;
my $bridge = CPANBridge->new();
$CPANBridge::DAEMON_MODE = 1;

print "\033[2J\033[H";  # Clear screen
print "🚀 CPAN BRIDGE DAEMON - OPERATIONAL DASHBOARD\n";
print "=" x 60 . "\n";

my $r = $bridge->call_python("system", "metrics", {});
if ($r->{success}) {
    my $m = $r->{result};

    # Header info
    print sprintf("📅 %s | v%s | ⏱ %s\n\n",
                  $m->{timestamp},
                  $m->{daemon_info}->{version},
                  $m->{daemon_info}->{uptime_formatted});

    # Performance section
    my $perf = $m->{performance_metrics};
    print "📊 PERFORMANCE\n";
    print "  Requests: " . $perf->{total_requests} . " total, " .
          sprintf("%.1f", $perf->{requests_per_second}) . "/sec\n";
    print "  Response: " . sprintf("%.3f", $perf->{avg_response_time}) . "s avg, " .
          sprintf("%.3f", $perf->{p95_response_time}) . "s P95\n";
    print "  Errors: " . sprintf("%.1f", $perf->{error_rate} * 100) . "%\n\n";

    # Resource section
    my $res = $m->{resource_status};
    print "💾 RESOURCES\n";
    printf "  Memory: %.1fMB", $res->{memory_mb};
    if ($res->{memory_mb} > 500) { print " ⚠️"; }
    elsif ($res->{memory_mb} > 1000) { print " 🔴"; }
    print "\n";

    printf "  CPU: %.1f%%", $res->{cpu_percent};
    if ($res->{cpu_percent} > 80) { print " ⚠️"; }
    elsif ($res->{cpu_percent} > 95) { print " 🔴"; }
    print "\n";

    print "  Load: " . $res->{requests_per_minute} . " req/min\n\n";

    # Connections section
    my $conn = $m->{connection_summary};
    print "🔌 CONNECTIONS\n";
    print "  Active: " . $conn->{active_connections};
    if ($conn->{active_connections} > 40) { print " ⚠️"; }
    print "\n";
    print "  Stale: " . $conn->{stale_connections};
    if ($conn->{stale_connections} > 5) { print " ⚠️"; }
    print "\n";
    print "  Total: " . $conn->{total_connections} . "\n\n";

    # Security section
    my $sec = $m->{security_summary};
    print "🔒 SECURITY\n";
    print "  Events: " . $sec->{total_security_events};
    if ($sec->{total_security_events} > 0) { print " ⚠️"; }
    print "\n";
    print "  Rejected: " . $sec->{requests_rejected};
    if ($sec->{requests_rejected} > 0) { print " ⚠️"; }
    print "\n\n";

    # Modules section
    my $mod = $m->{module_status};
    print "🧩 MODULES: " . $mod->{loaded_modules} . " loaded\n";
    print "  " . join(", ", @{$mod->{available_modules}}) . "\n";
}

print "\n📝 Use Ctrl+C to exit\n";
'
```

### Watch Mode Dashboard (Auto-refresh every 5 seconds)

```bash
# Create a watch script
cat > watch_dashboard.sh << 'EOF'
#!/bin/bash
while true; do
    clear
    echo "🚀 CPAN BRIDGE DAEMON - LIVE DASHBOARD ($(date))"
    echo "=================================================="

    perl -e '
    use lib "."; use CPANBridge;
    my $bridge = CPANBridge->new();
    $CPANBridge::DAEMON_MODE = 1;
    my $r = $bridge->call_python("system", "metrics", {});
    if ($r->{success}) {
        my $m = $r->{result};
        printf "Status: %s uptime | %.1fMB RAM | %.1f%% CPU | %d active connections\n",
               $m->{daemon_info}->{uptime_formatted},
               $m->{resource_status}->{memory_mb},
               $m->{resource_status}->{cpu_percent},
               $m->{connection_summary}->{active_connections};
        printf "Performance: %d requests | %.3fs avg | %.1f%% errors | %.1f req/sec\n",
               $m->{performance_metrics}->{total_requests},
               $m->{performance_metrics}->{avg_response_time},
               $m->{performance_metrics}->{error_rate} * 100,
               $m->{performance_metrics}->{requests_per_second};
    } else {
        print "❌ DAEMON NOT RESPONDING\n";
    }'

    echo -e "\nPress Ctrl+C to stop monitoring"
    sleep 5
done
EOF

chmod +x watch_dashboard.sh
./watch_dashboard.sh
```

---

## 🏥 Health Checks

### Comprehensive Health Check

```bash
# Full health assessment
perl -e '
use lib "."; use CPANBridge;
my $bridge = CPANBridge->new();
$CPANBridge::DAEMON_MODE = 1;
my $r = $bridge->call_python("system", "health", {});

if ($r->{success}) {
    my $h = $r->{result};
    print "🏥 HEALTH STATUS: " . uc($h->{overall_status}) . "\n";
    print "📅 Check Time: " . $h->{timestamp} . "\n\n";

    print "DETAILED CHECKS:\n";
    for my $check (sort keys %{$h->{checks}}) {
        my $c = $h->{checks}->{$check};
        my $icon = $c->{status} eq "pass" ? "✅" :
                   $c->{status} eq "warn" ? "⚠️" : "❌";
        print "$icon $check: $c->{message}\n";
    }

    if (@{$h->{warnings}}) {
        print "\n⚠️ WARNINGS:\n";
        for (@{$h->{warnings}}) { print "  • $_\n"; }
    }

    if (@{$h->{errors}}) {
        print "\n❌ ERRORS:\n";
        for (@{$h->{errors}}) { print "  • $_\n"; }
    }
} else {
    print "❌ HEALTH CHECK FAILED: " . $r->{error} . "\n";
}'
```

### Quick Health Status

```bash
# One-liner health check
perl -e 'use lib "."; use CPANBridge; my $bridge = CPANBridge->new(); $CPANBridge::DAEMON_MODE = 1; my $r = $bridge->call_python("system", "health", {}); print "Health: " . ($r->{success} ? $r->{result}->{overall_status} : "FAILED") . "\n";'
```

### Health Check Exit Codes

Create a health check script for monitoring systems:

```bash
cat > health_check.sh << 'EOF'
#!/bin/bash
# Returns 0 for healthy, 1 for degraded, 2 for unhealthy, 3 for unreachable

RESULT=$(perl -e '
use lib "."; use CPANBridge;
my $bridge = CPANBridge->new();
$CPANBridge::DAEMON_MODE = 1;
my $r = $bridge->call_python("system", "health", {});
if ($r->{success}) {
    print $r->{result}->{overall_status};
} else {
    print "unreachable";
}' 2>/dev/null)

case "$RESULT" in
    "healthy")   exit 0 ;;
    "degraded")  exit 1 ;;
    "unhealthy") exit 2 ;;
    *)           exit 3 ;;
esac
EOF

chmod +x health_check.sh
```

---

## 📈 Performance Monitoring

### Performance Analysis

```bash
# Detailed performance report
perl -e '
use lib "."; use CPANBridge;
my $bridge = CPANBridge->new();
$CPANBridge::DAEMON_MODE = 1;
my $r = $bridge->call_python("system", "performance", {});

if ($r->{success}) {
    my $p = $r->{result};
    my $m = $p->{performance_metrics};

    print "📈 PERFORMANCE ANALYSIS\n";
    print "=" x 40 . "\n";

    print "Request Statistics:\n";
    print "  Total: " . $m->{total_requests} . "\n";
    print "  Successful: " . $m->{successful_requests} . "\n";
    print "  Failed: " . $m->{failed_requests} . "\n";
    print "  Success Rate: " . sprintf("%.1f", (1 - $m->{error_rate}) * 100) . "%\n\n";

    print "Response Times:\n";
    print "  Average: " . sprintf("%.3f", $m->{avg_response_time}) . "s\n";
    print "  P95: " . sprintf("%.3f", $m->{p95_response_time}) . "s\n";
    print "  P99: " . sprintf("%.3f", $m->{p99_response_time}) . "s\n\n";

    print "Throughput:\n";
    print "  Requests/sec: " . sprintf("%.1f", $m->{requests_per_second}) . "\n";
    print "  Uptime: " . sprintf("%.1f", $m->{uptime_seconds}) . "s\n\n";

    my $modules = $p->{module_performance}->{top_modules};
    if (@$modules) {
        print "Top Modules by Activity:\n";
        for my $mod (@$modules) {
            printf "  %s: %d calls, %.2fms avg, %.1f%% errors\n",
                   $mod->{module_function}, $mod->{requests},
                   $mod->{avg_time_ms}, $mod->{error_rate};
        }
        print "\n";
    }

    my $health = $p->{health_indicators};
    if (@{$health->{concerns}}) {
        print "⚠️ Performance Concerns:\n";
        for (@{$health->{concerns}}) { print "  • $_\n"; }
        print "\n";
    }

    if (@{$health->{recommendations}}) {
        print "💡 Recommendations:\n";
        for (@{$health->{recommendations}}) { print "  • $_\n"; }
    }
}'
```

### Performance Benchmarking

```bash
# Quick performance test
cat > performance_test.sh << 'EOF'
#!/bin/bash
echo "🏃 Running performance test..."

START_TIME=$(date +%s.%N)

# Run 50 test requests
for i in {1..50}; do
    perl -e 'use lib "."; use CPANBridge; my $bridge = CPANBridge->new(); $CPANBridge::DAEMON_MODE = 1; $bridge->call_python("test", "ping", {test_id => '$i'});' >/dev/null 2>&1
done

END_TIME=$(date +%s.%N)
DURATION=$(echo "$END_TIME - $START_TIME" | bc)
RPS=$(echo "scale=2; 50 / $DURATION" | bc)

echo "✅ Completed 50 requests in ${DURATION}s"
echo "📊 Performance: ${RPS} requests/second"

# Get performance metrics
perl -e '
use lib "."; use CPANBridge;
my $bridge = CPANBridge->new();
$CPANBridge::DAEMON_MODE = 1;
my $r = $bridge->call_python("system", "performance", {});
if ($r->{success}) {
    my $m = $r->{result}->{performance_metrics};
    printf "📈 Current avg response: %.3fs\n", $m->{avg_response_time};
    printf "📈 Current P95 response: %.3fs\n", $m->{p95_response_time};
}'
EOF

chmod +x performance_test.sh
```

---

## 🔧 Troubleshooting Guide

### Common Issues and Solutions

#### 1. High CPU Usage (>95%)

**Symptoms:**
- Health check shows "unhealthy"
- Slow response times
- High CPU percentage in metrics

**Investigation:**
```bash
# Check CPU usage
perl -e 'use lib "."; use CPANBridge; my $bridge = CPANBridge->new(); $CPANBridge::DAEMON_MODE = 1; my $r = $bridge->call_python("system", "metrics", {}); printf "CPU: %.1f%%\n", $r->{result}->{resource_status}->{cpu_percent};'

# Check for high-frequency requests
tail -100 /tmp/cpan_daemon.log | grep -c "Handling client"
```

**Solutions:**
```bash
# 1. Check for connection leaks
perl -e 'use lib "."; use CPANBridge; my $bridge = CPANBridge->new(); $CPANBridge::DAEMON_MODE = 1; my $r = $bridge->call_python("system", "connections", {}); print "Active: " . $r->{result}->{active_connections} . ", Stale: " . $r->{result}->{stale_connections} . "\n";'

# 2. Force cleanup
perl -e 'use lib "."; use CPANBridge; my $bridge = CPANBridge->new(); $CPANBridge::DAEMON_MODE = 1; $bridge->call_python("system", "cleanup", {});'

# 3. Restart daemon if needed
pkill -f cpan_daemon.py && sleep 2 && python python_helpers/cpan_daemon.py &
```

#### 2. High Memory Usage (>500MB)

**Symptoms:**
- Memory warnings in health check
- Increasing memory usage over time

**Investigation:**
```bash
# Check memory trends
perl -e 'use lib "."; use CPANBridge; my $bridge = CPANBridge->new(); $CPANBridge::DAEMON_MODE = 1; my $r = $bridge->call_python("system", "metrics", {}); printf "Memory: %.1fMB\n", $r->{result}->{resource_status}->{memory_mb};'

# Check for memory leaks
ps aux | grep cpan_daemon | awk '{print $6/1024 " MB"}'
```

**Solutions:**
```bash
# 1. Clean up connections
perl -e 'use lib "."; use CPANBridge; my $bridge = CPANBridge->new(); $CPANBridge::DAEMON_MODE = 1; $bridge->call_python("system", "cleanup", {});'

# 2. Restart daemon
pkill -f cpan_daemon.py && sleep 2 && python python_helpers/cpan_daemon.py &
```

#### 3. High Error Rate (>5%)

**Symptoms:**
- Performance degraded status
- Increased failed requests

**Investigation:**
```bash
# Check recent errors
perl -e 'use lib "."; use CPANBridge; my $bridge = CPANBridge->new(); $CPANBridge::DAEMON_MODE = 1; my $r = $bridge->call_python("system", "performance", {}); my $errors = $r->{result}->{recent_errors}; for (@$errors) { print "$_->{module_function}: $_->{error}\n"; }'

# Check daemon logs
tail -50 /tmp/cpan_daemon.log | grep -i error
```

**Solutions:**
- Check helper module dependencies
- Verify database connections
- Check network connectivity for external services

#### 4. Daemon Not Responding

**Symptoms:**
- Health check fails
- Connection refused errors

**Investigation:**
```bash
# Check if daemon is running
ps aux | grep cpan_daemon | grep -v grep

# Check socket file
ls -la /tmp/cpan_bridge.sock

# Check recent logs
tail -20 /tmp/cpan_daemon.log
```

**Solutions:**
```bash
# Restart daemon
pkill -f cpan_daemon.py
sleep 2
python python_helpers/cpan_daemon.py &

# Verify startup
sleep 3
perl -e 'use lib "."; use CPANBridge; my $bridge = CPANBridge->new(); $CPANBridge::DAEMON_MODE = 1; my $r = $bridge->call_python("test", "ping", {}); print ($r->{success} ? "✅ Working" : "❌ Failed") . "\n";'
```

#### 5. Security Events

**Symptoms:**
- Security alerts in logs
- Increased rejected requests

**Investigation:**
```bash
# Check security events
tail -20 /tmp/cpan_security.log

# Check security metrics
perl -e 'use lib "."; use CPANBridge; my $bridge = CPANBridge->new(); $CPANBridge::DAEMON_MODE = 1; my $r = $bridge->call_python("system", "metrics", {}); my $sec = $r->{result}->{security_summary}; print "Events: $sec->{total_security_events}, Rejected: $sec->{requests_rejected}\n";'
```

**Solutions:**
- Review security logs for attack patterns
- Update validation rules if false positives
- Consider IP blocking for persistent attackers

---

## 🔧 Maintenance Tasks

### Daily Maintenance (Automated)

```bash
# Create daily maintenance script
cat > daily_maintenance.sh << 'EOF'
#!/bin/bash
echo "🔧 Daily CPAN Bridge Maintenance - $(date)"

# 1. Clean up stale connections
echo "Cleaning stale connections..."
CLEANUP=$(perl -e 'use lib "."; use CPANBridge; my $bridge = CPANBridge->new(); $CPANBridge::DAEMON_MODE = 1; my $r = $bridge->call_python("system", "cleanup", {}); print $r->{result}->{cleaned_connections};')
echo "Cleaned $CLEANUP stale connections"

# 2. Check health status
echo "Checking health..."
HEALTH=$(perl -e 'use lib "."; use CPANBridge; my $bridge = CPANBridge->new(); $CPANBridge::DAEMON_MODE = 1; my $r = $bridge->call_python("system", "health", {}); print $r->{result}->{overall_status};')
echo "Health status: $HEALTH"

# 3. Check for log rotation needs
LOG_SIZE=$(du -m /tmp/cpan_daemon.log 2>/dev/null | cut -f1)
if [ "${LOG_SIZE:-0}" -gt 100 ]; then
    echo "Log file is ${LOG_SIZE}MB, consider rotation"
fi

# 4. Performance summary
perl -e 'use lib "."; use CPANBridge; my $bridge = CPANBridge->new(); $CPANBridge::DAEMON_MODE = 1; my $r = $bridge->call_python("system", "metrics", {}); my $m = $r->{result}; printf "Performance: %d requests, %.1f%% errors, %.3fs avg response\n", $m->{performance_metrics}->{total_requests}, $m->{performance_metrics}->{error_rate} * 100, $m->{performance_metrics}->{avg_response_time};'

echo "✅ Daily maintenance complete"
EOF

chmod +x daily_maintenance.sh

# Schedule in crontab
# 0 6 * * * /path/to/daily_maintenance.sh >> /tmp/cpan_maintenance.log 2>&1
```

### Weekly Maintenance

```bash
# Create weekly maintenance script
cat > weekly_maintenance.sh << 'EOF'
#!/bin/bash
echo "🔧 Weekly CPAN Bridge Maintenance - $(date)"

# 1. Performance analysis
echo "Generating performance report..."
perl -e 'use lib "."; use CPANBridge; my $bridge = CPANBridge->new(); $CPANBridge::DAEMON_MODE = 1; my $r = $bridge->call_python("system", "performance", {}); my $p = $r->{result}; print "Total requests this week: " . $p->{performance_metrics}->{total_requests} . "\n"; print "Average response time: " . sprintf("%.3f", $p->{performance_metrics}->{avg_response_time}) . "s\n"; if (@{$p->{health_indicators}->{recommendations}}) { print "Recommendations:\n"; for (@{$p->{health_indicators}->{recommendations}}) { print "  • $_\n"; } }'

# 2. Security review
echo "Security events summary..."
SECURITY_EVENTS=$(tail -1000 /tmp/cpan_security.log 2>/dev/null | wc -l)
echo "Security events this week: $SECURITY_EVENTS"

# 3. Resource usage trends
echo "Resource usage analysis..."
perl -e 'use lib "."; use CPANBridge; my $bridge = CPANBridge->new(); $CPANBridge::DAEMON_MODE = 1; my $r = $bridge->call_python("system", "metrics", {}); my $res = $r->{result}->{resource_status}; printf "Current resource usage: %.1fMB RAM, %.1f%% CPU\n", $res->{memory_mb}, $res->{cpu_percent};'

# 4. Log rotation
if [ -f /tmp/cpan_daemon.log ]; then
    cp /tmp/cpan_daemon.log "/tmp/cpan_daemon_$(date +%Y%m%d).log"
    > /tmp/cpan_daemon.log
    echo "Daemon log rotated"
fi

if [ -f /tmp/cpan_security.log ]; then
    cp /tmp/cpan_security.log "/tmp/cpan_security_$(date +%Y%m%d).log"
    > /tmp/cpan_security.log
    echo "Security log rotated"
fi

echo "✅ Weekly maintenance complete"
EOF

chmod +x weekly_maintenance.sh
```

---

## 🚨 Alert Thresholds

### Critical Alerts (Immediate Action)

| Metric | Threshold | Command to Check |
|--------|-----------|------------------|
| CPU Usage | >95% | `perl -e 'use lib "."; use CPANBridge; my $bridge = CPANBridge->new(); $CPANBridge::DAEMON_MODE = 1; my $r = $bridge->call_python("system", "metrics", {}); print $r->{result}->{resource_status}->{cpu_percent};'` |
| Memory Usage | >1000MB | `perl -e 'use lib "."; use CPANBridge; my $bridge = CPANBridge->new(); $CPANBridge::DAEMON_MODE = 1; my $r = $bridge->call_python("system", "metrics", {}); print $r->{result}->{resource_status}->{memory_mb};'` |
| Error Rate | >10% | `perl -e 'use lib "."; use CPANBridge; my $bridge = CPANBridge->new(); $CPANBridge::DAEMON_MODE = 1; my $r = $bridge->call_python("system", "performance", {}); printf "%.1f", $r->{result}->{performance_metrics}->{error_rate} * 100;'` |
| Daemon Down | Health check fails | `./health_check.sh; echo $?` |

### Warning Alerts (Monitor Closely)

| Metric | Threshold | Command to Check |
|--------|-----------|------------------|
| CPU Usage | >80% | Same as above |
| Memory Usage | >500MB | Same as above |
| Error Rate | >5% | Same as above |
| Response Time | >1s | `perl -e 'use lib "."; use CPANBridge; my $bridge = CPANBridge->new(); $CPANBridge::DAEMON_MODE = 1; my $r = $bridge->call_python("system", "performance", {}); printf "%.3f", $r->{result}->{performance_metrics}->{avg_response_time};'` |
| Stale Connections | >5 | `perl -e 'use lib "."; use CPANBridge; my $bridge = CPANBridge->new(); $CPANBridge::DAEMON_MODE = 1; my $r = $bridge->call_python("system", "connections", {}); print $r->{result}->{stale_connections};'` |

### Monitoring Script for Alerts

```bash
cat > monitoring_alerts.sh << 'EOF'
#!/bin/bash

ALERT_LOG="/tmp/cpan_alerts.log"

log_alert() {
    echo "$(date): $1" | tee -a "$ALERT_LOG"
}

# Check CPU
CPU=$(perl -e 'use lib "."; use CPANBridge; my $bridge = CPANBridge->new(); $CPANBridge::DAEMON_MODE = 1; my $r = $bridge->call_python("system", "metrics", {}); print $r->{result}->{resource_status}->{cpu_percent};' 2>/dev/null)
if (( $(echo "$CPU > 95" | bc -l) )); then
    log_alert "CRITICAL: CPU usage ${CPU}% exceeds 95%"
elif (( $(echo "$CPU > 80" | bc -l) )); then
    log_alert "WARNING: CPU usage ${CPU}% exceeds 80%"
fi

# Check Memory
MEMORY=$(perl -e 'use lib "."; use CPANBridge; my $bridge = CPANBridge->new(); $CPANBridge::DAEMON_MODE = 1; my $r = $bridge->call_python("system", "metrics", {}); print $r->{result}->{resource_status}->{memory_mb};' 2>/dev/null)
if (( $(echo "$MEMORY > 1000" | bc -l) )); then
    log_alert "CRITICAL: Memory usage ${MEMORY}MB exceeds 1000MB"
elif (( $(echo "$MEMORY > 500" | bc -l) )); then
    log_alert "WARNING: Memory usage ${MEMORY}MB exceeds 500MB"
fi

# Check Error Rate
ERROR_RATE=$(perl -e 'use lib "."; use CPANBridge; my $bridge = CPANBridge->new(); $CPANBridge::DAEMON_MODE = 1; my $r = $bridge->call_python("system", "performance", {}); printf "%.1f", $r->{result}->{performance_metrics}->{error_rate} * 100;' 2>/dev/null)
if (( $(echo "$ERROR_RATE > 10" | bc -l) )); then
    log_alert "CRITICAL: Error rate ${ERROR_RATE}% exceeds 10%"
elif (( $(echo "$ERROR_RATE > 5" | bc -l) )); then
    log_alert "WARNING: Error rate ${ERROR_RATE}% exceeds 5%"
fi

# Check Health
if ! ./health_check.sh >/dev/null 2>&1; then
    log_alert "CRITICAL: Daemon health check failed"
fi
EOF

chmod +x monitoring_alerts.sh

# Run every minute via cron
# * * * * * /path/to/monitoring_alerts.sh
```

---

## 🆘 Emergency Procedures

### Emergency Restart

```bash
# Emergency restart procedure
echo "🚨 Emergency restart initiated..."

# 1. Stop daemon
pkill -f cpan_daemon.py
sleep 5

# 2. Clean up socket
rm -f /tmp/cpan_bridge.sock

# 3. Start daemon
python python_helpers/cpan_daemon.py &
sleep 3

# 4. Verify operation
if perl -e 'use lib "."; use CPANBridge; my $bridge = CPANBridge->new(); $CPANBridge::DAEMON_MODE = 1; my $r = $bridge->call_python("test", "ping", {}); exit($r->{success} ? 0 : 1);'; then
    echo "✅ Emergency restart successful"
else
    echo "❌ Emergency restart failed"
fi
```

### Fallback to Process Mode

```bash
# If daemon fails, temporarily disable daemon mode
export CPAN_BRIDGE_DAEMON=0

# Test fallback
perl -e 'use lib "."; use CPANBridge; my $bridge = CPANBridge->new(); $CPANBridge::DAEMON_MODE = 0; my $r = $bridge->call_python("test", "ping", {}); print ($r->{success} ? "✅ Fallback working" : "❌ Fallback failed") . "\n";'
```

### Emergency Contacts and Escalation

```bash
# Create incident report
cat > create_incident.sh << 'EOF'
#!/bin/bash
INCIDENT_FILE="/tmp/cpan_incident_$(date +%Y%m%d_%H%M%S).txt"

echo "CPAN Bridge Daemon Incident Report" > "$INCIDENT_FILE"
echo "Generated: $(date)" >> "$INCIDENT_FILE"
echo "=================================" >> "$INCIDENT_FILE"
echo "" >> "$INCIDENT_FILE"

# System status
echo "SYSTEM STATUS:" >> "$INCIDENT_FILE"
ps aux | grep cpan_daemon | grep -v grep >> "$INCIDENT_FILE" || echo "Daemon not running" >> "$INCIDENT_FILE"
echo "" >> "$INCIDENT_FILE"

# Recent logs
echo "RECENT LOGS (last 50 lines):" >> "$INCIDENT_FILE"
tail -50 /tmp/cpan_daemon.log >> "$INCIDENT_FILE" 2>/dev/null || echo "No daemon logs available" >> "$INCIDENT_FILE"
echo "" >> "$INCIDENT_FILE"

# Health status
echo "HEALTH STATUS:" >> "$INCIDENT_FILE"
perl -e 'use lib "."; use CPANBridge; my $bridge = CPANBridge->new(); $CPANBridge::DAEMON_MODE = 1; my $r = $bridge->call_python("system", "health", {}); if ($r->{success}) { print "Status: " . $r->{result}->{overall_status} . "\n"; } else { print "Health check failed: " . $r->{error} . "\n"; }' >> "$INCIDENT_FILE" 2>&1

echo "Incident report created: $INCIDENT_FILE"
EOF

chmod +x create_incident.sh
```

---

## 📚 Quick Reference

### Essential One-Liners

```bash
# Status check
perl -e 'use lib "."; use CPANBridge; my $bridge = CPANBridge->new(); $CPANBridge::DAEMON_MODE = 1; my $r = $bridge->call_python("system", "metrics", {}); printf "Status: %s | CPU: %.1f%% | Memory: %.1fMB | Connections: %d\n", ($r->{success} ? "UP" : "DOWN"), $r->{result}->{resource_status}->{cpu_percent}, $r->{result}->{resource_status}->{memory_mb}, $r->{result}->{connection_summary}->{active_connections};'

# Performance summary
perl -e 'use lib "."; use CPANBridge; my $bridge = CPANBridge->new(); $CPANBridge::DAEMON_MODE = 1; my $r = $bridge->call_python("system", "performance", {}); printf "Performance: %d requests | %.3fs avg | %.1f%% errors\n", $r->{result}->{performance_metrics}->{total_requests}, $r->{result}->{performance_metrics}->{avg_response_time}, $r->{result}->{performance_metrics}->{error_rate} * 100;'

# Connection cleanup
perl -e 'use lib "."; use CPANBridge; my $bridge = CPANBridge->new(); $CPANBridge::DAEMON_MODE = 1; my $r = $bridge->call_python("system", "cleanup", {}); print "Cleaned: " . $r->{result}->{cleaned_connections} . "\n";'

# Security check
grep -c "SECURITY ALERT" /tmp/cpan_security.log 2>/dev/null || echo "0"

# Error count
tail -100 /tmp/cpan_daemon.log | grep -c ERROR
```

### Key Files Reference

```
📁 Daemon Files:
/tmp/cpan_daemon.log              # Main application logs
/tmp/cpan_security.log            # Security events
/tmp/cpan_bridge.sock             # Unix socket
python_helpers/cpan_daemon.py     # Main daemon script

📁 Monitoring Scripts:
health_check.sh                   # Health check with exit codes
daily_maintenance.sh              # Daily maintenance tasks
weekly_maintenance.sh             # Weekly maintenance tasks
monitoring_alerts.sh              # Alert monitoring
watch_dashboard.sh                # Live dashboard

📁 Log Files:
/tmp/cpan_daemon_YYYYMMDD.log     # Archived daemon logs
/tmp/cpan_security_YYYYMMDD.log   # Archived security logs
/tmp/cpan_alerts.log              # Alert history
/tmp/cpan_maintenance.log         # Maintenance history
```

---

## 📞 Support and Escalation

### Before Escalating

1. ✅ Run health check: `./health_check.sh`
2. ✅ Check recent logs: `tail -50 /tmp/cpan_daemon.log`
3. ✅ Try connection cleanup: `perl -e 'use lib "."; use CPANBridge; my $bridge = CPANBridge->new(); $CPANBridge::DAEMON_MODE = 1; $bridge->call_python("system", "cleanup", {});'`
4. ✅ Attempt restart: `pkill -f cpan_daemon.py && sleep 2 && python python_helpers/cpan_daemon.py &`
5. ✅ Generate incident report: `./create_incident.sh`

### Information to Collect

- Output of health check
- Recent daemon logs (last 100 lines)
- System resource usage
- Performance metrics
- Connection status
- Security events (if any)

---

*This operations guide provides comprehensive monitoring and maintenance procedures for the CPAN Bridge daemon in production environments. Keep this guide accessible to all operations team members.*

**Last Updated:** September 2025
**Version:** 1.0.0
**Status:** Production Ready ✅