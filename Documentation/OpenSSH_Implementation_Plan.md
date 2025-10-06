# Net::OpenSSH Replacement Implementation Plan

## Overview
Create a Python-based replacement for Net::OpenSSH that provides SSH connectivity and file transfer capabilities compatible with existing Perl scripts.

## Current Usage Analysis

### Single Consumer
- **File**: `mi_ftp_unix_fw.pl`
- **Usage**: Conditional - used when `UseOpenSsh = 'y'`, otherwise uses Net::SFTP::Foreign
- **Purpose**: SSH-based file transfers

### Constructor Parameters
```perl
Net::OpenSSH->new(
    host     => $RemoteHost,
    user     => $RemoteUsername,
    port     => $SftpPort,          # default: 22
    timeout  => 30,
    password => $RemotePassword,     # OR
    key_path => $IdentityFile       # for key-based auth
)
```

## Required API Compatibility

### 1. Constructor: `new()`
**Perl Signature:**
```perl
my $ssh = Net::OpenSSH->new(%params);
```

**Parameters:**
- `host` - Remote hostname/IP (required)
- `user` - SSH username (required)
- `port` - SSH port (default: 22)
- `timeout` - Connection timeout in seconds
- `password` - Password for authentication
- `key_path` - Path to SSH private key file

**Return:** SSH connection object or undef on failure

### 2. Expected Methods (Standard Net::OpenSSH API)

Based on typical SFTP/file transfer usage:

#### File Transfer Methods
- `$ssh->scp_put($local_file, $remote_file)` - Upload file
- `$ssh->scp_get($remote_file, $local_file)` - Download file
- `$ssh->sftp()` - Get SFTP subsystem object

#### SFTP Methods (via $ssh->sftp)
- `$sftp->put($local, $remote)` - Upload via SFTP
- `$sftp->get($remote, $local)` - Download via SFTP
- `$sftp->ls($path)` - List directory
- `$sftp->mkdir($path)` - Create directory
- `$sftp->remove($path)` - Delete file
- `$sftp->stat($path)` - Get file stats

#### Command Execution
- `$ssh->system($command)` - Execute command
- `$ssh->capture($command)` - Execute and capture output

#### Connection Management
- `$ssh->error()` - Get last error message
- `$ssh->die_on_error()` - Enable auto-die on errors

## Implementation Architecture

### Component 1: Python SSH Backend (`python_helpers/helpers/openssh.py`)

**Technology:** `paramiko` library (industry-standard Python SSH)

**Functions:**
```python
def new(host, user, port=22, password=None, key_path=None, timeout=30)
    # Create SSH connection, return connection_id

def scp_put(connection_id, local_file, remote_file)
    # Upload file via SCP

def scp_get(connection_id, remote_file, local_file)
    # Download file via SCP

def sftp_put(connection_id, local_file, remote_file)
    # Upload file via SFTP

def sftp_get(connection_id, remote_file, local_file)
    # Download file via SFTP

def execute_command(connection_id, command)
    # Execute command and return output

def disconnect(connection_id)
    # Close SSH connection

def cleanup_connection(connection_id)
    # Cleanup resources
```

**State Management:**
- Global `SSH_CONNECTIONS` dict to store active connections
- Connection IDs using UUID
- Persistent connections in daemon mode

### Component 2: Perl Wrapper (`OpenSSHHelper.pm`)

**Provides drop-in Net::OpenSSH compatibility:**

```perl
package OpenSSHHelper;
use base 'CPANBridge';

sub new {
    my ($class, %args) = @_;
    # Call Python openssh.new()
    # Return blessed object with connection_id
}

sub scp_put {
    my ($self, $local, $remote) = @_;
    # Call Python openssh.scp_put()
}

sub scp_get {
    my ($self, $local, $remote) = @_;
    # Call Python openssh.scp_get()
}

sub sftp {
    my $self = shift;
    # Return SFTP object wrapper
}

sub error {
    my $self = shift;
    return $self->{last_error};
}

# Compatibility namespace
package Net::OpenSSH;
sub new {
    shift;
    return OpenSSHHelper->new(@_);
}
```

### Component 3: SFTP Subobject (`OpenSSHHelper::SFTP`)

```perl
package OpenSSHHelper::SFTP;

sub new {
    my ($class, $ssh_obj) = @_;
    return bless { ssh => $ssh_obj }, $class;
}

sub put {
    my ($self, $local, $remote) = @_;
    # Call Python openssh.sftp_put()
}

sub get {
    my ($self, $remote, $local) = @_;
    # Call Python openssh.sftp_get()
}

# Additional SFTP methods as needed
```

## Migration Path

### For mi_ftp_unix_fw.pl:
```perl
# BEFORE:
use Net::OpenSSH;
my $ssh = Net::OpenSSH->new(%params);

# AFTER:
use OpenSSHHelper;  # Single line change
my $ssh = Net::OpenSSH->new(%params);  # Same API
```

## Testing Strategy

### Test Suite Components:

1. **Connection Tests**
   - Password authentication
   - Key-based authentication
   - Connection timeout
   - Invalid credentials
   - Port specification

2. **File Transfer Tests**
   - SCP upload
   - SCP download
   - SFTP upload
   - SFTP download
   - Large file handling
   - Binary file integrity

3. **Error Handling Tests**
   - Connection failures
   - Authentication failures
   - File not found
   - Permission errors
   - Network timeouts

4. **Compatibility Tests**
   - Net::OpenSSH vs OpenSSHHelper behavior
   - Parameter compatibility
   - Error message compatibility

## Dependencies

### Python Requirements:
```
paramiko>=2.7.0     # SSH/SFTP functionality
cryptography>=3.0   # Required by paramiko
```

### Installation:
```bash
pip install paramiko cryptography
```

## Security Considerations

1. **Key Management**
   - Support for SSH key files
   - Proper key permissions checking
   - No key caching in memory

2. **Password Handling**
   - Secure password transmission
   - No password logging
   - Clear passwords from memory after use

3. **Connection Security**
   - Host key verification (optional)
   - Timeout enforcement
   - Secure channel encryption

## Implementation Phases

### Phase 1: Core SSH Connection
- Python openssh.py with new() and disconnect()
- OpenSSHHelper.pm with constructor
- Basic connection test

### Phase 2: File Transfer
- SCP put/get methods
- SFTP put/get methods
- File transfer tests

### Phase 3: Advanced Features
- Command execution
- Directory operations
- Error handling enhancement

### Phase 4: Testing & Validation
- Comprehensive test suite
- Integration with mi_ftp_unix_fw.pl
- Performance testing

## Success Criteria

- ✅ Drop-in replacement for Net::OpenSSH
- ✅ All mi_ftp_unix_fw.pl functionality working
- ✅ Password and key-based authentication
- ✅ File upload/download working
- ✅ Error handling compatible
- ✅ Test coverage > 90%

## Notes

- **Daemon Mode Required**: SSH connections must persist across calls
- **Connection Pooling**: Reuse connections when possible
- **Resource Cleanup**: Proper connection cleanup on exit
- **Backward Compatible**: Existing scripts work without changes
