# CPAN Bridge Daemon Architecture - Data Flow & Failure Analysis

## Overview
This document provides comprehensive architecture diagrams and failure scenario analysis for the proposed daemon-based CPAN Bridge system.

---

## 1. Data Flow Diagrams (DFD)

### Level 0: Context Diagram - System Overview
```
                    ┌─────────────────────────────────────┐
                    │         CPAN Bridge System          │
                    │                                     │
┌──────────────┐    │  ┌─────────────┐  ┌─────────────┐  │    ┌──────────────┐
│              │    │  │    Perl     │  │   Python    │  │    │              │
│  ControlM    │───▶│  │  Scripts    │◄─┤   Daemon    │  │───▶│  External    │
│  Jobs        │    │  │ (DBIHelper) │  │ (Persistent)│  │    │  Resources   │
│              │    │  └─────────────┘  └─────────────┘  │    │              │
└──────────────┘    │                                     │    └──────────────┘
                    └─────────────────────────────────────┘

    Input:              Process:                            Output:
    - Job requests      - DBI operations                   - Database results
    - SQL queries       - File operations                  - Files transferred
    - File transfers    - Excel generation                 - Reports generated
    - Email requests    - State management                 - Emails sent
```

### Level 1: Main Process Flow
```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   1.0       │────▶│    2.0      │────▶│    3.0      │────▶│    4.0      │
│ Perl Script │     │   Socket    │     │   Python    │     │  External   │
│  Execution  │     │ Communication│     │   Daemon    │     │  Resources  │
└─────────────┘     └─────────────┘     └─────────────┘     └─────────────┘
      │                    │                    │                    │
      ▼                    ▼                    ▼                    ▼
┌─────────────┐     ┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│ Load        │     │ JSON        │     │ Route       │     │ Database    │
│ DBIHelper   │     │ Request     │     │ Request     │     │ Oracle/     │
│ Modules     │     │ Packaging   │     │ to Module   │     │ Informix    │
└─────────────┘     └─────────────┘     └─────────────┘     └─────────────┘
      │                    │                    │                    │
      ▼                    ▼                    ▼                    ▼
┌─────────────┐     ┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│ Generate    │     │ Socket      │     │ Execute     │     │ SFTP        │
│ Python      │     │ Write/Read  │     │ Function    │     │ Servers     │
│ Request     │     │ Operations  │     │ Call        │     └─────────────┘
└─────────────┘     └─────────────┘     └─────────────┘           │
                                              │                    ▼
                                              ▼             ┌─────────────┐
                                       ┌─────────────┐     │ SMTP        │
                                       │ Manage      │     │ Servers     │
                                       │ Persistent  │     └─────────────┘
                                       │ State       │           │
                                       └─────────────┘           ▼
                                                          ┌─────────────┐
                                                          │ File        │
                                                          │ System      │
                                                          └─────────────┘
```

### Level 2: Detailed Component Flow

#### 2.1 Perl Script Process Flow
```
┌─────────────────────────────────────────────────────────────────────┐
│                           Perl Process                              │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│ ┌─────────────┐    ┌─────────────┐    ┌─────────────┐              │
│ │ User Script │───▶│ DBIHelper   │───▶│ CPANBridge  │              │
│ │ my $dbh =   │    │ .pm         │    │ .pm         │              │
│ │ DBI->       │    │             │    │             │              │
│ │ connect()   │    │ - connect() │    │ - call_     │              │
│ └─────────────┘    │ - prepare() │    │   python()  │              │
│                    │ - execute() │    │ - json      │              │
│                    │ - fetch()   │    │   encode    │              │
│                    └─────────────┘    │ - socket    │              │
│                           │           │   mgmt      │              │
│                           ▼           └─────────────┘              │
│                    ┌─────────────┐           │                     │
│                    │ Statement   │           ▼                     │
│                    │ Handle      │    ┌─────────────┐              │
│                    │ Objects     │    │ Socket      │              │
│                    │             │    │ Client      │              │
│                    │ - fetchrow  │    │             │              │
│                    │ - finish    │    │ Unix Domain │              │
│                    │ - DESTROY   │    │ Socket      │              │
│                    └─────────────┘    │ /tmp/cpan   │              │
│                                       │ _bridge.sock│              │
│                                       └─────────────┘              │
│                                             │                       │
└─────────────────────────────────────────────┼───────────────────────┘
                                              │
                                              ▼ JSON Request
                                       ┌─────────────┐
                                       │{            │
                                       │ "module":   │
                                       │ "database", │
                                       │ "function": │
                                       │ "connect",  │
                                       │ "params": { │
                                       │   "dsn": "" │
                                       │ }           │
                                       │}            │
                                       └─────────────┘
```

#### 2.2 Python Daemon Process Flow
```
┌─────────────────────────────────────────────────────────────────────┐
│                         Python Daemon Process                       │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│ ┌─────────────┐    ┌─────────────┐    ┌─────────────┐              │
│ │ Unix Socket │───▶│ Request     │───▶│ Module      │              │
│ │ Server      │    │ Router      │    │ Dispatcher  │              │
│ │             │    │             │    │             │              │
│ │ - bind()    │    │ - parse     │    │ - database  │              │
│ │ - listen()  │    │   JSON      │    │ - sftp      │              │
│ │ - accept()  │    │ - validate  │    │ - excel     │              │
│ │ - threading │    │ - route     │    │ - crypto    │              │
│ └─────────────┘    └─────────────┘    │ - xpath     │              │
│        ▲                   │          │ - logging   │              │
│        │                   ▼          └─────────────┘              │
│        │            ┌─────────────┐          │                     │
│        │            │ JSON        │          ▼                     │
│        │            │ Response    │   ┌─────────────┐              │
│        │            │ Builder     │   │ Persistent  │              │
│        │            │             │   │ State       │              │
│        │            │ - success   │   │ Manager     │              │
│        │            │ - result    │   │             │              │
│        │            │ - error     │   │ Global:     │              │
│        │            │ - metadata  │   │ _connections│              │
│        └────────────│             │   │ _statements │              │
│                     └─────────────┘   │ SFTP_SESSIONS│             │
│                                       │ WORKBOOKS   │              │
│                                       │ CIPHER_CACHE│              │
│                                       │ _documents  │              │
│                                       │ LOGGERS     │              │
│                                       └─────────────┘              │
│                                              │                     │
└──────────────────────────────────────────────┼─────────────────────┘
                                               │
                                               ▼ External Calls
                                        ┌─────────────┐
                                        │ External    │
                                        │ Resources   │
                                        │             │
                                        │ - Oracle DB │
                                        │ - SFTP      │
                                        │ - Files     │
                                        │ - SMTP      │
                                        └─────────────┘
```

### Level 3: Detailed State Management Flow

#### 3.1 Database Connection Flow
```
Perl Side                 Socket               Python Daemon
─────────────────────────────────────────────────────────────────

$dbh = DBI->connect()
    │
    ▼
call_python("database",
           "connect",
           {dsn, user, pass})
    │
    ▼
JSON Request ──────────▶ Unix Socket ──────────▶ Request Router
{                                                      │
  "module": "database",                               ▼
  "function": "connect",                        database.connect()
  "params": {                                          │
    "dsn": "dbi:Oracle:PROD",                         ▼
    "username": "user",                         oracledb.connect()
    "password": "pass"                                 │
  }                                                    ▼
}                                               _connections[conn_id] = {
                                                 'connection': conn,
                                                 'dsn': dsn,
                                                 'created_at': time()
                                               }
                                                       │
JSON Response ◄─────────── Unix Socket ◄─────────────┘
{
  "success": true,
  "result": {
    "connection_id": "conn_123",
    "connected": true
  }
}
    │
    ▼
Store connection_id in
DBIHelper object
```

#### 3.2 SFTP Session Flow
```
Perl Side                 Socket               Python Daemon
─────────────────────────────────────────────────────────────────

$sftp = Net::SFTP::
Foreign->new()
    │
    ▼
call_python("sftp",
           "new",
           {host, user, pass})
    │
    ▼
JSON Request ──────────▶ Unix Socket ──────────▶ Request Router
{                                                      │
  "module": "sftp",                                   ▼
  "function": "new",                            sftp.new()
  "params": {                                          │
    "host": "server.com",                             ▼
    "user": "username",                        paramiko.SSHClient()
    "password": "pass"                          .connect()
  }                                                    │
}                                                      ▼
                                               SFTP_SESSIONS[session_id] = {
                                                 'ssh_client': ssh,
                                                 'sftp_client': sftp,
                                                 'host': host,
                                                 'created_at': time()
                                               }
                                                       │
JSON Response ◄─────────── Unix Socket ◄─────────────┘
{
  "success": true,
  "result": {
    "session_id": "sftp_456",
    "connected": true
  }
}
    │
    ▼
Store session_id in
SFTP object

# Subsequent operations reuse the connection:
$sftp->put($file)
    │
    ▼
call_python("sftp", "put",
           {session_id: "sftp_456",
            local: $file,
            remote: $path})
    │
    ▼
Use existing SFTP_SESSIONS["sftp_456"] ──▶ Fast operation (no reconnect)
```

### Level 4: Multi-Module Workflow Example

#### 4.1 Complex Business Process Flow
```
Business Process: Generate Excel Report with Database Data and Email

┌─────────────────────────────────────────────────────────────────────────────┐
│                              Perl Script                                    │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│ 1. Database Connection                                                      │
│    my $dbh = DBI->connect("dbi:Oracle:PROD", $user, $pass);               │
│    ──────────────────────────────────────▶ daemon: database.connect()      │
│                                            Result: conn_id = "db_123"      │
│                                                                             │
│ 2. Excel Workbook Creation                                                  │
│    my $wb = Excel::Writer::XLSX->new("report.xlsx");                       │
│    ──────────────────────────────────────▶ daemon: excel.create_workbook() │
│                                            Result: wb_id = "wb_456"        │
│                                                                             │
│ 3. Database Query                                                           │
│    my $sth = $dbh->prepare("SELECT * FROM sales");                         │
│    ──────────────────────────────────────▶ daemon: database.prepare()      │
│                                            Uses: conn_id = "db_123"        │
│                                            Result: stmt_id = "stmt_789"    │
│                                                                             │
│ 4. Execute Query                                                            │
│    $sth->execute();                                                         │
│    ──────────────────────────────────────▶ daemon: database.execute()      │
│                                            Uses: stmt_id = "stmt_789"      │
│                                            Result: success = true          │
│                                                                             │
│ 5. Excel Worksheet Creation                                                 │
│    my $ws = $wb->add_worksheet("Sales Data");                              │
│    ──────────────────────────────────────▶ daemon: excel.add_worksheet()   │
│                                            Uses: wb_id = "wb_456"          │
│                                            Result: ws_id = "ws_101"        │
│                                                                             │
│ 6. Data Population Loop                                                     │
│    while (my @row = $sth->fetchrow_array()) {                              │
│        $ws->write($row_num, 0, $row[0]);                                    │
│    }   ──────────────────────────────────▶ daemon: database.fetch_row()    │
│        ──────────────────────────────────▶ daemon: excel.write_cell()      │
│                                            Uses: stmt_id = "stmt_789"      │
│                                            Uses: ws_id = "ws_101"          │
│                                            (Persistent state maintained)   │
│                                                                             │
│ 7. Close Excel File                                                         │
│    $wb->close();                                                            │
│    ──────────────────────────────────────▶ daemon: excel.close_workbook()  │
│                                            Uses: wb_id = "wb_456"          │
│                                            Result: file saved              │
│                                                                             │
│ 8. Email Report                                                             │
│    my $mailer = Mail::Sender->new({smtp => "mail.company.com"});           │
│    $mailer->MailFile({to => "boss@company.com", file => "report.xlsx"});   │
│    ──────────────────────────────────────▶ daemon: email.send_file()       │
│                                            Result: email sent              │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘

Daemon State During Process:
┌─────────────────────────────────────────────────────────────────────────────┐
│                           Python Daemon Memory                              │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│ _connections = {                                                            │
│   "db_123": {                                                               │
│     'connection': <OracleConnection>,                                       │
│     'dsn': "dbi:Oracle:PROD",                                               │
│     'last_used': time()                                                     │
│   }                                                                         │
│ }                                                                           │
│                                                                             │
│ _statements = {                                                             │
│   "stmt_789": {                                                             │
│     'connection_id': "db_123",                                              │
│     'sql': "SELECT * FROM sales",                                           │
│     'cursor': <OracleCursor>,                                               │
│     'executed': True                                                        │
│   }                                                                         │
│ }                                                                           │
│                                                                             │
│ WORKBOOKS = {                                                               │
│   "wb_456": {                                                               │
│     'workbook': <XLSXWorkbook>,                                             │
│     'filename': "report.xlsx",                                              │
│     'worksheets': ["ws_101"]                                                │
│   }                                                                         │
│ }                                                                           │
│                                                                             │
│ WORKSHEETS = {                                                              │
│   "ws_101": {                                                               │
│     'worksheet': <XLSXWorksheet>,                                           │
│     'workbook_id': "wb_456",                                                │
│     'name': "Sales Data",                                                   │
│     'current_row': 150                                                      │
│   }                                                                         │
│ }                                                                           │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘

Performance Comparison:
┌─────────────────────────────────────────────────────────────────────────────┐
│                    Current vs Daemon Performance                            │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│ Current (Process per Operation):                                            │
│ ┌─────────────────┬─────────────────┬─────────────────┬─────────────────┐  │
│ │ DB Connect      │ Excel Create    │ DB Prepare      │ Excel Worksheet │  │
│ │ 200ms           │ 150ms           │ 200ms           │ 150ms           │  │
│ │ (+ restore)     │ (+ recreate)    │ (+ restore)     │ (+ recreate)    │  │
│ └─────────────────┴─────────────────┴─────────────────┴─────────────────┘  │
│ │ DB Execute      │ Loop: Fetch+Write (x100 rows)     │ Excel Close     │  │
│ │ 200ms           │ (200ms + 150ms) * 100 = 35000ms  │ 150ms           │  │
│ │ (+ restore)     │ (restore + recreate each time)    │ (+ recreate)    │  │
│ └─────────────────┴─────────────────────────────────────┴─────────────────┘  │
│                                                                             │
│ Total Current: ~36,000ms (36 seconds)                                      │
│                                                                             │
│ Daemon (Persistent State):                                                 │
│ ┌─────────────────┬─────────────────┬─────────────────┬─────────────────┐  │
│ │ DB Connect      │ Excel Create    │ DB Prepare      │ Excel Worksheet │  │
│ │ 200ms           │ 150ms           │ 50ms            │ 10ms            │  │
│ │ (initial only)  │ (initial only)  │ (reuse conn)    │ (reuse wb)      │  │
│ └─────────────────┴─────────────────┴─────────────────┴─────────────────┘  │
│ │ DB Execute      │ Loop: Fetch+Write (x100 rows)     │ Excel Close     │  │
│ │ 50ms            │ (5ms + 2ms) * 100 = 700ms        │ 10ms            │  │
│ │ (reuse stmt)    │ (reuse cursor + worksheet)        │ (reuse wb)      │  │
│ └─────────────────┴─────────────────────────────────────┴─────────────────┘  │
│                                                                             │
│ Total Daemon: ~1,170ms (1.2 seconds)                                       │
│                                                                             │
│ Performance Improvement: 30x faster (97% reduction in time)                │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Failure Scenarios & Risk Analysis

### 2.1 Critical Failure Categories

#### 🔴 **CATEGORY 1: Daemon Process Failures**

##### Failure 1.1: Daemon Process Death
**Scenario**: Python daemon process crashes, exits, or is killed
```
┌─────────────────────────────────────────────────────────────────┐
│                    Daemon Death Scenario                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│ Normal Flow:                                                    │
│ Perl ──▶ Socket ──▶ [Daemon Running] ──▶ Database             │
│                                                                 │
│ Failure Point:                                                  │
│ Perl ──▶ Socket ──▶ [DAEMON DEAD] ──X──▶ Connection Refused   │
│                                                                 │
│ Impact:                                                         │
│ • All active connections lost                                   │
│ • All prepared statements lost                                  │
│ • All Excel workbooks lost                                      │
│ • All SFTP sessions terminated                                  │
│ • In-progress operations fail                                   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**Risk Level**: 🔴 HIGH
**Probability**: Medium (process crashes, OOM, system restart)
**Business Impact**: Complete service interruption

**Mitigation Strategies**:
1. **Automatic Restart**:
   ```perl
   sub _ensure_daemon_running {
       return 1 if _ping_daemon();

       _log_warning("Daemon down, attempting restart");
       return _start_daemon();
   }
   ```

2. **Fallback to Process Mode**:
   ```perl
   sub call_python {
       my $result = _try_daemon_call(@_);
       return $result if $result->{success};

       _log_warning("Daemon failed, falling back to process mode");
       return _call_python_process_mode(@_);
   }
   ```

3. **Health Monitoring**:
   ```python
   # In daemon
   def health_check_thread():
       while True:
           time.sleep(30)
           cleanup_stale_connections()
           log_memory_usage()
   ```

##### Failure 1.2: Daemon Startup Failure
**Scenario**: Daemon fails to start (permissions, port conflicts, missing dependencies)

**Risk Level**: 🔴 HIGH
**Probability**: Low (deployment/configuration issues)
**Business Impact**: No daemon benefits, falls back to process mode

**Mitigation Strategies**:
1. **Dependency Validation**:
   ```python
   def validate_environment():
       required_modules = ['oracledb', 'paramiko', 'openpyxl']
       for module in required_modules:
           try:
               __import__(module)
           except ImportError:
               log_error(f"Missing module: {module}")
               return False
       return True
   ```

2. **Permission Checks**:
   ```python
   def check_socket_permissions():
       socket_dir = os.path.dirname(SOCKET_PATH)
       if not os.access(socket_dir, os.W_OK):
           log_error(f"Cannot write to socket directory: {socket_dir}")
           return False
       return True
   ```

##### Failure 1.3: Daemon Memory Exhaustion
**Scenario**: Daemon accumulates too much state and runs out of memory

**Risk Level**: 🟡 MEDIUM
**Probability**: Medium (long-running processes, memory leaks)
**Business Impact**: Degraded performance, eventual daemon crash

**Mitigation Strategies**:
1. **Connection Limits**:
   ```python
   MAX_CONNECTIONS = 100
   MAX_STATEMENTS = 1000
   MAX_SESSIONS = 50

   def enforce_limits():
       if len(_connections) > MAX_CONNECTIONS:
           cleanup_oldest_connections()
   ```

2. **Automatic Cleanup**:
   ```python
   def cleanup_stale_resources():
       now = time.time()
       stale_connections = [
           conn_id for conn_id, conn in _connections.items()
           if now - conn['last_used'] > CONNECTION_TIMEOUT
       ]
       for conn_id in stale_connections:
           cleanup_connection(conn_id)
   ```

#### 🟡 **CATEGORY 2: Communication Failures**

##### Failure 2.1: Socket Communication Breakdown
**Scenario**: Unix socket becomes unavailable or corrupted

**Risk Level**: 🟡 MEDIUM
**Probability**: Low (file system issues, permissions)
**Business Impact**: Service interruption until socket recovery

**Mitigation Strategies**:
1. **Socket Recreation**:
   ```perl
   sub _handle_socket_error {
       my ($error) = @_;

       if ($error =~ /Connection refused|No such file/) {
           _cleanup_stale_socket();
           return _start_daemon();
       }
       return 0;
   }
   ```

2. **Alternative Communication**:
   ```perl
   # Fallback to TCP socket if Unix socket fails
   sub _try_tcp_fallback {
       my $socket = IO::Socket::INET->new(
           PeerAddr => 'localhost',
           PeerPort => 9999,
           Proto    => 'tcp'
       );
       return $socket;
   }
   ```

##### Failure 2.2: JSON Serialization/Deserialization Errors
**Scenario**: Complex data structures fail to serialize or corrupt during transport

**Risk Level**: 🟡 MEDIUM
**Probability**: Low (edge cases with binary data, circular references)
**Business Impact**: Individual operation failures

**Mitigation Strategies**:
1. **Data Validation**:
   ```python
   def safe_json_encode(data):
       try:
           return json.dumps(data, default=str, ensure_ascii=False)
       except (TypeError, ValueError) as e:
           return json.dumps({
               'success': False,
               'error': f'Serialization error: {str(e)}'
           })
   ```

2. **Size Limits**:
   ```python
   MAX_REQUEST_SIZE = 10 * 1024 * 1024  # 10MB

   def validate_request_size(data):
       if len(data) > MAX_REQUEST_SIZE:
           raise ValueError(f"Request too large: {len(data)} bytes")
   ```

#### 🟢 **CATEGORY 3: External Resource Failures**

##### Failure 3.1: Database Connection Loss
**Scenario**: Database server becomes unavailable or connections timeout

**Risk Level**: 🟢 LOW
**Probability**: Medium (database maintenance, network issues)
**Business Impact**: Database operations fail (same as current system)

**Mitigation Strategies**:
1. **Connection Pooling**:
   ```python
   def get_or_create_connection(conn_id):
       if conn_id in _connections:
           conn = _connections[conn_id]['connection']
           if _test_connection(conn):
               return conn
           else:
               _cleanup_connection(conn_id)

       return _create_new_connection(conn_id)
   ```

2. **Automatic Retry**:
   ```python
   def execute_with_retry(conn_id, sql, max_retries=3):
       for attempt in range(max_retries):
           try:
               conn = get_or_create_connection(conn_id)
               return conn.execute(sql)
           except DatabaseError as e:
               if attempt == max_retries - 1:
                   raise
               time.sleep(2 ** attempt)  # Exponential backoff
   ```

##### Failure 3.2: SFTP Server Unavailability
**Scenario**: SFTP servers become unreachable or authentication fails

**Risk Level**: 🟢 LOW
**Probability**: Medium (server maintenance, network issues)
**Business Impact**: SFTP operations fail (same as current system)

**Mitigation Strategies**:
1. **Connection Validation**:
   ```python
   def validate_sftp_session(session_id):
       if session_id not in SFTP_SESSIONS:
           return False

       session = SFTP_SESSIONS[session_id]
       try:
           # Test connection with simple operation
           session['sftp_client'].listdir('.')
           return True
       except Exception:
           cleanup_sftp_session(session_id)
           return False
   ```

### 2.2 Cascade Failure Scenarios

#### Cascade 1: Daemon Death During Multi-Step Operation
**Scenario**: Daemon crashes in the middle of a complex workflow

```
Step 1: Connect to DB ✅ (Success - connection stored in daemon)
Step 2: Create Excel ✅ (Success - workbook stored in daemon)
Step 3: Prepare SQL ✅ (Success - statement stored in daemon)
Step 4: Execute SQL ✅ (Success - cursor stored in daemon)
Step 5: Fetch data ❌ (DAEMON CRASHES - all state lost)
Step 6: Write Excel ❌ (Fails - workbook reference lost)
Step 7: Close Excel ❌ (Fails - workbook reference lost)
```

**Impact**: Partial operation completion, potential resource leaks
**Mitigation**:
- Stateless operation design where possible
- Operation checkpointing for critical workflows
- Automatic cleanup on daemon restart

#### Cascade 2: Resource Exhaustion Chain
**Scenario**: One resource type exhaustion leads to system-wide failure

```
1. SFTP sessions accumulate (no cleanup) ──▶ Memory pressure
2. Memory pressure affects daemon performance ──▶ Slower responses
3. Slower responses cause Perl timeouts ──▶ More retry attempts
4. More retries create more sessions ──▶ Accelerated memory exhaustion
5. Daemon OOM kill ──▶ Complete service failure
```

**Mitigation**:
- Aggressive resource cleanup policies
- Circuit breaker patterns for failing resources
- Memory monitoring and alerts

### 2.3 Security Failure Scenarios

#### Security 1: Socket Permission Escalation
**Scenario**: Unix socket permissions allow unauthorized access

**Risk Level**: 🟡 MEDIUM
**Probability**: Low (configuration errors)
**Business Impact**: Potential unauthorized database/system access

**Mitigation**:
```python
def secure_socket_creation():
    if os.path.exists(SOCKET_PATH):
        os.unlink(SOCKET_PATH)

    server_socket = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    server_socket.bind(SOCKET_PATH)

    # Set restrictive permissions (owner only)
    os.chmod(SOCKET_PATH, 0o600)

    return server_socket
```

#### Security 2: Process Injection via JSON
**Scenario**: Malicious JSON payloads attempt code execution

**Risk Level**: 🔴 HIGH
**Probability**: Low (requires access to Perl processes)
**Business Impact**: Potential system compromise

**Mitigation**:
```python
def validate_request_security(request):
    # Whitelist allowed modules and functions
    allowed_modules = {
        'database': ['connect', 'prepare', 'execute', 'fetch'],
        'sftp': ['new', 'put', 'get', 'ls'],
        'excel': ['create_workbook', 'add_worksheet', 'write_cell']
    }

    module = request.get('module')
    function = request.get('function')

    if module not in allowed_modules:
        raise SecurityError(f"Module not allowed: {module}")

    if function not in allowed_modules[module]:
        raise SecurityError(f"Function not allowed: {module}.{function}")
```

### 2.4 Performance Degradation Scenarios

#### Performance 1: Lock Contention
**Scenario**: High concurrency causes thread lock contention in daemon

**Risk Level**: 🟡 MEDIUM
**Probability**: Medium (high load scenarios)
**Business Impact**: Degraded response times

**Mitigation**:
```python
import threading
from collections import defaultdict

# Per-resource locks instead of global locks
_connection_locks = defaultdict(threading.RLock)
_statement_locks = defaultdict(threading.RLock)

def thread_safe_operation(resource_type, resource_id, operation):
    lock = _connection_locks[resource_id] if resource_type == 'connection' else _statement_locks[resource_id]
    with lock:
        return operation()
```

#### Performance 2: Memory Fragmentation
**Scenario**: Long-running daemon suffers memory fragmentation

**Risk Level**: 🟡 MEDIUM
**Probability**: Medium (long uptimes)
**Business Impact**: Increased memory usage, potential swapping

**Mitigation**:
```python
def periodic_memory_optimization():
    # Periodic garbage collection
    import gc
    gc.collect()

    # Compact data structures
    compact_connection_cache()
    compact_statement_cache()

    # Log memory statistics
    log_memory_usage()
```

### 2.5 Operational Failure Scenarios

#### Operational 1: Daemon Version Mismatch
**Scenario**: Perl code expects newer daemon API than what's running

**Risk Level**: 🟡 MEDIUM
**Probability**: Medium (deployment issues)
**Business Impact**: Feature failures, unexpected errors

**Mitigation**:
```python
DAEMON_VERSION = "2.0.0"
MIN_CLIENT_VERSION = "1.5.0"

def validate_client_compatibility(request):
    client_version = request.get('client_version', '1.0.0')
    if version_compare(client_version, MIN_CLIENT_VERSION) < 0:
        raise CompatibilityError(f"Client version {client_version} too old")
```

#### Operational 2: Configuration Drift
**Scenario**: Daemon and Perl configurations become inconsistent

**Risk Level**: 🟡 MEDIUM
**Probability**: Medium (manual configuration changes)
**Business Impact**: Connection failures, unexpected behavior

**Mitigation**:
```python
def load_shared_config():
    config_file = os.environ.get('CPAN_BRIDGE_CONFIG', '/etc/cpan_bridge.conf')
    with open(config_file) as f:
        return json.load(f)

# Both Perl and Python read same config file
```

### 2.6 Risk Mitigation Summary

#### High Priority Mitigations (Must Implement)

1. **Daemon Health Monitoring**:
   ```bash
   # Systemd service file
   [Unit]
   Description=CPAN Bridge Daemon
   After=network.target

   [Service]
   Type=simple
   ExecStart=/usr/bin/python3 /opt/cpan_bridge/daemon.py
   Restart=always
   RestartSec=5
   User=cpan_bridge
   Group=cpan_bridge

   [Install]
   WantedBy=multi-user.target
   ```

2. **Graceful Fallback System**:
   ```perl
   # In CPANBridge.pm
   our $DAEMON_MODE = $ENV{CPAN_BRIDGE_DAEMON} // 1;
   our $FALLBACK_ENABLED = $ENV{CPAN_BRIDGE_FALLBACK} // 1;

   sub call_python {
       return _call_python_process(@_) unless $DAEMON_MODE;

       my $result = _try_daemon_call(@_);
       return $result if $result->{success};

       return _call_python_process(@_) if $FALLBACK_ENABLED;
       return $result;  # Return daemon error if fallback disabled
   }
   ```

3. **Resource Cleanup Framework**:
   ```python
   class ResourceManager:
       def __init__(self):
           self.cleanup_callbacks = []
           signal.signal(signal.SIGTERM, self.graceful_shutdown)
           signal.signal(signal.SIGINT, self.graceful_shutdown)

       def register_cleanup(self, callback):
           self.cleanup_callbacks.append(callback)

       def graceful_shutdown(self, signum, frame):
           for callback in self.cleanup_callbacks:
               try:
                   callback()
               except Exception as e:
                   log_error(f"Cleanup error: {e}")
   ```

#### Medium Priority Mitigations (Should Implement)

1. **Circuit Breaker Pattern**
2. **Connection Pooling**
3. **Memory Monitoring**
4. **Performance Metrics Collection**

#### Low Priority Mitigations (Nice to Have)

1. **Distributed Daemon Architecture**
2. **Hot Reload Configuration**
3. **Advanced Security Auditing**

---

## 3. Implementation Recommendations

### Phase 1: Minimal Viable Daemon (MVP)
- Basic socket server with health checks
- Simple request routing
- Fallback to process mode on any failure
- Comprehensive logging

### Phase 2: Production Hardening
- Resource cleanup and limits
- Memory monitoring
- Security validation
- Performance optimization

### Phase 3: Advanced Features
- Circuit breakers
- Distributed architecture
- Advanced monitoring and alerting

This architecture provides a robust foundation while maintaining the ability to fall back to the current system in case of any daemon-related issues.

<function_calls>
<invoke name="TodoWrite">
<parameter name="todos">[{"content": "Create DFD and architecture diagrams for daemon approach", "status": "completed", "activeForm": "Creating DFD and architecture diagrams for daemon approach"}, {"content": "Analyze all failure scenarios and mitigation strategies", "status": "in_progress", "activeForm": "Analyzing all failure scenarios and mitigation strategies"}]