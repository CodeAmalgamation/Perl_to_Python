# Net::FTP Usage Analysis Report



## Executive Summary



After analyzing all Perl files (*.pl and *.pm) in the project, I found **Net::FTP usage in 4 files** with comprehensive FTP functionality including connection management, file transfers, directory operations, and error handling.



### Key Findings:

- **4 files use Net::FTP**

- **15+ different FTP methods used**

- **Mixed FTP/SFTP implementations** (hybrid approach)

- **Comprehensive error handling** with fallback mechanisms

- **Both simple and complex usage patterns**



## Files Using Net::FTP



| File | Import Line | Usage Type | Complexity |

|------|-------------|------------|------------|

| `CommonControlmSubs.pm` | 370 | Helper Function | **Simple** |

| `mi_common_controlm_subs.pm` | 283 | Helper Function | **Simple** |

| `mi_ftp_stratus_files.pl` | 65 | Full Implementation | **Complex** |

| `https://lnkd.in/eRauN5Tz` | 93 | Full Implementation | **Complex** |



## Detailed Usage Analysis



### 1. CommonControlmSubs.pm & mi_common_controlm_subs.pm



**Purpose**: Simple FTP file retrieval helper function (identical implementations)



**Constructor Pattern**:

```perl

$ftp = Net::FTP->new( $server, Debug => 1 );

```



**Method Usage**:

```perl

# Authentication

$ftp->login( $login, $password )



# Directory operations  

$ftp->cwd( $directory )



# File transfer

$ftp->get( $file )



# Connection cleanup

$ftp->quit()

```



**Error Handling Pattern**:

```perl

if ( $ftp == NULL ) {

  &log_msg( "Could not connect to server.\n" );

  $myrc = 9;

}



if ( $ftp->login( $login, $password ) ) {

  # Success path

} else {

  &log_msg( "Could not login with user: [$login] and password: [$password].\n" );

  $myrc = 7;

}

```


**Complexity Assessment**: **SIMPLE**

- Basic get-only operations

- Simple error codes (4, 6, 7, 9)

- No advanced features



### 2. mi_ftp_stratus_files.pl



**Purpose**: Comprehensive FTP/SFTP file transfer with Stratus system integration



**Constructor Patterns**:

```perl

# Net::FTP with comprehensive options

$ftp = Net::FTP->new($dns_server, Debug => 0, Timeout => 30 )

  or $MsgBuffer .= "ftp_transfer(): Cannot connect to $dns_server:\n $@" and die ;



# SFTP alternative (conditional)

if ($^O =~ m/linux/i) {

  require Net::SFTP::Foreign;

}

```



**Authentication**:

```perl

$ftp->login( $user, $password )

  or $MsgBuffer .= "ftp_transfer(): User [$user] cannot login to [$dns_server]. " .

    $ftp->message . "\n" and die ;

```



**Directory Operations**:

```perl

# Change directory with error handling

if ( ! $ftp->cwd( $remote_location ) ) {

  $MsgBuffer .= "ftp_transfer(): Cannot change remote directory to [$remote_location]" .

    "on server [$dns_server]. " . $ftp->message . "\n" ;

  die ;

}



# SFTP directory operations

$ftp->setcwd( $remote_location ) # SFTP version

```



**Transfer Mode Configuration**:

```perl

# Binary mode setting

if ($Opt{XferMode} =~ /binary/) {

  if ( ! $ftp->binary ) {

    $MsgBuffer = "Cannot set Transfer mode to [$Opt{XferMode}]\n".

      $ftp->message . "\n" ;

    die ;

  }

}

```



**File Transfer Operations**:

```perl

# GET operations with SFTP options

if ( $Opt{UseSftp} ) {

  my %sftp_get_options = $Opt{SftpGetOption} ? %{$Opt{SftpGetOption}} : ();

  $sftp_get_options{perm} = oct( $sftp_get_options{perm} ) if( $sftp_get_options{perm} );

  $sftp_get_options{umask} = oct( $sftp_get_options{umask} ) if( $sftp_get_options{umask} );

  $ftp->get( $remote_file, $local_file, %sftp_get_options )

} else {

  $ftp->get( $remote_file, $local_file )

}



# PUT operations with error recovery

if( $Opt{UseSftp} ) {

  my %sftp_put_options = $Opt{SftpPutOption} ? %{$Opt{SftpPutOption}} : ();

  eval { $ftp->put( $local_file, $remote_file, %sftp_put_options ) or die } ;

} else {

  eval { $ftp->put( $local_file, $remote_file ) or die } ;

}



# Failed transfer cleanup

if ( $@ ) {

  if ( $Opt{UseSftp} ) {

    $ftp->remove( $remote_file ) ; # SFTP delete

  } else {

    $ftp->delete( $remote_file ) ; # FTP delete

  }

}

```



**File Operations**:

```perl

# File renaming with completion suffix

$ftp->rename( $remote_file, $remote_file . $Opt{CmpltSuf} )



# Local file completion marking

move( $local_file, $local_file . $Opt{CmpltSuf} )

```



**Connection Management**:

```perl

# Cleanup with protocol detection

if ( $Opt{UseSftp} ) {

  undef $ftp if( defined $ftp );

} else {

  $ftp->quit() if( defined $ftp ) ;

}

```



**Complexity Assessment**: **COMPLEX**

- Hybrid FTP/SFTP implementation

- Advanced error recovery

- Transfer mode management

- File completion tracking

- RPC integration



### 3. https://lnkd.in/eRauN5Tz



**Purpose**: Enterprise file movement with comprehensive FTP and SFTP support



**Constructor Pattern**:

```perl

$ftp=Net::FTP->new($rHost,Debug=>0,Timeout=>60)or die "Could not create connection to $rHost : $@\n";

```



**Authentication**:

```perl

$ftp->login("$rUser","$rPass") or die "Cannot login to $rHost\n", $ftp->message;

```



**Transfer Format Setting**:

```perl

# Dynamic format setting (binary/ascii)

$ftp->$format or die "Issue with changing format to $format.\n", $ftp->message;

```



**Directory Operations**:

```perl

# Directory change with validation

@ftp_list = $ftp->cwd("$rDir") or die "Could not change to working directory $rDir\n", $ftp->message;



# Present working directory check

my $pwd_path = $ftp->pwd() or die "pwd failed: " ,$ftp->message;

print "Present Working Directory is $pwd_path\n" ;



# Directory listing

@ftp_list = $ftp->dir("$rFile");

```


**File Transfer Patterns**:

```perl

# Simple put operation

$ftp->put("$lFqFile","$rFile") or die "Could not put $lFqFile as $rFile\n", $ftp->message;



# Put with temporary filename and rename (atomic operation)

$ftp->put("$lFqFile","$tLFile") or die "Could not put $lFqFile as $tLFile\n", $ftp->message;

$ftp->rename("$tLFile","$rFile") or die "Could not rename $tLFile as $rFile\n", $ftp->message;

```



**Advanced File Operations**:

```perl

# File rename operations

$ftp->rename("$tLFile","$rFile") or die "Could not rename $tLFile as $rFile\n", $ftp->message;



# Directory listing with verification

@ftp_list = $ftp->dir("$rFile");

print "Directory listing of $rFile on $rHost\n" ;

foreach(@ftp_list){print "$_\n" ; }

```



**Connection Cleanup**:

```perl

$ftp->quit;

```



**Complexity Assessment**: **COMPLEX**

- Multiple transfer patterns

- Atomic file operations (temp + rename)

- Directory validation

- Comprehensive error handling



## Method Usage Statistics



### Constructor Usage

| Constructor Pattern | Files | Options Used |

|-------------------|-------|--------------|

| `Net::FTP->new($host, Debug => 1)` | 2 | Debug enabled |

| `Net::FTP->new($host, Debug => 0, Timeout => 30)` | 1 | Debug off, 30s timeout |

| `Net::FTP->new($host, Debug => 0, Timeout => 60)` | 1 | Debug off, 60s timeout |



### Method Usage Frequency

| Method | Usage Count | Files | Purpose |

|--------|-------------|-------|---------|

| `login()` | 4 | All | Authentication |

| `put()` | 10+ | 2 | File upload |

| `get()` | 4+ | 2 | File download |

| `cwd()` | 6+ | 3 | Directory change |

| `quit()` | 4 | All | Connection close |

| `message()` | 12+ | All | Error messages |

| `rename()` | 4+ | 2 | File renaming |

| `delete()` | 2 | 1 | File deletion |

| `dir()` | 4+ | 1 | Directory listing |

| `pwd()` | 1 | 1 | Current directory |

| `binary()` | 1 | 1 | Transfer mode |



## Connection Patterns Analysis



### Authentication Methods

```perl

# Standard username/password

$ftp->login( $user, $password )



# Password retrieval from function

$rPass = &GETPASS($rUser,$rHost);

$ftp->login("$rUser","$rPass")

```


### Connection Options Used

| Option | Usage | Purpose |

|--------|-------|---------|

| `Debug => 0` | Most common | Production mode |

| `Debug => 1` | Helper functions | Debug mode |

| `Timeout => 30` | File transfer | 30 second timeout |

| `Timeout => 60` | File movement | 60 second timeout |



### Transfer Mode Configuration

```perl

# Binary mode (most common)

$ftp->binary()



# Dynamic format setting

$ftp->$format # where $format = "binary" or "ascii"

```



## Error Handling Patterns



### 1. **Simple Boolean Checks**:

```perl

$ftp->login( $login, $password ) or die "Cannot login to $rHost\n", $ftp->message;

```



### 2. **Conditional Error Handling**:

```perl

if ( ! $ftp->cwd( $directory ) ) {

  &log_msg( "Could not change directory to $directory\n" );

  $myrc = 6;

  last FTPGETBLOCK;

}

```



### 3. **Exception-Based Handling**:

```perl

eval { $ftp->put( $local_file, $remote_file ) or die } ;

if ( $@ ) {

  $MsgBuffer .= "ERROR: ftp_put_file(): PUT failed for [$local_file]. " . $@ . "\n" ;

  $rc = $FAILURE ;

}

```



### 4. **Message Extraction**:

```perl

# FTP error messages

$ftp->message . "\n"



# SFTP error messages (hybrid approach)

$ftp->error . "\n"

```



## Special Requirements & Edge Cases



### 1. **Hybrid FTP/SFTP Support**

```perl

if ( $Opt{UseSftp} ) {

  $ftp->get( $remote_file, $local_file, %sftp_get_options )

} else {

  $ftp->get( $remote_file, $local_file )

}

```



### 2. **File Permissions (SFTP)**

```perl

# Convert permissions to octal

$sftp_get_options{perm} = oct( $sftp_get_options{perm} ) if( $sftp_get_options{perm} );

$sftp_get_options{umask} = oct( $sftp_get_options{umask} ) if( $sftp_get_options{umask} );

```



### 3. **Atomic File Operations**

```perl

# Upload to temporary name, then rename (atomic)

$ftp->put("$lFqFile","$tLFile")

$ftp->rename("$tLFile","$rFile")

```


### 4. **File Completion Tracking**

```perl

# Add completion suffix to indicate successful transfer

$ftp->rename( $remote_file, $remote_file . $Opt{CmpltSuf} )

move( $local_file, $local_file . $Opt{CmpltSuf} )

```



### 5. **Transfer Recovery**

```perl

# Clean up failed transfers

if ( $@ ) {

  if ( $Opt{UseSftp} ) {

    $ftp->remove( $remote_file ) ;

  } else {

    $ftp->delete( $remote_file ) ;

  }

}

```



## Python ftplib Compatibility Matrix



| Net::FTP Method | Usage Count | Options/Context | Python ftplib Equivalent | Notes |

|-----------------|-------------|-----------------|---------------------------|--------|

| `new($host, %opts)` | 4 | Debug, Timeout | `FTP(host, timeout=timeout)` | Constructor options differ |

| `login($user, $pass)` | 4 | Standard auth | `login(user, passwd)` | Direct equivalent |

| `cwd($dir)` | 6+ | Directory change | `cwd(pathname)` | Direct equivalent |

| `pwd()` | 1 | Current directory | `pwd()` | Direct equivalent |

| `get($remote, $local)` | 4+ | Download | `retrbinary('RETR '+filename, file.write)` | More complex in Python |

| `put($local, $remote)` | 10+ | Upload | `storbinary('STOR '+filename, file)` | More complex in Python |

| `delete($file)` | 2 | File deletion | `delete(filename)` | Direct equivalent |

| `rename($old, $new)` | 4+ | File rename | `rename(fromname, toname)` | Direct equivalent |

| `dir($path)` | 4+ | Directory listing | `nlst(argument)` or `retrlines('LIST')` | Multiple options |

| `binary()` | 1 | Transfer mode | Built into retrbinary/storbinary | Different approach |

| `message()` | 12+ | Error messages | `lastresp` attribute | Different access pattern |

| `quit()` | 4 | Close connection | `quit()` | Direct equivalent |



## Implementation Recommendations



### 1. **Python Migration Strategy**



**Option A: Direct ftplib Translation**

```python

import ftplib



# Constructor

ftp = ftplib.FTP(host, timeout=30)



# Authentication  

ftp.login(user, password)



# File upload

with open(local_file, 'rb') as f:

  ftp.storbinary(f'STOR {remote_file}', f)



# File download

with open(local_file, 'wb') as f:

  ftp.retrbinary(f'RETR {remote_file}', f.write)



# Directory operations

ftp.cwd(remote_dir)

files = ftp.nlst()



# Cleanup

ftp.quit()

```


**Option B: Enhanced Python Implementation**

```python

import ftplib

import os

from contextlib import contextmanager



class FTPClient:

  def __init__(self, host, debug=False, timeout=30):

    self.ftp = ftplib.FTP(host, timeout=timeout)

    if debug:

      self.ftp.set_debuglevel(2)

   

  def login(self, user, password):

    return self.ftp.login(user, password)

   

  def put_file(self, local_file, remote_file, binary=True):

    with open(local_file, 'rb' if binary else 'r') as f:

      if binary:

        return self.ftp.storbinary(f'STOR {remote_file}', f)

      else:

        return self.ftp.storlines(f'STOR {remote_file}', f)

   

  def get_file(self, remote_file, local_file, binary=True):

    with open(local_file, 'wb' if binary else 'w') as f:

      if binary:

        return self.ftp.retrbinary(f'RETR {remote_file}', f.write)

      else:

        return self.ftp.retrlines(f'RETR {remote_file}', f.write)

   

  def message(self):

    return self.ftp.lastresp

```



### 2. **Hybrid FTP/SFTP Python Implementation**

```python

import ftplib

import paramiko

from contextlib import contextmanager



class UnifiedFileTransfer:

  def __init__(self, host, use_sftp=False, **kwargs):

    self.use_sftp = use_sftp

    if use_sftp:

      self.client = paramiko.SSHClient()

      self.client.set_missing_host_key_policy(paramiko.AutoAddPolicy())

      self.client.connect(host, **kwargs)

      self.ftp = self.client.open_sftp()

    else:

      self.ftp = ftplib.FTP(host, **kwargs)

   

  def get(self, remote_file, local_file, **options):

    if self.use_sftp:

      return self.ftp.get(remote_file, local_file, **options)

    else:

      with open(local_file, 'wb') as f:

        return self.ftp.retrbinary(f'RETR {remote_file}', f.write)

```



### 3. **Migration Complexity by File**



| File | Migration Effort | Key Challenges |

|------|------------------|----------------|

| `CommonControlmSubs.pm` | **LOW** | Simple get operation |

| `mi_common_controlm_subs.pm` | **LOW** | Identical to above |

| `mi_ftp_stratus_files.pl` | **HIGH** | Hybrid FTP/SFTP, complex options |

| `https://lnkd.in/eRauN5Tz` | **MEDIUM-HIGH** | Complex operations, atomic transfers |



### 4. **Critical Migration Considerations**



1. **Error Handling Translation**:

  - Perl: `$ftp->message` → Python: `ftp.lastresp`

  - Exception handling patterns differ significantly



2. **Transfer Mode Management**:

  - Perl: Explicit `$ftp->binary()` calls

  - Python: Built into `retrbinary()` vs `retrlines()`



3. **Hybrid Protocol Support**:

  - Current code switches between Net::FTP and Net::SFTP::Foreign

  - Python needs separate libraries: `ftplib` + `paramiko`



4. **Atomic Operations**:

  - Temp file + rename pattern needs careful preservation

  - File completion suffix logic must be maintained



5. **Connection Management**:

  - Perl uses simple `quit()` calls

  - Python benefits from context managers for cleanup



## Risk Assessment



### **HIGH RISK AREAS**:

1. **Hybrid FTP/SFTP Logic** in `mi_ftp_stratus_files.pl`

2. **Atomic File Operations** in `https://lnkd.in/eRauN5Tz`

3. **Error Message Dependencies** across all files

4. **File Completion Tracking** mechanisms



### **MEDIUM RISK AREAS**:

1. **Transfer Mode Configuration** (binary/ascii)

2. **Directory Operation Sequencing**

3. **Timeout and Connection Management**



### **LOW RISK AREAS**:

1. **Simple Helper Functions** (CommonControlmSubs.pm)

2. **Basic Login/Logout Operations**

3. **Standard File Transfer Operations**



## Conclusion



Your Net::FTP usage spans from simple helper functions to complex enterprise file transfer systems with hybrid FTP/SFTP support. The migration to Python will require:



1. **Careful preservation** of hybrid protocol logic

2. **Enhanced error handling** to match Perl's message patterns  

3. **Atomic operation guarantees** for enterprise file transfers

4. **Comprehensive testing** of file completion tracking mechanisms



**Estimated Migration Timeline**:

- Simple functions: 1-2 days each

- Complex implementations: 2-3 weeks each

- Testing and validation: 1-2 weeks total



**Total Project Effort**: 4-6 weeks with thorough testing and validation.