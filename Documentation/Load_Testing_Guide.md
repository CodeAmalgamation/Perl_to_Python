# CPAN Bridge Daemon - Load Testing Guide

**Purpose**: Verify throttling behavior and stress-test the daemon under high load
**Created**: 2025-10-10
**Throttling Limits**: 100 concurrent, 2000 req/min

---

## Quick Start

### Prerequisites

1. **Ensure daemon is running**:
   ```bash
   cd /Users/shubhamdixit/Perl_to_Python/python_helpers
   python3 cpan_daemon.py &
   ```

2. **Verify daemon is responding**:
   ```bash
   cd /Users/shubhamdixit/Perl_to_Python
   perl -e 'use CPANBridge; my $b = CPANBridge->new(); print "OK\n" if $b->test_python_bridge();'
   ```

### Run Quick Test (1 minute)

```bash
cd /Users/shubhamdixit/Perl_to_Python/Test_Scripts
perl quick_load_test.pl
```

**What it tests**:
- Baseline: 20 concurrent threads (15s)
- Warning: 80 concurrent threads (15s) - at 80% threshold
- Over limit: 120 concurrent threads (15s) - should trigger throttling
- Recovery: 10 concurrent threads (10s) - verify recovery

**Expected duration**: ~1 minute

### Run Full Load Test (8-10 minutes)

```bash
cd /Users/shubhamdixit/Perl_to_Python/Test_Scripts
perl load_test_throttling.pl
```

**What it tests**:
- Phase 1: Baseline (10 concurrent, 30s)
- Phase 2: Moderate load (50 concurrent, 30s)
- Phase 3: Warning threshold (80 concurrent, 30s)
- Phase 4: At limit (100 concurrent, 30s)
- Phase 5: Over limit (150 concurrent, 30s) - **throttling expected**
- Phase 6: Rate limit test (2000 req/min, 60s)
- Phase 7: Rate burst (3000 req/min, 60s) - **rate limiting expected**
- Phase 8: Memory pressure (large payloads, 30s)
- Phase 9: Recovery (10 concurrent, 20s)

**Expected duration**: ~8-10 minutes

---

## Test Scenarios

### Scenario 1: Verify Baseline Performance

**Goal**: Establish baseline metrics under normal load

```bash
# 10 concurrent threads for 30 seconds
perl quick_load_test.pl
```

**Expected Results**:
- 0% throttling
- No resource warnings
- Consistent response times
- ~200-500 req/sec throughput

**Key Metrics**:
```
Success: 100%
Memory: < 200 MB
CPU: < 50%
Concurrent: ~10
Rate: ~300-600/min
```

---

### Scenario 2: Test Warning Threshold

**Goal**: Trigger warning logs but no throttling

```bash
# Manually trigger 80 concurrent
cd Test_Scripts
perl -e '
use lib "..";
use CPANBridge;
use threads;
my @t;
for (1..80) {
    push @t, threads->create(sub {
        my $b = CPANBridge->new();
        for (1..100) {
            $b->call_python("test", "ping", {});
            select(undef,undef,undef,0.1);
        }
    });
}
$_->join() for @t;
'
```

**Expected Results**:
- 0-5% throttling
- Warning logs: "approaching limit 100"
- Mostly successful requests

**Daemon Logs** (check `/tmp/cpan_daemon.log`):
```
[WARNING] Resource warning: ['Concurrent requests 82 approaching limit 100']
```

---

### Scenario 3: Trigger Concurrent Request Throttling

**Goal**: Exceed concurrent limit and observe backpressure

```bash
# 150 concurrent threads (50% over limit)
cd Test_Scripts
perl load_test_throttling.pl
# OR manually:
perl -e '
use lib "..";
use CPANBridge;
use threads;
my @t;
for (1..150) {
    push @t, threads->create(sub {
        my $b = CPANBridge->new();
        for (1..50) {
            $b->call_python("test", "ping", {});
            select(undef,undef,undef,0.05);
        }
    });
}
$_->join() for @t;
'
```

**Expected Results**:
- 20-40% throttling rate
- Violation logs in daemon
- 1-second backpressure delays
- Some connection timeouts

**Daemon Logs**:
```
[CRITICAL] RESOURCE VIOLATION: ['Concurrent requests 152 exceeds limit 100']
[WARNING] Resource violations detected, throttling connections
```

---

### Scenario 4: Trigger Request Rate Limiting

**Goal**: Exceed 2000 req/min and observe rate limiting

```bash
# Send 3000 requests in 60 seconds
cd Test_Scripts
perl -e '
use lib "..";
use CPANBridge;
use Time::HiRes qw(time sleep);
my $b = CPANBridge->new();
my $start = time();
for (1..3000) {
    $b->call_python("test", "ping", {});
    sleep(0.02);  # 50 req/sec = 3000/min
    print "Request $_/3000\r" if $_ % 100 == 0;
}
my $elapsed = time() - $start;
print "\nSent 3000 requests in $elapsed seconds\n";
'
```

**Expected Results**:
- Rate limit warnings after ~60 seconds
- Sliding window enforcement
- Some requests delayed

**Daemon Logs**:
```
[CRITICAL] RESOURCE VIOLATION: ['Request rate 2134/min exceeds limit 2000/min']
```

---

### Scenario 5: Memory Pressure Test

**Goal**: Test daemon behavior under memory pressure

```bash
# Send large payloads (1MB each)
cd Test_Scripts
perl -e '
use lib "..";
use CPANBridge;
my $b = CPANBridge->new();
for (1..50) {
    my $large_data = "X" x (1024 * 1024);  # 1MB
    $b->call_python("test", "ping", { data => $large_data });
    print "Request $_ (1MB payload)\n";
    sleep(1);
}
'
```

**Expected Results**:
- Memory usage increases
- No memory limit violations (if < 1GB)
- Proper cleanup after requests

**Monitor**:
```bash
# In another terminal
watch -n 1 'ps aux | grep cpan_daemon'
```

---

## Monitoring During Tests

### Real-Time Metrics (Option 1: Daemon Metrics)

```bash
# In separate terminal, run continuous monitoring
cd /Users/shubhamdixit/Perl_to_Python
while true; do
    perl -e '
    use lib ".";
    use CPANBridge;
    my $b = CPANBridge->new();
    my $r = $b->call_python("system", "metrics", {});
    if ($r->{success}) {
        my $res = $r->{result}->{resource_status};
        printf "\r[%s] Mem: %.1fMB CPU: %.1f%% Concurrent: %d Rate: %d/min",
            scalar(localtime()),
            $res->{memory_mb}, $res->{cpu_percent},
            $res->{concurrent_requests}, $res->{requests_per_minute};
    }
    ' 2>/dev/null
    sleep 1
done
```

### Real-Time Metrics (Option 2: System Tools)

```bash
# Monitor daemon process
watch -n 1 'ps aux | grep cpan_daemon | grep -v grep'

# Monitor daemon logs
tail -f /tmp/cpan_daemon.log | grep -E "VIOLATION|WARNING|throttling"
```

### Real-Time Metrics (Option 3: Glances)

```bash
# If glances is installed
glances -t 0.5 --process-filter python
```

---

## Expected Behavior

### Under Normal Load (< 50 concurrent, < 1000/min)

✅ **Success rate**: 99-100%
✅ **Warnings**: None
✅ **Violations**: None
✅ **Latency**: < 50ms average
✅ **Memory**: Stable, < 300 MB
✅ **CPU**: < 50%

### At Warning Threshold (80 concurrent, 1600/min)

⚠️ **Success rate**: 95-100%
⚠️ **Warnings**: "Approaching limit" logs
✅ **Violations**: None
✅ **Latency**: 50-100ms average
✅ **Memory**: Stable
✅ **CPU**: 50-100%

### At Violation Threshold (100+ concurrent, 2000+ /min)

🚨 **Success rate**: 70-90%
🚨 **Warnings**: Multiple
🚨 **Violations**: Active
🚨 **Throttling**: 1-second backpressure
🚨 **Latency**: 100-1000ms (includes throttle delays)
✅ **Memory**: Stable (throttling prevents runaway)
✅ **CPU**: Capped by throttling

### Recovery After Throttling

✅ **Success rate**: Returns to 99-100% quickly
✅ **Warnings**: Clear within 60 seconds
✅ **Violations**: Clear immediately
✅ **Latency**: Returns to baseline
✅ **Memory**: May stay elevated briefly, then GC
✅ **CPU**: Returns to normal

---

## Interpreting Results

### Success Rate

| Rate | Meaning | Action |
|------|---------|--------|
| **99-100%** | Normal operation | None |
| **90-99%** | Warning threshold | Monitor logs |
| **70-90%** | Throttling active | Expected under overload |
| **< 70%** | Problem detected | Check daemon health |

### Throttling Rate

| Rate | Meaning |
|------|---------|
| **0%** | No throttling (within limits) |
| **1-10%** | Occasional burst throttling |
| **10-30%** | Active throttling (over limits) |
| **> 30%** | Heavy throttling (significantly over limits) |

### Daemon Logs

**Normal operation**:
```
[INFO] Health check - Uptime: 3600s, Requests: 12456, Errors: 12
[INFO] Resource summary - Memory: 256.3MB, CPU: 45.2%, Concurrent: 12, Requests/min: 456
```

**Warning state**:
```
[WARNING] Resource warning: ['Concurrent requests 82 approaching limit 100']
[WARNING] Resource warning: ['Request rate 1834/min approaching limit 2000/min']
```

**Violation state**:
```
[CRITICAL] RESOURCE VIOLATION: ['Concurrent requests 152 exceeds limit 100']
[WARNING] Resource violations detected, throttling connections
[WARNING] Connection limit reached (100), rejecting new connections
```

---

## Tuning After Testing

### If Tests Show Headroom

If daemon handles load easily with resources to spare:

```bash
# Increase limits (requires daemon restart)
export CPAN_BRIDGE_MAX_CONCURRENT_REQUESTS=200
export CPAN_BRIDGE_MAX_REQUESTS_PER_MINUTE=4000
export CPAN_BRIDGE_MAX_MEMORY_MB=2048

# Restart daemon
pkill -f cpan_daemon.py
python3 cpan_daemon.py &
```

### If Tests Show Strain

If daemon struggles or crashes:

```bash
# Decrease limits (requires daemon restart)
export CPAN_BRIDGE_MAX_CONCURRENT_REQUESTS=50
export CPAN_BRIDGE_MAX_REQUESTS_PER_MINUTE=1000

# Restart daemon
pkill -f cpan_daemon.py
python3 cpan_daemon.py &
```

---

## Troubleshooting

### Daemon Crashes During Test

**Symptoms**: Connection refused, daemon not running

**Check**:
```bash
# Check if daemon is running
ps aux | grep cpan_daemon

# Check daemon logs
tail -100 /tmp/cpan_daemon.log

# Check system resources
free -h
top
```

**Common Causes**:
1. Out of memory (increase system RAM or decrease MAX_MEMORY_MB)
2. Too many open files (increase ulimit -n)
3. Port already in use (check socket file)

**Recovery**:
```bash
# Kill any stuck processes
pkill -9 -f cpan_daemon.py

# Remove socket file
rm -f /tmp/cpan_bridge.sock

# Restart with debug logging
CPAN_BRIDGE_DEBUG=1 python3 cpan_daemon.py
```

### Test Hangs or Slow

**Symptoms**: Test takes much longer than expected

**Possible causes**:
1. Daemon is throttling heavily (expected if over limits)
2. Network/socket issues
3. Python interpreter overloaded

**Check**:
```bash
# Check daemon CPU usage
ps aux | grep cpan_daemon

# Check for socket errors
netstat -an | grep cpan_bridge

# Check daemon logs for throttling
grep -i "throttling\|violation" /tmp/cpan_daemon.log
```

### Inconsistent Results

**Symptoms**: Results vary significantly between runs

**Possible causes**:
1. Daemon state not reset between tests
2. Background processes interfering
3. Memory/CPU pressure from other applications

**Solution**:
```bash
# Restart daemon between tests
pkill -f cpan_daemon.py
sleep 2
python3 cpan_daemon.py &
sleep 5

# Run test
perl load_test_throttling.pl
```

---

## Best Practices

1. **Always restart daemon** between major test runs
2. **Monitor daemon logs** in separate terminal during tests
3. **Run quick test first** before full load test
4. **Check system resources** (free memory, CPU) before testing
5. **Allow recovery time** (30-60s) between test phases
6. **Document results** for capacity planning
7. **Test incrementally** - don't jump straight to maximum load

---

## Example Test Session

```bash
# Terminal 1: Start daemon with debug
cd /Users/shubhamdixit/Perl_to_Python/python_helpers
CPAN_BRIDGE_DEBUG=1 python3 cpan_daemon.py

# Terminal 2: Monitor logs
tail -f /tmp/cpan_daemon.log

# Terminal 3: Run load test
cd /Users/shubhamdixit/Perl_to_Python/Test_Scripts
perl quick_load_test.pl

# After quick test completes, run full test
perl load_test_throttling.pl

# When done, analyze logs
grep -c "VIOLATION" /tmp/cpan_daemon.log
grep -c "WARNING" /tmp/cpan_daemon.log
```

---

## Summary

The load tests verify that the CPAN Bridge daemon:

✅ Handles baseline load efficiently
✅ Warns appropriately at 80% thresholds
✅ Throttles correctly when limits exceeded
✅ Recovers gracefully after throttling
✅ Maintains stability under extreme load
✅ Prevents resource exhaustion

**Current limits (2025-10-10)**:
- MAX_CONCURRENT_REQUESTS: 100
- MAX_REQUESTS_PER_MINUTE: 2000
- MAX_MEMORY_MB: 1024
- MAX_CPU_PERCENT: 200

These can be tuned based on load test results and production requirements.
