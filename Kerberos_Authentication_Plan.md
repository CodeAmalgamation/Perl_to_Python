# Kerberos Authentication Implementation Plan

## Overview
This document outlines the implementation plan to add Kerberos authentication support for Oracle database connections in the database.py helper module. This will enable secure, passwordless authentication using Kerberos tickets for enterprise environments.

## Current State Analysis

### What We Have ✅
- Username/password authentication via `oracledb.connect()`
- TNS-based connection strings
- Connection pooling and persistence
- Transaction management
- Multiple DSN format support

### What's Missing ❌
- Kerberos (GSSAPI) authentication

## Kerberos Authentication Overview

### What is Kerberos?
Kerberos is a network authentication protocol that uses tickets to allow nodes to prove their identity securely. In Oracle context:
- **No password needed** - uses Kerberos ticket from system
- **Single Sign-On (SSO)** - authenticate once, access multiple services
- **Enterprise standard** - widely used in corporate environments
- **Secure** - encrypted tickets, mutual authentication

### How Oracle Uses Kerberos
1. User authenticates to Kerberos KDC (Key Distribution Center)
2. User receives Kerberos ticket (TGT - Ticket Granting Ticket)
3. When connecting to Oracle, client requests service ticket
4. Oracle validates ticket with KDC
5. Connection established without password

## Implementation Strategy

### Phase 1: Basic Kerberos Support (Core Functionality)
**Goal:** Enable Kerberos authentication for Oracle connections

**Changes Required:**
1. Detect Kerberos authentication requests
2. Configure `oracledb` for external authentication
3. Handle connection without username/password
4. Test with Kerberos-enabled Oracle database

### Phase 2: Enhanced Kerberos Features (Optional)
**Goal:** Add advanced Kerberos capabilities

**Potential Enhancements:**
1. Kerberos keytab file support
2. Cross-realm authentication
3. Kerberos ticket refresh
4. Multiple authentication fallback
5. Kerberos credential caching


## Detailed Implementation Plan

### Step 1: Update Connection Function Signature

**File:** `database.py` - `connect()` function (line 284)

**Current Signature:**
```python
def connect(dsn: str, username: str = '', password: str = '',
            options: Dict = None, db_type: str = '') -> Dict[str, Any]:
```

**Enhanced Signature:**
```python
def connect(dsn: str, username: str = '', password: str = '',
            options: Dict = None, db_type: str = '',
            auth_mode: str = 'password') -> Dict[str, Any]:
    """
    Connect to Oracle database with multiple authentication modes

    Args:
        dsn: Database connection string
        username: Username (optional for Kerberos)
        password: Password (not used for Kerberos)
        options: Connection options dict
        db_type: Database type ('oracle', etc.)
        auth_mode: Authentication mode - 'password' or 'kerberos'

    Returns:
        Dict with connection_id or error
    """
```

### Step 2: Add Kerberos Detection Logic

**Location:** Early in `connect()` function

**New Code:**
```python
def connect(dsn: str, username: str = '', password: str = '',
            options: Dict = None, db_type: str = '',
            auth_mode: str = 'password') -> Dict[str, Any]:
    """Connect to Oracle database with multiple authentication modes"""
    try:
        connection_id = str(uuid.uuid4())

        # Determine authentication mode
        actual_auth_mode = auth_mode

        # Auto-detect Kerberos if username/password are empty
        if not password and not username:
            actual_auth_mode = 'kerberos'

        # Handle Oracle TNS-in-username pattern
        actual_username = username
        if '@' in username:
            actual_username, tns_name = username.split('@', 1)
            if dsn in ['dbi:Oracle:', 'dbi:Oracle', 'dbi:Ora:', 'dbi:Ora']:
                dsn = tns_name

        # Parse connection details
        connection_params = _parse_oracle_dsn(dsn)

        # Route to appropriate authentication method
        if actual_auth_mode == 'kerberos':
            conn = _connect_oracle_kerberos(connection_params, actual_username, options)
        else:  # password (default)
            conn = _connect_oracle(connection_params, actual_username, password, options)

        # ... rest of connection storage logic
```

### Step 3: Implement Kerberos Connection Function

**New Function:**
```python
def _connect_oracle_kerberos(connection_params: Dict[str, str],
                             username: str = '',
                             options: Dict = None) -> Any:
    """
    Connect to Oracle database using Kerberos authentication

    Requires:
    - Valid Kerberos ticket (kinit must have been run)
    - Oracle database configured for Kerberos
    - Proper sqlnet.ora configuration

    Args:
        connection_params: Parsed DSN parameters
        username: Optional username (can be empty for Kerberos)
        options: Connection options

    Returns:
        Oracle connection object

    Raises:
        RuntimeError: If Kerberos authentication fails
    """
    # Build connection string
    if 'service_name' in connection_params:
        connect_string = f"{connection_params.get('host', 'localhost')}:{connection_params.get('port', 1521)}/{connection_params['service_name']}"
    elif 'sid' in connection_params:
        connect_string = f"{connection_params.get('host', 'localhost')}:{connection_params.get('port', 1521)}/{connection_params['sid']}"
    elif 'tns' in connection_params:
        connect_string = connection_params['tns']
    else:
        connect_string = f"localhost:1521/XE"

    try:
        # For Kerberos, use external authentication mode
        # The oracledb driver supports external authentication when user/password are not provided
        # or when using specific authentication modes

        # Method 1: Use externalauth parameter (preferred for oracledb)
        conn = oracledb.connect(
            dsn=connect_string,
            externalauth=True  # Enable external (Kerberos/OS) authentication
        )

        return conn

    except Exception as e:
        # Provide helpful error messages for common Kerberos issues
        error_msg = str(e).lower()

        if 'ora-01017' in error_msg or 'invalid username/password' in error_msg:
            raise RuntimeError(
                "Kerberos authentication failed - ORA-01017. "
                "Possible causes:\n"
                "1. No valid Kerberos ticket (run 'kinit username@REALM')\n"
                "2. Oracle database not configured for Kerberos\n"
                "3. sqlnet.ora missing AUTHENTICATION_SERVICES=(KERBEROS5)\n"
                "4. Service principal not registered in Kerberos"
            )
        elif 'ora-12641' in error_msg:
            raise RuntimeError(
                "Kerberos authentication failed - ORA-12641 (Authentication service not initialized). "
                "Check sqlnet.ora configuration for AUTHENTICATION_SERVICES=(KERBEROS5)"
            )
        elif 'ora-12649' in error_msg:
            raise RuntimeError(
                "Kerberos authentication failed - ORA-12649 (Unknown encryption/checksum type). "
                "Kerberos ticket encryption type may not be supported by Oracle"
            )
        else:
            raise RuntimeError(f"Kerberos authentication failed: {str(e)}")
```

### Step 4: Add Kerberos Utility Functions

**New Utilities:**
```python
def check_kerberos_ticket() -> Dict[str, Any]:
    """
    Check if a valid Kerberos ticket exists

    Returns:
        Dict with ticket status and principal information
    """
    import subprocess

    try:
        # Run klist to check for valid tickets
        result = subprocess.run(['klist'],
                              capture_output=True,
                              text=True,
                              timeout=5)

        if result.returncode == 0:
            # Parse klist output to get principal and expiration
            output = result.stdout

            # Look for principal (usually first line after header)
            principal = None
            for line in output.split('\n'):
                if 'Default principal:' in line or 'Principal:' in line:
                    principal = line.split(':', 1)[1].strip()
                    break

            return {
                'success': True,
                'has_ticket': True,
                'principal': principal,
                'details': output
            }
        else:
            return {
                'success': True,
                'has_ticket': False,
                'error': 'No Kerberos ticket found',
                'details': result.stderr
            }

    except FileNotFoundError:
        return {
            'success': False,
            'error': 'Kerberos tools not available (klist command not found)',
            'has_ticket': False
        }
    except Exception as e:
        return {
            'success': False,
            'error': f'Failed to check Kerberos ticket: {str(e)}',
            'has_ticket': False
        }


def refresh_kerberos_ticket(principal: str = None, keytab: str = None) -> Dict[str, Any]:
    """
    Refresh Kerberos ticket using kinit

    Args:
        principal: Kerberos principal (user@REALM)
        keytab: Path to keytab file (optional)

    Returns:
        Dict with success status
    """
    import subprocess

    try:
        if keytab and principal:
            # Use keytab for non-interactive renewal
            result = subprocess.run(
                ['kinit', '-k', '-t', keytab, principal],
                capture_output=True,
                text=True,
                timeout=10
            )
        elif principal:
            # Interactive kinit (may require password prompt)
            result = subprocess.run(
                ['kinit', principal],
                capture_output=True,
                text=True,
                timeout=30
            )
        else:
            return {
                'success': False,
                'error': 'Principal required for ticket refresh'
            }

        if result.returncode == 0:
            return {
                'success': True,
                'message': 'Kerberos ticket refreshed successfully',
                'principal': principal
            }
        else:
            return {
                'success': False,
                'error': f'Failed to refresh Kerberos ticket: {result.stderr}'
            }

    except FileNotFoundError:
        return {
            'success': False,
            'error': 'Kerberos tools not available (kinit command not found)'
        }
    except Exception as e:
        return {
            'success': False,
            'error': f'Failed to refresh Kerberos ticket: {str(e)}'
        }
```

### Step 5: Update Metadata Storage for Auth Mode

**Update:** `_save_connection_metadata()` function

**Modified Code:**
```python
def _save_connection_metadata(connection_id: str, metadata: Dict[str, Any],
                              password: str = '', auth_mode: str = 'password'):
    """Save connection metadata to persistent storage"""
    try:
        _ensure_persistence_dir()
        metadata_file = os.path.join(_PERSISTENCE_DIR, f"{connection_id}.json")

        # Store connection metadata including encrypted password (if any)
        persistent_metadata = {
            'connection_id': connection_id,
            'type': metadata.get('type'),
            'dsn': metadata.get('dsn'),
            'username': metadata.get('username'),
            'password': _simple_encrypt(password) if password and auth_mode == 'password' else '',
            'auth_mode': auth_mode,  # NEW: Store authentication mode
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

### Step 6: Update Connection Restoration for Kerberos

**Update:** `_restore_connection_from_metadata()` function

**Modified Code:**
```python
def _restore_connection_from_metadata(metadata: Dict[str, Any]) -> Optional[Any]:
    """Restore Oracle connection from metadata"""
    try:
        # Recreate the Oracle connection using stored metadata
        connection_params = _parse_oracle_dsn(metadata['dsn'])
        auth_mode = metadata.get('auth_mode', 'password')

        # Restore based on authentication mode
        if auth_mode == 'kerberos':
            # For Kerberos, no password needed - use current ticket
            conn = _connect_oracle_kerberos(connection_params, metadata['username'])
        else:  # password (default)
            # Decrypt stored password
            password = _simple_decrypt(metadata.get('password', ''))

            # Re-establish Oracle connection
            options = {
                'AutoCommit': metadata.get('autocommit', True),
                'RaiseError': metadata.get('raise_error', False),
                'PrintError': metadata.get('print_error', True)
            }
            conn = _connect_oracle(connection_params, metadata['username'], password, options)

        return conn

    except Exception as e:
        # If connection restoration fails, the metadata is stale
        return None
```

## Perl API Usage Examples

### Example 1: Basic Kerberos Authentication
```perl
#!/usr/bin/perl
use strict;
use warnings;
use lib '.';
use CPANBridge;

$CPANBridge::DAEMON_MODE = 1;

my $bridge = CPANBridge->new();

# Connect using Kerberos (no password needed)
my $result = $bridge->call_python('database', 'connect', {
    dsn => 'dbi:Oracle:host=dbserver;service_name=ORCL',
    username => 'myuser',  # Or empty for ticket principal
    password => '',
    auth_mode => 'kerberos'
});

if ($result->{success}) {
    my $conn_id = $result->{result}->{connection_id};
    print "Connected via Kerberos: $conn_id\n";

    # Use connection normally...
} else {
    print "Connection failed: " . $result->{error} . "\n";
}
```

### Example 2: Auto-Detection of Kerberos
```perl
# Empty password triggers Kerberos detection
my $result = $bridge->call_python('database', 'connect', {
    dsn => 'mydb',
    username => '',  # Empty username = use Kerberos ticket principal
    password => ''   # Empty password = Kerberos mode
});
```

### Example 3: Check Kerberos Ticket Before Connection
```perl
# Check if Kerberos ticket exists
my $ticket_check = $bridge->call_python('database', 'check_kerberos_ticket', {});

if ($ticket_check->{result}->{has_ticket}) {
    print "Kerberos ticket found for: " .
          $ticket_check->{result}->{principal} . "\n";

    # Connect using Kerberos
    my $result = $bridge->call_python('database', 'connect', {
        dsn => 'mydb',
        auth_mode => 'kerberos'
    });
} else {
    print "No Kerberos ticket found. Run kinit first.\n";
}
```


## Environment Configuration

### Oracle Client Configuration (sqlnet.ora)

**Required for Kerberos:**
```ini
# Enable Kerberos authentication
NAMES.DIRECTORY_PATH = (TNSNAMES, EZCONNECT)
SQLNET.AUTHENTICATION_SERVICES = (KERBEROS5, NONE)

# Kerberos parameters
SQLNET.KERBEROS5_CONF = /etc/krb5.conf
SQLNET.KERBEROS5_KEYTAB = /path/to/keytab
SQLNET.KERBEROS5_CONF_MIT = TRUE
SQLNET.KERBEROS5_CC_NAME = /tmp/krb5cc_1000

# Optional: Kerberos realm mapping
SQLNET.KERBEROS5_REALMS = /etc/krb5/krb5realms
```

### Kerberos Configuration (krb5.conf)

**Example:**
```ini
[libdefaults]
    default_realm = EXAMPLE.COM
    dns_lookup_realm = false
    dns_lookup_kdc = false
    ticket_lifetime = 24h
    forwardable = true

[realms]
    EXAMPLE.COM = {
        kdc = kdc.example.com
        admin_server = admin.example.com
    }

[domain_realm]
    .example.com = EXAMPLE.COM
    example.com = EXAMPLE.COM
```

### Oracle Database Configuration

**Create Kerberos-enabled user:**
```sql
-- Create user identified externally
CREATE USER myuser IDENTIFIED EXTERNALLY AS 'myuser@EXAMPLE.COM';
GRANT CONNECT, RESOURCE TO myuser;

-- Check Kerberos configuration
SELECT * FROM V$PARAMETER WHERE NAME LIKE '%kerberos%';
```

## Testing Strategy

### Unit Tests

**Test 1: Kerberos Connection (with valid ticket)**
```python
def test_kerberos_connection_with_ticket():
    # Prerequisite: valid Kerberos ticket (kinit)
    result = connect(
        dsn='test_db',
        username='',
        password='',
        auth_mode='kerberos'
    )
    assert result['success'] == True
```

**Test 2: Kerberos Connection (no ticket)**
```python
def test_kerberos_connection_without_ticket():
    # Clear Kerberos ticket first (kdestroy)
    result = connect(
        dsn='test_db',
        username='',
        password='',
        auth_mode='kerberos'
    )
    assert result['success'] == False
    assert 'kerberos' in result['error'].lower()
```

**Test 3: Ticket Status Check**
```python
def test_check_kerberos_ticket():
    result = check_kerberos_ticket()
    assert result['success'] == True
    assert 'has_ticket' in result
```

### Integration Tests

**Test Script:** `test_kerberos_db.pl`
```perl
#!/usr/bin/perl
use strict;
use warnings;
use lib '.';
use CPANBridge;

$CPANBridge::DAEMON_MODE = 1;

print "=== Kerberos Database Authentication Tests ===\n\n";

my $bridge = CPANBridge->new();

# Test 1: Check Kerberos ticket
print "Test 1: Checking Kerberos ticket status...\n";
my $ticket_check = $bridge->call_python('database', 'check_kerberos_ticket', {});
if ($ticket_check->{result}->{has_ticket}) {
    print "✅ Kerberos ticket found: " . $ticket_check->{result}->{principal} . "\n";
} else {
    print "❌ No Kerberos ticket found\n";
    print "Run: kinit your_username\@REALM\n";
    exit 1;
}

# Test 2: Connect via Kerberos
print "\nTest 2: Connecting via Kerberos...\n";
my $conn_result = $bridge->call_python('database', 'connect', {
    dsn => 'test_db',
    username => '',
    password => '',
    auth_mode => 'kerberos'
});

if ($conn_result->{success}) {
    print "✅ Kerberos connection successful\n";
    my $conn_id = $conn_result->{result}->{connection_id};

    # Test 3: Query database
    print "\nTest 3: Executing test query...\n";
    my $query_result = $bridge->call_python('database', 'execute_immediate', {
        connection_id => $conn_id,
        sql => 'SELECT USER FROM DUAL'
    });

    if ($query_result->{success}) {
        print "✅ Query executed successfully\n";
    } else {
        print "❌ Query failed: " . $query_result->{error} . "\n";
    }

    # Cleanup
    $bridge->call_python('database', 'disconnect', {
        connection_id => $conn_id
    });
} else {
    print "❌ Kerberos connection failed: " . $conn_result->{error} . "\n";
}

print "\n=== Tests Complete ===\n";
```

## Risk Assessment

### Low Risk Changes ✅
- Adding `auth_mode` parameter (default 'password')
- Adding Kerberos detection logic
- Adding utility functions (check_ticket, etc.)

### Medium Risk Changes ⚠️
- Modifying `_connect_oracle()` routing logic
- Updating metadata storage
- Connection restoration logic changes

### High Risk Changes 🔴
- Changing existing password authentication behavior
- Security implications of external authentication
- Kerberos ticket caching/refresh automation

## Security Considerations

### Kerberos Security Best Practices

1. **Ticket Lifetime**
   - Configure reasonable ticket lifetimes
   - Implement automatic ticket refresh
   - Handle ticket expiration gracefully

2. **Credential Storage**
   - Never store Kerberos passwords
   - Protect keytab files (chmod 600)
   - Use encrypted file systems for keytabs

3. **Connection Security**
   - Use encrypted connections (SSL/TLS)
   - Validate service principals
   - Monitor for authentication failures

4. **Audit Logging**
   - Log authentication attempts
   - Track connection source
   - Monitor for suspicious patterns

## Rollback Plan

### If Issues Arise:
1. **Disable Kerberos** - revert `auth_mode` to 'password' only
2. **Remove Kerberos functions** - comment out Kerberos-specific code
3. **Restore connection logic** - use original password-only authentication
4. **Git revert** to previous working state

### Rollback Triggers:
- Existing password authentication breaks
- Security vulnerabilities discovered
- Kerberos ticket handling causes connection leaks
- Performance degradation > 15%
- Cross-platform compatibility issues

## Success Criteria

### Phase 1 Success Metrics:
- ✅ Kerberos authentication works with valid ticket
- ✅ Graceful error handling for missing/expired tickets
- ✅ Existing password authentication unaffected
- ✅ Connection restoration works for Kerberos
- ✅ Works on Linux, macOS, Windows with Kerberos client
- ✅ Comprehensive error messages for troubleshooting

### Phase 2 Success Metrics (Future):
- ✅ Automatic ticket refresh
- ✅ Keytab file support for non-interactive auth
- ✅ Cross-realm authentication
- ✅ Multiple authentication method fallback

## Timeline Estimate

### Phase 1: Basic Kerberos Support
- **Research & Planning:** 2-3 hours
- **Implementation:** 4-6 hours
- **Testing:** 3-4 hours
- **Documentation:** 2 hours
- **Total:** 11-15 hours

### Phase 2: Enhanced Features (Optional)
- **Ticket refresh automation:** 3-4 hours
- **Keytab support:** 2-3 hours
- **Testing:** 2-3 hours
- **Total:** 7-10 hours

## Dependencies

### Required:
- Python `oracledb` library (already installed)
- Kerberos client tools (`kinit`, `klist`, `kdestroy`)
- Oracle database configured for Kerberos
- Valid Kerberos KDC setup

### Optional:
- MIT Kerberos or Heimdal Kerberos
- Oracle sqlnet.ora configuration
- Keytab files for automation
- Kerberos realm configuration

### Python Packages:
```bash
# Already have oracledb
pip install oracledb

# Optional: for advanced Kerberos handling
pip install gssapi  # Python GSSAPI bindings (optional)
```

## Next Steps

1. **Review and approve this implementation plan**
2. **Verify Oracle database Kerberos configuration**
3. **Test Kerberos client tools availability**
4. **Begin Phase 1 implementation**
5. **Create comprehensive test suite**
6. **Document Kerberos setup requirements**
7. **Update database helper documentation**

---

*Implementation Plan Version: 1.0*
*Created: 2025-09-29*
*Estimated Effort: 11-15 hours (Phase 1)*
*Priority: High (Enterprise Requirement)*