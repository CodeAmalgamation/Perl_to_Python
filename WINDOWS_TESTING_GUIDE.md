# CPAN Daemon Testing Guide for Windows

This guide provides detailed step-by-step testing procedures for the CPAN Bridge daemon on Windows systems.

## Quick Windows Testing Commands

For easier copy-paste testing, here are simplified PowerShell alternatives to the complex Perl one-liners:

### Quick Health Check (PowerShell)
```powershell
# Read socket info and test health endpoint
$socket = Get-Content cpan_bridge_socket.txt
$host, $port = $socket -split ':'
$tcp = New-Object System.Net.Sockets.TcpClient
$tcp.Connect($host, $port)
$stream = $tcp.GetStream()
$writer = New-Object System.IO.StreamWriter($stream)
$reader = New-Object System.IO.StreamReader($stream)
$writer.WriteLine('{"action":"health_check","request_id":"test"}')
$writer.Flush()
$response = $reader.ReadLine()
Write-Host "Health Response: $response"
$tcp.Close()
```

### Quick Basic Test (PowerShell)
```powershell
# Simple connection test
$socket = Get-Content cpan_bridge_socket.txt
$host, $port = $socket -split ':'
try {
    $tcp = New-Object System.Net.Sockets.TcpClient
    $tcp.Connect($host, $port)
    Write-Host "✅ Connection successful to $socket"
    $tcp.Close()
} catch {
    Write-Host "❌ Connection failed: $($_.Exception.Message)"
}
```

## Pre-Testing Setup

### 1. Check Python Environment
```cmd
cd C:\Users\sxdixit\ds\Perl_to_Python-architecture-revamp
python --version
pip list | findstr psutil
```

### 2. Verify File Permissions
```cmd
dir python_helpers\cpan_daemon.py
```

## Phase 1: Basic Daemon Operations

### Step 1: Start the Daemon
```cmd
REM Terminal 1 - Start daemon with debug logging
cd C:\Users\sxdixit\ds\Perl_to_Python-architecture-revamp
set CPAN_BRIDGE_DEBUG=1
python python_helpers\cpan_daemon.py
```

**Expected Output:**
- `Starting CPAN Bridge Daemon v1.0.0`
- `TCP socket created at 127.0.0.1:XXXXX` (random port)
- `All helper modules loaded successfully`

### Step 2: Verify Socket Info File
```cmd
REM Terminal 2 - Check socket info file exists
dir cpan_bridge_socket.txt
type cpan_bridge_socket.txt
REM Should show: 127.0.0.1:XXXXX
```

### Step 3: Test Basic Connectivity
```cmd
REM Terminal 2 - Test basic connection (Method 1: Using file read)
perl -e "use IO::Socket::INET; open my $fh, '<', 'cpan_bridge_socket.txt' or die $!; my $sock_info = <$fh>; close $fh; chomp $sock_info; my ($host, $port) = split ':', $sock_info; my $sock = IO::Socket::INET->new(PeerAddr => $host, PeerPort => $port, Proto => 'tcp'); if ($sock) { print \"Connection successful\n\"; close $sock; } else { print \"Connection failed: $!\n\"; }"
```

**Alternative Method 2 (PowerShell):**
```powershell
REM If Perl command fails, try PowerShell version:
powershell -Command "$socket = Get-Content cpan_bridge_socket.txt; $host, $port = $socket -split ':'; try { $tcp = New-Object System.Net.Sockets.TcpClient; $tcp.Connect($host, $port); Write-Host 'Connection successful'; $tcp.Close() } catch { Write-Host 'Connection failed:' $_.Exception.Message }"
```

## Phase 2: Health and Status Testing

### Step 4: Test Health Endpoint
```cmd
REM Terminal 2 - Health check
perl -e "use IO::Socket::INET; use JSON::PP::PP; open my $fh, '<', 'cpan_bridge_socket.txt'; my $socket_path = <$fh>; chomp $socket_path; close $fh; my ($host, $port) = split ':', $socket_path; my $sock = IO::Socket::INET->new(PeerAddr => $host, PeerPort => $port, Proto => 'tcp') or die \"Cannot connect: $!\"; my $request = encode_json({action => 'health_check', request_id => 'test_' . time()}); print $sock $request . \"\n\"; my $response = <$sock>; print \"Health Response: $response\"; close $sock;"
```

**Expected Response:**
```json
{"status": "healthy", "uptime": "X seconds", "connections": 0, "memory_usage": "X MB"}
```

### Step 5: Test System Info
```cmd
REM Terminal 2 - System info
perl -e "use IO::Socket::INET; use JSON::PP::PP; open my $fh, '<', 'cpan_bridge_socket.txt'; my $socket_path = <$fh>; chomp $socket_path; close $fh; my ($host, $port) = split ':', $socket_path; my $sock = IO::Socket::INET->new(PeerAddr => $host, PeerPort => $port, Proto => 'tcp') or die \"Cannot connect: $!\"; my $request = encode_json({action => 'system_info', request_id => 'sysinfo_' . time()}); print $sock $request . \"\n\"; my $response = <$sock>; print \"System Info: $response\"; close $sock;"
```

## Phase 3: Core Module Testing

### Step 6: Test File Operations
```cmd
REM Create test file first
echo test content for daemon > C:\temp\test_daemon_file.txt

REM Terminal 2 - Test file_helper
perl -e "use IO::Socket::INET; use JSON::PP; open my $fh, '<', 'cpan_bridge_socket.txt'; my $socket_path = <$fh>; chomp $socket_path; close $fh; my ($host, $port) = split ':', $socket_path; my $sock = IO::Socket::INET->new(PeerAddr => $host, PeerPort => $port, Proto => 'tcp') or die \"Cannot connect: $!\"; my $request = encode_json({action => 'call_module', module => 'file_helper', function => 'read_file', args => ['C:/temp/test_daemon_file.txt'], request_id => 'file_' . time()}); print $sock $request . \"\n\"; my $response = <$sock>; print \"File Read Response: $response\"; close $sock;"
```

### Step 7: Test Database Operations
```cmd
REM Terminal 2 - Test db_helper
perl -e "use IO::Socket::INET; use JSON::PP; open my $fh, '<', 'cpan_bridge_socket.txt'; my $socket_path = <$fh>; chomp $socket_path; close $fh; my ($host, $port) = split ':', $socket_path; my $sock = IO::Socket::INET->new(PeerAddr => $host, PeerPort => $port, Proto => 'tcp') or die \"Cannot connect: $!\"; my $request = encode_json({action => 'call_module', module => 'db_helper', function => 'test_connection', args => [], request_id => 'db_' . time()}); print $sock $request . \"\n\"; my $response = <$sock>; print \"DB Test Response: $response\"; close $sock;"
```

### Step 8: Test JSON Operations
```cmd
REM Terminal 2 - Test json_helper
perl -e "use IO::Socket::INET; use JSON::PP; open my $fh, '<', 'cpan_bridge_socket.txt'; my $socket_path = <$fh>; chomp $socket_path; close $fh; my ($host, $port) = split ':', $socket_path; my $sock = IO::Socket::INET->new(PeerAddr => $host, PeerPort => $port, Proto => 'tcp') or die \"Cannot connect: $!\"; my $request = encode_json({action => 'call_module', module => 'json_helper', function => 'parse_json', args => ['{\"test\": \"data\", \"number\": 42}'], request_id => 'json_' . time()}); print $sock $request . \"\n\"; my $response = <$sock>; print \"JSON Parse Response: $response\"; close $sock;"
```

## Phase 4: Performance and Concurrent Testing

### Step 9: Concurrent Connection Test
```cmd
REM Terminal 2 - Run multiple connections simultaneously
for /L %%i in (1,1,5) do start /B perl -e "use IO::Socket::INET; use JSON::PP; open my $fh, '<', 'cpan_bridge_socket.txt'; my $socket_path = <$fh>; chomp $socket_path; close $fh; my ($host, $port) = split ':', $socket_path; my $sock = IO::Socket::INET->new(PeerAddr => $host, PeerPort => $port, Proto => 'tcp') or die \"Cannot connect: $!\"; my $request = encode_json({action => 'call_module', module => 'string_helper', function => 'trim', args => ['  test string %%i  '], request_id => 'concurrent_%%i' . time()}); print $sock $request . \"\n\"; my $response = <$sock>; print \"Worker %%i Response: $response\"; close $sock;"
```

### Step 10: Performance Monitoring
```cmd
REM Terminal 2 - Check performance stats
perl -e "use IO::Socket::INET; use JSON::PP; open my $fh, '<', 'cpan_bridge_socket.txt'; my $socket_path = <$fh>; chomp $socket_path; close $fh; my ($host, $port) = split ':', $socket_path; my $sock = IO::Socket::INET->new(PeerAddr => $host, PeerPort => $port, Proto => 'tcp') or die \"Cannot connect: $!\"; my $request = encode_json({action => 'performance_stats', request_id => 'perf_' . time()}); print $sock $request . \"\n\"; my $response = <$sock>; print \"Performance Stats: $response\"; close $sock;"
```

## Phase 5: Error Handling and Edge Cases

### Step 11: Test Invalid Requests
```cmd
REM Terminal 2 - Invalid module
perl -e "use IO::Socket::INET; use JSON::PP; open my $fh, '<', 'cpan_bridge_socket.txt'; my $socket_path = <$fh>; chomp $socket_path; close $fh; my ($host, $port) = split ':', $socket_path; my $sock = IO::Socket::INET->new(PeerAddr => $host, PeerPort => $port, Proto => 'tcp') or die \"Cannot connect: $!\"; my $request = encode_json({action => 'call_module', module => 'invalid_module', function => 'some_function', args => [], request_id => 'invalid_' . time()}); print $sock $request . \"\n\"; my $response = <$sock>; print \"Invalid Module Response: $response\"; close $sock;"
```

### Step 12: Test Security Validation
```cmd
REM Terminal 2 - Test dangerous function detection
perl -e "use IO::Socket::INET; use JSON::PP; open my $fh, '<', 'cpan_bridge_socket.txt'; my $socket_path = <$fh>; chomp $socket_path; close $fh; my ($host, $port) = split ':', $socket_path; my $sock = IO::Socket::INET->new(PeerAddr => $host, PeerPort => $port, Proto => 'tcp') or die \"Cannot connect: $!\"; my $request = encode_json({action => 'call_module', module => 'file_helper', function => 'eval', args => ['print \"test\"'], request_id => 'security_' . time()}); print $sock $request . \"\n\"; my $response = <$sock>; print \"Security Test Response: $response\"; close $sock;"
```

## Phase 6: Integration with Perl Bridge

### Step 13: Test via CPANBridge.pm
```cmd
REM Terminal 2 - Test through the actual Perl interface
cd C:\Users\sxdixit\ds\Perl_to_Python-architecture-revamp
perl -I. -e "use CPANBridge; my $bridge = CPANBridge->new(); print \"Testing through CPANBridge.pm:\n\"; my $result = $bridge->call_helper('string_helper', 'trim', '  hello world  '); print \"Trim result: '$result'\n\";"
```

## Phase 7: Cleanup and Shutdown Testing

### Step 14: Test Graceful Shutdown
```cmd
REM Terminal 1 - Send Ctrl+C to daemon
REM Press Ctrl+C in Terminal 1

REM Expected output in Terminal 1:
REM "Received shutdown signal, cleaning up..."
REM "Daemon shutdown complete"
```

### Step 15: Verify Cleanup
```cmd
REM Terminal 2 - Check socket info file removed
dir cpan_bridge_socket.txt
REM Should show: File Not Found
```

## Monitoring During Testing

### Watch Daemon Logs (Terminal 1)
Monitor for:
- Connection establishments/closures
- Request processing times
- Memory usage changes
- Any error messages

### Watch System Resources
```cmd
REM Terminal 3 - Monitor daemon process
tasklist | findstr python
REM Use Task Manager to monitor CPU/Memory usage
```

## Windows-Specific Log Locations

### View Log Files
```cmd
REM View daemon logs
type %TEMP%\cpan_daemon.log

REM View security logs
type %TEMP%\cpan_security.log

REM Monitor logs in real-time (PowerShell)
powershell "Get-Content %TEMP%\cpan_daemon.log -Wait"
```

### Log File Locations
- **Daemon logs**: `%TEMP%\cpan_daemon.log`
- **Security logs**: `%TEMP%\cpan_security.log`
- **Socket info**: `cpan_bridge_socket.txt` (in current directory)

## Expected Results Summary

### ✅ Success Indicators
- Daemon starts without errors
- TCP socket created successfully with port displayed
- Socket info file created with correct host:port format
- Health checks return "healthy" status
- All module calls return expected results
- Concurrent requests handled properly
- Security validation blocks dangerous functions
- Graceful shutdown works correctly
- No memory leaks or resource issues

### ❌ Failure Indicators
- TCP socket creation fails
- Module loading errors
- Connection timeouts
- Invalid JSON responses
- Memory usage continuously growing
- Socket info file not created or incorrect format
- Security validation not working

## Key Windows Differences

1. **Socket Type**: Uses TCP sockets (127.0.0.1:PORT) instead of Unix domain sockets
2. **Socket Discovery**: Reads connection info from `cpan_bridge_socket.txt` file
3. **Log Locations**: Uses Windows temporary directory (`%TEMP%`) instead of `/tmp`
4. **Path Separators**: Uses backslashes (`\`) in Windows paths
5. **Process Monitoring**: Uses `tasklist` instead of `ps` for process monitoring

## Troubleshooting Windows-Specific Issues

### Common Windows Problems
1. **Port Already in Use**: Daemon automatically selects available port
2. **Firewall Blocking**: Windows Firewall may block localhost connections
3. **Antivirus Interference**: Some antivirus software may flag the daemon
4. **Path Issues**: Use forward slashes in file paths for cross-platform compatibility

### Debug Commands
```cmd
REM Check if daemon is running
tasklist | findstr python

REM Check socket file contents
type cpan_bridge_socket.txt

REM Test direct TCP connection
telnet 127.0.0.1 PORT_NUMBER

REM View recent daemon logs
powershell "Get-Content %TEMP%\cpan_daemon.log | Select-Object -Last 20"
```

This testing guide ensures comprehensive validation of the CPAN Bridge daemon functionality on Windows systems while accounting for platform-specific differences.