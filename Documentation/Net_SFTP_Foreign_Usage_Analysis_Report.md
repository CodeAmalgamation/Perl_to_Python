# Net::SFTP::Foreign Usage Analysis Report



## Executive Summary

Found 6 Perl files using Net::SFTP::Foreign for secure file transfers to Stratus mainframe systems and Unix/Linux hosts. All implementations use SSH key-based authentication with consistent patterns for financial data processing.



## Files Analyzed

1. `e_oh_n_elec_rpt.pl` - Electronic reporting for merchants

2. `mi_ftp_stratus_files.pl` - Generic SFTP/FTP transfer utility

3. `mi_ftp_stratus_rpc_fw.pl` - File watcher with SFTP + RPC

4. `mi_ftp_unix_fw.pl` - Unix/Linux file transfer watcher

5. `https://lnkd.in/eRauN5Tz` - Server-to-server file moving

6. `https://lnkd.in/eeResEHf` - PDE-specific SFTP + RPC watcher



## Detailed Analysis by File



### 1. e_oh_n_elec_rpt.pl

**Import Pattern:**

```perl

use Net::SFTP::Foreign;

```



**Connection Pattern:**

```perl

my %sftp_opts = ();

$sftp_opts{user} = $user;

$sftp_opts{port} = 295; # Hardcoded Stratus port

$sftp_opts{more} = [ -i => $identity_file, '-v'];

$sftp_opts{timeout} = 30;



$sftp = Net::SFTP::Foreign->new($remote_host, %sftp_opts);

```



**Authentication:**

- SSH key-based only (identity_file)

- No password authentication

- Port 295 hardcoded for Stratus



**Operations Used:**

- `setcwd()` - Change remote directory

- `put()` - Upload report files

- `rename()` - Add 'p' prefix for Stratus processing

- `error` - Error checking after each operation



**Error Handling:**

```perl

if( $sftp->error ) {

  job_msg("ABORTING: Unable to login to $remote_host");

  job_msg("Error msg: " . $sftp->error);

  $rc = 1;

}

```



**File Patterns:**

- Source: `/eprod/ecp/` or `/eprod/legacy_reports/npc/`

- Destination: `/$env/npc` or `/$env/data/fe_funnel`

- Naming: `noc_elec.yymmdd.yymmdd.<member>`, `yymmdd.<member>.cb1`



### 2. mi_ftp_stratus_files.pl

**Import Pattern:**

```perl

if ($^O =~ m/linux/i) {

  require Net::SFTP::Foreign; # Conditional loading on Linux only

}

```



**Connection Pattern:**

```perl

my %sftp_config = $Opt{SftpConnOption} ? %{$Opt{SftpConnOption}} : ();

my @sftp_more  = $Opt{SftpMoreOption} ? @{$Opt{SftpMoreOption}} : ();

push(@sftp_more, -i => $identity_File);

$sftp_config{host} = $dns_server;

$sftp_config{user} = $user;

$sftp_config{port} = $sftp_port;

$sftp_config{more} = \@sftp_more;

$sftp_config{timeout} = 30; # Default timeout



$ftp = Net::SFTP::Foreign->new(%sftp_config);

```



**Authentication:**

- SSH key-based (identity_file)

- Configurable through command line options

- Supports additional SSH options via SftpMoreOption



**Operations Used:**

- `setcwd()` - Change directory

- `get()` - Download files with options

- `put()` - Upload files with options

- `error` - Error retrieval



**Advanced Features:**

```perl

# Permission handling for get/put operations

my %sftp_get_options = $Opt{SftpGetOption} ? %{$Opt{SftpGetOption}} : ();

$sftp_get_options{perm} = oct($sftp_get_options{perm}) if($sftp_get_options{perm});

$sftp_get_options{umask} = oct($sftp_get_options{umask}) if($sftp_get_options{umask});

```



**File Patterns:**

- Flexible source/destination through parameters

- Pattern matching for LocalPutFilePattern

- Path conversion: `>prod>fx` → `/prod/fx`



### 3. mi_ftp_stratus_rpc_fw.pl

**Connection Pattern:**

```perl

$ftp = Net::SFTP::Foreign->new(

  host => $RemoteHost,

  user => $StratusSftpUsername,

  timeout => 30,

  port => $StratusSftpPort,

  more => [-i => $SftpIdentityFile, '-v']

);

```



**Failover Implementation:**

```perl

# Primary connection attempt

if ($ftp->error) {

  if ($RemoteHostFailOverEnable) {

    $ftp = Net::SFTP::Foreign->new(

      host => $RemoteHostFailOver,

      user => $StratusSftpUsername,

      timeout => 30,

      port => $StratusSftpPort,

      more => [-i => $SftpIdentityFile, '-v']

    );

  }

}

```


**Operations Used:**

- `put()` - File uploads with retry logic

- `rename()` - File renaming after upload

- `remove()` - Cleanup on failure

- `error` - Comprehensive error checking



**Retry Logic:**

```perl

for ($ftpCnt = 0; $ftpCnt < $FtpAttempts; $ftpCnt++) {

  eval { $ftp->put($ProcessFile, $RemoteFile, %sftp_put_options) or die };

  if ($@) {

    sleep $FtpWait if (($ftpCnt + 1) < $FtpAttempts);

  } else {

    last;

  }

}

```



### 4-6. Other Files (mi_ftp_unix_fw.pl, https://lnkd.in/eRauN5Tz, https://lnkd.in/eeResEHf)

These files follow similar patterns with variations in:

- Connection parameters (different config sections)

- File processing workflows

- Error handling specifics

- Integration with different business processes



## Common Usage Patterns Across All Files



### 1. Import Patterns

- **Standard**: `use Net::SFTP::Foreign;`

- **Conditional**: `require Net::SFTP::Foreign;` (Linux-only)

- **No specific imports**: Always uses default exports



### 2. Connection Patterns

- **SSH Key Authentication**: Universal across all files

- **No Password Auth**: No files use password-based authentication

- **Timeout**: Consistently 30 seconds

- **Verbose Mode**: `-v` flag commonly used

- **Port Configuration**: Configurable, default varies by target system



### 3. Authentication Methods

- **SSH Key Only**: All files use identity_file parameter

- **No Agent Forwarding**: Not implemented in any file

- **No Known Hosts**: Handling not explicitly implemented

- **Error Handling**: Consistent $sftp->error pattern



### 4. File Transfer Operations

**PUT Operations (Upload):**

```perl

$ftp->put($local_file, $remote_file, %options);

```

- Used in 5/6 files

- Options include permissions (perm, umask)

- Retry logic in 2/6 files



**GET Operations (Download):**

```perl

$ftp->get($remote_file, $local_file, %options);

```

- Used in 2/6 files

- Less common than PUT operations



### 5. File/Directory Operations

- **setcwd()**: Universal for directory changes

- **rename()**: Used in 3/6 files for post-transfer processing

- **remove()**: Used in 2/6 files for cleanup

- **No mkdir/rmdir**: Not used in any files

- **No ls/stat**: Directory listing not implemented



### 6. Error Handling Patterns

```perl

if ($sftp->error) {

  # Log error and take action

  $gLogger->info("Error: " . $sftp->error);

  # Either continue or die based on ContinueOnFail setting

}

```

- **Consistent**: All files use $sftp->error

- **No die_on_error**: Option not used

- **Custom handling**: Each file implements specific error responses



m handling**: Each file implements specific error responses



### 7. Connection Cleanup

```perl

undef $ftp if(defined $ftp); # Universal pattern

```

- **No explicit disconnect()**: All files use undef

- **Automatic cleanup**: Relies on object destruction



### 8. Performance Patterns

- **No buffer sizes**: Not configured in any file

- **No compression**: Not implemented

- **No concurrent transfers**: Single-threaded operations

- **Default block sizes**: No custom configurations



### 9. Data Flow Patterns

**Sources:**

- File watchers monitoring directories

- Report generation systems

- Scheduled batch processes



**Destinations:**

- Stratus mainframe systems (primary use case)

- Unix/Linux servers

- Payment processing systems



**File Naming:**

- Date-based naming (yymmdd format)

- Merchant/account number inclusion

- Extension-based type identification (.cb1, .rej, .cbv)



## Summary Table



| File | Connection Method | Auth Type | Operations Used | Error Handling | File Patterns | Notes |

|------|-------------------|-----------|-----------------|----------------|---------------|-------|

| e_oh_n_elec_rpt.pl | Hash options | SSH Key | put, setcwd, rename | $sftp->error | Report files (noc_elec, cb_*) | Port 295 hardcoded |

| mi_ftp_stratus_files.pl | Hash config | SSH Key | get, put, setcwd | $sftp->error + eval | Flexible patterns | Conditional Linux loading |

| mi_ftp_stratus_rpc_fw.pl | Named params | SSH Key | put, rename, remove | $sftp->error | File watcher patterns | Failover support |

| mi_ftp_unix_fw.pl | Hash params | SSH Key | put, get, setcwd | $sftp->error | Unix/Linux transfers | Multi-host support |

| https://lnkd.in/eRauN5Tz | Array args | SSH Key | put, setcwd | $sftp->error | Server migration | Simple transfer |

| https://lnkd.in/eeResEHf | Named params | SSH Key | put, rename, remove | $sftp->error | PDE processing | Identical to #3 |



## Key Findings



1. **Consistent Architecture**: All files follow similar SFTP usage patterns

2. **SSH Key Only**: No password authentication anywhere in codebase  

3. **Stratus-Centric**: Primary use case is transfers to Stratus mainframe

4. **Financial Focus**: All transfers relate to payment/chargeback processing

5. **Production Ready**: Comprehensive error handling and retry logic

6. **No Advanced Features**: Limited use of SFTP advanced capabilities



This analysis provides a complete inventory of Net::SFTP::Foreign usage as it exists in the current production codebase.