# Kerberos Implementation Plan - Based on POC

## POC Analysis

### Key Requirements Identified from POC:

1. **Environment Variables (Critical)**
   - `KRB5_CONFIG` - Path to krb5.conf file
   - `KRB5CCNAME` - Path to Kerberos credential cache
   - Both must exist and be validated before connection

2. **Oracle Thick Client (Critical)**
   - `oracledb.init_oracle_client()` must be called once
   - Required for Kerberos/external authentication
   - Should be initialized globally, not per-connection

3. **Connection Method**
   - `externalauth=True` parameter
   - No username/password needed
   - DSN format: `host:port/service_name`

4. **Validation**
   - Environment variables must be checked before attempting connection
   - Files must exist at specified paths

## Smart Integration Strategy

### Design Principles:

1. **Minimal Changes** - Don't break existing password authentication
2. **Single Initialization** - Init Oracle thick client once globally
3. **Environment Handling** - Validate and preserve Kerberos environment
4. **Smart Auto-Detection** - Check KRB5_CONFIG and KRB5CCNAME environment variables to auto-select Kerberos
5. **Graceful Fallback** - Clear error messages for missing requirements

### Architecture Overview:

```
┌──────────────────────────────────────────────────────────┐
│ connect(dsn, username, password, auth_mode='auto')       │
│   ↓                                                       │
│   ├─ Auto-detect if auth_mode='auto':                    │
│   │   ├─ Check if KRB5_CONFIG env var exists            │
│   │   ├─ Check if KRB5CCNAME env var exists             │
│   │   └─ Both present? → Kerberos, else → Password      │
│   │                                                       │
│   ├─ If Kerberos:                                        │
│   │   ├─ Validate KRB5_CONFIG file exists               │
│   │   ├─ Validate KRB5CCNAME file exists                │
│   │   ├─ Ensure Oracle thick client initialized         │
│   │   └─ Connect with externalauth=True                 │
│   │                                                       │
│   └─ If Password:                                        │
│       └─ Connect with username/password                  │
└──────────────────────────────────────────────────────────┘
```

## Implementation Plan

### Phase 1: Add Oracle Thick Client Initialization (Global)

**Location:** Top of `database.py` module

**Add after imports:**
```python
# Global Oracle thick client initialization state
_ORACLE_THICK_CLIENT_INITIALIZED = False
_ORACLE_THICK_CLIENT_INIT_LOCK = threading.Lock()

def _ensure_oracle_thick_client() -> Dict[str, Any]:
    """
    Ensure Oracle thick client is initialized (required for Kerberos)

    This should be called once globally before any Kerberos connections.
    Thread-safe initialization.

    Returns:
        Dict with success status
    """
    global _ORACLE_THICK_CLIENT_INITIALIZED

    with _ORACLE_THICK_CLIENT_INIT_LOCK:
        if _ORACLE_THICK_CLIENT_INITIALIZED:
            return {
                'success': True,
                'message': 'Oracle thick client already initialized'
            }

        try:
            # Initialize Oracle thick client (needed for external auth)
            oracledb.init_oracle_client()
            _ORACLE_THICK_CLIENT_INITIALIZED = True

            return {
                'success': True,
                'message': 'Oracle thick client initialized successfully'
            }
        except Exception as e:
            error_msg = str(e)

            # Provide helpful error messages
            if 'cannot be used in thin mode' in error_msg.lower():
                return {
                    'success': False,
                    'error': 'Oracle thick client initialization failed - thick mode required for Kerberos'
                }
            else:
                return {
                    'success': False,
                    'error': f'Oracle thick client initialization failed: {error_msg}'
                }
```

### Phase 2: Add Kerberos Environment Validation

**New function:**
```python
def _validate_kerberos_environment() -> Dict[str, Any]:
    """
    Validate Kerberos environment variables

    Checks that KRB5_CONFIG and KRB5CCNAME are set and point to existing files.
    This matches the POC validation logic.

    Returns:
        Dict with success status and environment info
    """
    krb5_config = os.getenv("KRB5_CONFIG")
    krb5_ccname = os.getenv("KRB5CCNAME")

    errors = []

    # Validate KRB5_CONFIG
    if not krb5_config:
        errors.append("KRB5_CONFIG environment variable not set")
    elif not os.path.exists(krb5_config):
        errors.append(f"KRB5_CONFIG file does not exist: {krb5_config}")

    # Validate KRB5CCNAME
    if not krb5_ccname:
        errors.append("KRB5CCNAME environment variable not set")
    elif not os.path.exists(krb5_ccname):
        errors.append(f"KRB5CCNAME file does not exist: {krb5_ccname}")

    if errors:
        return {
            'success': False,
            'error': 'Kerberos environment validation failed',
            'details': errors,
            'help': (
                "To use Kerberos authentication:\n"
                "1. Ensure you have a valid Kerberos ticket (run 'kinit')\n"
                "2. Set KRB5_CONFIG to your krb5.conf path\n"
                "3. Set KRB5CCNAME to your credential cache path\n"
                "Example:\n"
                "  export KRB5_CONFIG=/etc/krb5.conf\n"
                "  export KRB5CCNAME=/tmp/krb5cc_1000"
            )
        }

    return {
        'success': True,
        'krb5_config': krb5_config,
        'krb5_ccname': krb5_ccname,
        'message': 'Kerberos environment validated successfully'
    }
```

### Phase 3: Add Kerberos Connection Function

**New function (matches POC logic):**
```python
def _connect_oracle_kerberos(connection_params: Dict[str, str],
                             username: str = '',
                             options: Dict = None) -> Any:
    """
    Connect to Oracle database using Kerberos authentication

    This matches the POC implementation:
    1. Validates Kerberos environment (KRB5_CONFIG, KRB5CCNAME)
    2. Ensures Oracle thick client is initialized
    3. Connects with externalauth=True

    Args:
        connection_params: Parsed DSN parameters
        username: Optional username (usually not needed for Kerberos)
        options: Connection options

    Returns:
        Oracle connection object

    Raises:
        RuntimeError: If Kerberos setup is invalid or connection fails
    """
    # Step 1: Validate Kerberos environment (from POC)
    env_check = _validate_kerberos_environment()
    if not env_check['success']:
        raise RuntimeError(
            f"{env_check['error']}: {', '.join(env_check['details'])}\n\n"
            f"{env_check['help']}"
        )

    # Step 2: Ensure Oracle thick client is initialized (from POC)
    thick_client_init = _ensure_oracle_thick_client()
    if not thick_client_init['success']:
        raise RuntimeError(
            f"Cannot use Kerberos authentication: {thick_client_init['error']}\n"
            "Kerberos requires Oracle thick client mode."
        )

    # Step 3: Build connection string (same format as POC: host:port/service_name)
    if 'service_name' in connection_params:
        connect_string = f"{connection_params.get('host', 'localhost')}:{connection_params.get('port', 1521)}/{connection_params['service_name']}"
    elif 'sid' in connection_params:
        connect_string = f"{connection_params.get('host', 'localhost')}:{connection_params.get('port', 1521)}/{connection_params['sid']}"
    elif 'tns' in connection_params:
        connect_string = connection_params['tns']
    else:
        raise RuntimeError("Invalid DSN for Kerberos connection - need host:port/service_name format")

    try:
        # Step 4: Connect with externalauth=True (from POC)
        conn = oracledb.connect(
            dsn=connect_string,
            externalauth=True  # This is the key for Kerberos
        )

        return conn

    except Exception as e:
        error_msg = str(e).lower()

        # Provide helpful error messages for common Kerberos issues
        if 'ora-01017' in error_msg or 'invalid username/password' in error_msg:
            raise RuntimeError(
                "Kerberos authentication failed - ORA-01017\n"
                "Possible causes:\n"
                "1. No valid Kerberos ticket (run 'kinit username')\n"
                "2. Ticket expired (run 'kinit -R' to renew)\n"
                "3. Oracle database not configured for Kerberos\n"
                "4. Check 'klist' to verify ticket status"
            )
        elif 'ora-12641' in error_msg:
            raise RuntimeError(
                "Kerberos authentication failed - ORA-12641\n"
                "Authentication service not initialized\n"
                "Check Oracle sqlnet.ora: AUTHENTICATION_SERVICES=(KERBEROS5)"
            )
        elif 'ora-12649' in error_msg:
            raise RuntimeError(
                "Kerberos authentication failed - ORA-12649\n"
                "Unknown encryption/checksum type\n"
                "Kerberos encryption type may not be supported by Oracle"
            )
        else:
            raise RuntimeError(f"Kerberos connection failed: {str(e)}")
```

### Phase 4: Update Main connect() Function

**Modify `connect()` function:**
```python
def connect(dsn: str, username: str = '', password: str = '',
            options: Dict = None, db_type: str = '',
            auth_mode: str = 'auto') -> Dict[str, Any]:
    """
    Connect to Oracle database using oracledb driver

    Supports two authentication modes:
    - 'password': Traditional username/password
    - 'kerberos': Kerberos ticket-based authentication
    - 'auto': Auto-detect based on environment variables (default)

    Auto-detection logic:
    - If KRB5_CONFIG and KRB5CCNAME are both set -> Kerberos
    - Otherwise -> Password authentication

    For Kerberos, set environment variables:
    - KRB5_CONFIG: Path to krb5.conf
    - KRB5CCNAME: Path to credential cache
    """
    try:
        connection_id = str(uuid.uuid4())

        # Auto-detect authentication mode based on environment variables
        actual_auth_mode = auth_mode
        if auth_mode == 'auto':
            # Check if Kerberos environment variables are set
            krb5_config = os.getenv("KRB5_CONFIG")
            krb5_ccname = os.getenv("KRB5CCNAME")

            if krb5_config and krb5_ccname:
                # Both Kerberos env vars present -> use Kerberos
                actual_auth_mode = 'kerberos'
            else:
                # Kerberos env vars missing -> use password
                actual_auth_mode = 'password'

        # Handle Oracle TNS-in-username pattern
        actual_username = username
        if '@' in username:
            actual_username, tns_name = username.split('@', 1)
            if dsn in ['dbi:Oracle:', 'dbi:Oracle', 'dbi:Ora:', 'dbi:Ora']:
                dsn = tns_name

        # Parse Oracle connection details
        connection_params = _parse_oracle_dsn(dsn)

        # Route to appropriate authentication method
        if actual_auth_mode == 'kerberos':
            conn = _connect_oracle_kerberos(connection_params, actual_username, options)
        else:  # password (default)
            conn = _connect_oracle(connection_params, actual_username, password, options)

        if not conn:
            raise RuntimeError("Failed to establish Oracle database connection")

        # Store connection with metadata
        connection_metadata = {
            'connection': conn,
            'type': 'oracle',
            'dsn': dsn,
            'username': actual_username,
            'auth_mode': actual_auth_mode,  # NEW: Track auth mode
            'autocommit': options.get('AutoCommit', True) if options else True,
            'raise_error': options.get('RaiseError', False) if options else False,
            'print_error': options.get('PrintError', True) if options else True,
        }
        _connections[connection_id] = connection_metadata

        # Configure autocommit
        conn.autocommit = connection_metadata['autocommit']

        # Save connection metadata (only save password for password auth)
        _save_connection_metadata(
            connection_id,
            connection_metadata,
            password if actual_auth_mode == 'password' else '',
            actual_auth_mode
        )

        return {
            'success': True,
            'connection_id': connection_id,
            'db_type': 'oracle',
            'auth_mode': actual_auth_mode
        }

    except Exception as e:
        return {
            'success': False,
            'error': str(e),
            'traceback': traceback.format_exc()
        }
```

### Phase 5: Update Metadata Functions

**Update `_save_connection_metadata()`:**
```python
def _save_connection_metadata(connection_id: str, metadata: Dict[str, Any],
                              password: str = '', auth_mode: str = 'password'):
    """Save connection metadata to persistent storage"""
    try:
        _ensure_persistence_dir()
        metadata_file = os.path.join(_PERSISTENCE_DIR, f"{connection_id}.json")

        persistent_metadata = {
            'connection_id': connection_id,
            'type': metadata.get('type'),
            'dsn': metadata.get('dsn'),
            'username': metadata.get('username'),
            'password': _simple_encrypt(password) if password and auth_mode == 'password' else '',
            'auth_mode': auth_mode,  # NEW: Store auth mode
            'autocommit': metadata.get('autocommit'),
            'raise_error': metadata.get('raise_error'),
            'print_error': metadata.get('print_error'),
            'created_at': time.time(),
            'last_used': time.time()
        }

        with open(metadata_file, 'w') as f:
            json.dump(persistent_metadata, f)

        return True
    except Exception:
        return False
```

**Update `_restore_connection_from_metadata()`:**
```python
def _restore_connection_from_metadata(metadata: Dict[str, Any]) -> Optional[Any]:
    """Restore Oracle connection from metadata"""
    try:
        connection_params = _parse_oracle_dsn(metadata['dsn'])
        auth_mode = metadata.get('auth_mode', 'password')

        # Restore based on authentication mode
        if auth_mode == 'kerberos':
            # For Kerberos, reconnect using current ticket
            # No password needed
            conn = _connect_oracle_kerberos(connection_params, metadata['username'])
        else:  # password
            # Decrypt stored password
            password = _simple_decrypt(metadata.get('password', ''))
            options = {
                'AutoCommit': metadata.get('autocommit', True),
                'RaiseError': metadata.get('raise_error', False),
                'PrintError': metadata.get('print_error', True)
            }
            conn = _connect_oracle(connection_params, metadata['username'], password, options)

        return conn

    except Exception as e:
        return None
```

### Phase 6: Add Import for threading

**Add at top of file:**
```python
import threading  # For thick client initialization lock
```

## Perl Usage Examples

### Example 1: Basic Kerberos Connection (Matching POC)
```perl
#!/usr/bin/perl
use strict;
use warnings;
use lib '.';
use CPANBridge;

$CPANBridge::DAEMON_MODE = 1;

# Ensure environment variables are set (like POC)
$ENV{KRB5_CONFIG} = '/etc/krb5.conf';
$ENV{KRB5CCNAME} = '/tmp/krb5cc_1000';

my $bridge = CPANBridge->new();

# Connect using Kerberos (no username/password)
my $result = $bridge->call_python('database', 'connect', {
    dsn => 'dbhost:6136/servicename',  # Same format as POC
    username => '',
    password => '',
    auth_mode => 'kerberos'
});

if ($result->{success}) {
    my $conn_id = $result->{result}->{connection_id};
    print "Connected via Kerberos: $conn_id\n";

    # Query like POC
    my $query = $bridge->call_python('database', 'execute_immediate', {
        connection_id => $conn_id,
        sql => 'SELECT user FROM dual'
    });

    # Cleanup
    $bridge->call_python('database', 'disconnect', {
        connection_id => $conn_id
    });
} else {
    print "Connection failed: " . $result->{error} . "\n";
}
```

### Example 2: Auto-Detection (Based on Environment Variables)
```perl
# If KRB5_CONFIG and KRB5CCNAME are set, automatically uses Kerberos
$ENV{KRB5_CONFIG} = '/etc/krb5.conf';
$ENV{KRB5CCNAME} = '/tmp/krb5cc_1000';

# No need to specify auth_mode - it auto-detects!
my $result = $bridge->call_python('database', 'connect', {
    dsn => 'dbhost:6136/servicename',
    username => '',
    password => ''
    # auth_mode defaults to 'auto' - will detect Kerberos from env vars
});
```

### Example 2b: Force Password Authentication (Override Auto-Detection)
```perl
# Even if Kerberos env vars are set, use password auth
$ENV{KRB5_CONFIG} = '/etc/krb5.conf';  # Present but ignored
$ENV{KRB5CCNAME} = '/tmp/krb5cc_1000'; # Present but ignored

my $result = $bridge->call_python('database', 'connect', {
    dsn => 'mydb',
    username => 'scott',
    password => 'tiger',
    auth_mode => 'password'  # Explicitly force password auth
});
```

### Example 3: Environment Variable Validation
```perl
# Check environment before connecting
use Env qw(KRB5_CONFIG KRB5CCNAME);

if (!$KRB5_CONFIG || !-f $KRB5_CONFIG) {
    die "KRB5_CONFIG not set or file missing\n";
}

if (!$KRB5CCNAME || !-f $KRB5CCNAME) {
    die "KRB5CCNAME not set or file missing\n";
}

print "Kerberos environment validated\n";
print "  KRB5_CONFIG: $KRB5_CONFIG\n";
print "  KRB5CCNAME: $KRB5CCNAME\n";

# Now connect...
```

## Testing Strategy

### Test 1: Auto-Detection Logic
```perl
#!/usr/bin/perl
# test_kerberos_autodetect.pl

use lib '.';
use CPANBridge;

$CPANBridge::DAEMON_MODE = 1;

print "=== Test 1: Auto-Detection Logic ===\n\n";

my $bridge = CPANBridge->new();

# Test 1a: No Kerberos env vars -> should use password auth
print "Test 1a: No Kerberos env vars (should use password)\n";
delete $ENV{KRB5_CONFIG};
delete $ENV{KRB5CCNAME};

my $result1 = $bridge->call_python('database', 'connect', {
    dsn => 'mydb',
    username => 'scott',
    password => 'tiger'
    # auth_mode defaults to 'auto'
});

print "Result: " . ($result1->{success} ? "✅ Used password auth" : "❌ Failed") . "\n\n";

# Test 1b: Both Kerberos env vars present -> should use Kerberos
print "Test 1b: Both Kerberos env vars present (should use Kerberos)\n";
$ENV{KRB5_CONFIG} = '/etc/krb5.conf';
$ENV{KRB5CCNAME} = '/tmp/krb5cc_1000';

my $result2 = $bridge->call_python('database', 'connect', {
    dsn => 'dbhost:6136/servicename',
    username => '',
    password => ''
    # auth_mode defaults to 'auto' -> will detect Kerberos
});

if ($result2->{success}) {
    print "✅ Auto-detected Kerberos\n";
    print "Auth mode: " . $result2->{result}->{auth_mode} . "\n";
} else {
    print "❌ Failed: " . $result2->{error} . "\n";
}

# Test 1c: Only one env var present -> should use password
print "\nTest 1c: Only KRB5_CONFIG set (should use password)\n";
$ENV{KRB5_CONFIG} = '/etc/krb5.conf';
delete $ENV{KRB5CCNAME};

my $result3 = $bridge->call_python('database', 'connect', {
    dsn => 'mydb',
    username => 'scott',
    password => 'tiger'
});

if ($result3->{success}) {
    print "✅ Used password auth (Kerberos incomplete)\n";
    print "Auth mode: " . $result3->{result}->{auth_mode} . "\n";
}
```

### Test 2: Thick Client Initialization
```perl
#!/usr/bin/perl
# test_kerberos_thick_client.pl

use lib '.';
use CPANBridge;

$CPANBridge::DAEMON_MODE = 1;
$ENV{KRB5_CONFIG} = '/etc/krb5.conf';
$ENV{KRB5CCNAME} = '/tmp/krb5cc_1000';

print "=== Test 2: Oracle Thick Client Initialization ===\n\n";

my $bridge = CPANBridge->new();

# First connection should initialize thick client
my $result1 = $bridge->call_python('database', 'connect', {
    dsn => 'dbhost:6136/servicename',
    auth_mode => 'kerberos'
});

print "First connection: " . ($result1->{success} ? "✅" : "❌") . "\n";

# Second connection should reuse initialized client
my $result2 = $bridge->call_python('database', 'connect', {
    dsn => 'dbhost:6136/servicename',
    auth_mode => 'kerberos'
});

print "Second connection: " . ($result2->{success} ? "✅" : "❌") . "\n";
```

### Test 3: Full POC Replication
```perl
#!/usr/bin/perl
# test_kerberos_full_poc.pl

use strict;
use warnings;
use lib '.';
use CPANBridge;

$CPANBridge::DAEMON_MODE = 1;

# Set environment (matching POC)
$ENV{KRB5_CONFIG} = $ENV{KRB5_CONFIG} || '/etc/krb5.conf';
$ENV{KRB5CCNAME} = $ENV{KRB5CCNAME} || '/tmp/krb5cc_1000';

print "=== Full POC Replication Test ===\n\n";

my $bridge = CPANBridge->new();

# Connect (matching POC)
print "Connecting to dbhost:6136/servicename...\n";
my $result = $bridge->call_python('database', 'connect', {
    dsn => 'dbhost:6136/servicename',
    username => '',
    password => '',
    auth_mode => 'kerberos'
});

if (!$result->{success}) {
    die "Connection failed: " . $result->{error} . "\n";
}

my $conn_id = $result->{result}->{connection_id};
print "✅ Connected: $conn_id\n\n";

# Query 1: SELECT user FROM dual (matching POC)
print "Query 1: SELECT user FROM dual\n";
my $user_result = $bridge->call_python('database', 'execute_immediate', {
    connection_id => $conn_id,
    sql => 'SELECT user FROM dual'
});

if ($user_result->{success}) {
    print "✅ Logged in as: [result from query]\n\n";
} else {
    print "❌ Query failed\n\n";
}

# Query 2: SELECT COUNT(*) FROM ACQUIRER (matching POC)
print "Query 2: SELECT COUNT(*) FROM ACQUIRER\n";
my $count_result = $bridge->call_python('database', 'execute_immediate', {
    connection_id => $conn_id,
    sql => 'SELECT COUNT(*) FROM ACQUIRER'
});

if ($count_result->{success}) {
    print "✅ ACQUIRER count: [result from query]\n\n";
} else {
    print "❌ Query failed\n\n";
}

# Cleanup
$bridge->call_python('database', 'disconnect', {
    connection_id => $conn_id
});

print "=== Test Complete ===\n";
```

## Implementation Checklist

### Phase 1: Core Kerberos Support
- [ ] Add `threading` import
- [ ] Add `_ORACLE_THICK_CLIENT_INITIALIZED` global variables
- [ ] Implement `_ensure_oracle_thick_client()` function
- [ ] Implement `_validate_kerberos_environment()` function
- [ ] Implement `_connect_oracle_kerberos()` function (matches POC)

### Phase 2: Integration
- [ ] Update `connect()` function signature (add `auth_mode` parameter)
- [ ] Add auto-detection logic (empty credentials = Kerberos)
- [ ] Add routing to `_connect_oracle_kerberos()`
- [ ] Update connection metadata storage (include `auth_mode`)

### Phase 3: Persistence
- [ ] Update `_save_connection_metadata()` (add `auth_mode` parameter)
- [ ] Update `_restore_connection_from_metadata()` (handle Kerberos restore)

### Phase 4: Testing
- [ ] Test environment validation
- [ ] Test thick client initialization
- [ ] Test POC replication
- [ ] Test password authentication still works
- [ ] Test daemon mode with Kerberos

## Key Differences from Generic Plan

### What's Different (Based on POC):

1. **Environment Variables Required**
   - POC explicitly validates `KRB5_CONFIG` and `KRB5CCNAME`
   - We add validation function matching POC logic

2. **Thick Client Required**
   - POC calls `oracledb.init_oracle_client()` explicitly
   - We add global initialization with thread safety

3. **DSN Format**
   - POC uses simple format: `host:port/service_name`
   - We parse DSN but ensure it produces same format

4. **No Username Parameter**
   - POC doesn't pass username to `oracledb.connect()`
   - We only use `externalauth=True`

### What's Unchanged (Good to Keep):

1. **Connection Pooling** - Still maintain connection IDs
2. **Metadata Storage** - Still persist connections
3. **Error Handling** - Enhanced with POC-specific checks
4. **Daemon Mode** - Thick client init happens once globally

## Estimated Effort

- **Phase 1 (Core Functions):** 2-3 hours
- **Phase 2 (Integration):** 2-3 hours
- **Phase 3 (Persistence):** 1-2 hours
- **Phase 4 (Testing):** 2-3 hours
- **Total:** 7-11 hours

## Next Steps

1. Review this plan and approve changes
2. Implement Phase 1 (core functions)
3. Implement Phase 2 (integration)
4. Test with your POC environment
5. Validate all queries work like POC
6. Deploy to production

---

*Implementation Plan Version: 2.0 (POC-Based)*
*Created: 2025-09-29*
*Based on validated POC script*
*Estimated Effort: 7-11 hours*