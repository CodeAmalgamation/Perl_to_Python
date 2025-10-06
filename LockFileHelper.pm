# File: LockFileHelper.pm
package LockFileHelper;

use strict;
use warnings;
use CPANBridge;
use Carp;

our $VERSION = '1.00';

# LockFile::Simple replacement using Python backend
use base 'CPANBridge';

sub make {
    my ($class, %args) = @_;

    # Handle case where make() is called on an object instead of a class
    $class = ref($class) || $class;

    my $self = $class->SUPER::new();

    # Process LockFile::Simple style arguments
    my $nfs = $args{'-nfs'} || $args{'nfs'} || 0;
    my $hold = $args{'-hold'} || $args{'hold'} || 90;
    my $max_age = $args{'-max_age'} || $args{'max_age'};
    my $delay = $args{'-delay'} || $args{'delay'} || 1;
    my $max_wait = $args{'-max_wait'} || $args{'max_wait'};

    # Store configuration
    $self->{config} = {
        nfs => $nfs,
        hold => $hold,
        max_age => $max_age,
        delay => $delay,
        max_wait => $max_wait
    };

    # Create lock manager via Python backend
    my $params = {
        nfs => $nfs ? 1 : 0,
        hold => $hold
    };

    # Add optional parameters
    if (defined $max_age) {
        $params->{max_age} = $max_age;
    }
    if (defined $delay) {
        $params->{delay} = $delay;
    }
    if (defined $max_wait) {
        $params->{max_wait} = $max_wait;
    }

    my $result = $self->call_python('lockfile', 'make', $params);

    if (!$result->{success}) {
        croak "Failed to create lock manager: " . ($result->{error} || 'unknown error');
    }

    $self->{manager_id} = $result->{result}->{manager_id};
    $self->{last_error} = undef;

    return $self;
}

sub trylock {
    my ($self, $filename, $lockfile_pattern) = @_;

    croak "Filename required for trylock" unless defined $filename;
    croak "Lock manager not initialized" unless $self->{manager_id};

    my $params = {
        manager_id => $self->{manager_id},
        filename => $filename
    };

    # Add lockfile pattern if specified
    if (defined $lockfile_pattern) {
        $params->{lockfile_pattern} = $lockfile_pattern;
    }

    my $result = $self->call_python('lockfile', 'trylock', $params);

    if (!$result->{success}) {
        # Set $! to simulate system error (matches LockFile::Simple behavior)
        my $error = $result->{error} || 'Lock acquisition failed';
        $! = $error;
        $self->{last_error} = $error;
        return undef;
    }

    $self->{last_error} = undef;

    # Create lock object that can be released
    my $lock = LockFileHelper::Lock->new(
        bridge => $self,
        lock_id => $result->{result}->{lock_id},
        filename => $result->{result}->{filename},
        lockfile => $result->{result}->{lockfile}
    );

    return $lock;
}

sub error {
    my $self = shift;
    return $self->{last_error};
}

# Cleanup on destruction
sub DESTROY {
    my $self = shift;

    if ($self->{manager_id}) {
        # Cleanup lock manager in Python backend
        $self->call_python('lockfile', 'cleanup_manager', {
            manager_id => $self->{manager_id}
        });
    }
}

# Lock object returned by trylock()
package LockFileHelper::Lock;

use strict;
use warnings;
use Carp;

sub new {
    my ($class, %args) = @_;

    my $self = {
        bridge => $args{bridge},
        lock_id => $args{lock_id},
        filename => $args{filename},
        lockfile => $args{lockfile},
        released => 0
    };

    return bless $self, $class;
}

sub release {
    my $self = shift;

    return 1 if $self->{released};  # Already released

    croak "Lock not initialized" unless $self->{lock_id};

    my $result = $self->{bridge}->call_python('lockfile', 'release', {
        lock_id => $self->{lock_id}
    });

    if (!$result->{success}) {
        croak "Failed to release lock: " . ($result->{error} || 'unknown error');
    }

    $self->{released} = 1;
    return $result->{result}->{released};
}

sub filename {
    my $self = shift;
    return $self->{filename};
}

sub lockfile {
    my $self = shift;
    return $self->{lockfile};
}

# Auto-release on destruction
sub DESTROY {
    my $self = shift;

    if (!$self->{released} && $self->{lock_id}) {
        eval {
            $self->release();
        };
    }
}

# Compatibility namespace for LockFile::Simple
package LockFile::Simple;

use strict;
use warnings;

sub make {
    shift;  # Remove class name
    return LockFileHelper->make(@_);
}

1;

__END__

=head1 NAME

LockFileHelper - LockFile::Simple replacement using Python file locking backend

=head1 SYNOPSIS

    # Drop-in replacement for LockFile::Simple
    use LockFileHelper;

    # Your existing NfsLock pattern works unchanged:
    use LockFile::Simple qw(lock trylock unlock);

    $lockmgr = LockFile::Simple->make(-nfs => 1, -hold => 90);

    if ($lock = $lockmgr->trylock($work_file, "$self->{lockFile}")) {
        print "File $work_file locked\n";
        # ... do work ...
        $lock->release();
    } else {
        print "Couldn't lock file $work_file because $!\n";
    }

    # Alternative direct usage:
    use LockFileHelper;

    my $lockmgr = LockFileHelper->make(-nfs => 1, -hold => 90);
    my $lock = $lockmgr->trylock('myfile.txt', '/tmp/%F.lock');
    if ($lock) {
        # ... do work ...
        $lock->release();
    }

=head1 DESCRIPTION

LockFileHelper provides a drop-in replacement for LockFile::Simple by routing
file locking operations through a Python backend that uses atomic file operations.

Supports all patterns from your NfsLock.pm usage:
- NFS-safe locking with -nfs => 1
- Stale lock detection and cleanup with -hold => 90 seconds
- Non-blocking trylock() for single attempt locking
- %F token replacement in lock file patterns
- Proper $! error variable setting
- Lock object with release() method

=head1 METHODS

=head2 make(%args)

Create new lock manager instance. Supports LockFile::Simple parameters:

    -nfs => 1           # Enable NFS-safe locking
    -hold => 90         # Lock becomes stale after 90 seconds
    -max_age => 90      # Deprecated alias for -hold
    -delay => 1         # Retry delay (not used in non-blocking mode)
    -max_wait => undef  # Maximum wait time (undef = don't wait)

Returns: LockFileHelper object (lock manager)

=head2 trylock($filename, $lockfile_pattern)

Attempt to acquire lock (non-blocking). Matches LockFile::Simple->trylock().

    $filename: File to lock (used for %F replacement)
    $lockfile_pattern: Lock file pattern (e.g., "/tmp/%F.lock")

Returns: Lock object on success, undef on failure
Sets $! to error message on failure

=head2 error()

Get last error message (compatibility method).

=head1 LOCK OBJECT METHODS

The lock object returned by trylock() supports:

=head2 release()

Release the acquired lock. Removes lock file.

Returns: 1 on success, croaks on failure

=head2 filename()

Get the filename that was locked.

=head2 lockfile()

Get the path to the lock file.

=head1 NFS LOCK COMPATIBILITY

Perfect compatibility with NfsLock.pm usage patterns:

    # From NfsLock.pm
    use LockFile::Simple qw(lock trylock unlock);
    $lockmgr = LockFile::Simple->make(-nfs => 1, -hold => 90);

    # Lock file pattern with %F token
    $self->{lockFile} = "$ENV{DATADIR}/out_files/%F.lock";

    # Acquire lock
    if ($self->{lock} = $lockmgr->trylock($work_file, "$self->{lockFile}")) {
        print "File $work_file locked\n";
        $retCode = 1;
    } else {
        print "Couldn't lock file $work_file because $!\n";
    }

    # Release lock
    eval {
        if ($self->{lock}) {
            $retCode = $self->{lock}->release;
        }
    };
    if ($@) {
        print "Unable to unlock file:\n$@\n";
    }

Simply change "use LockFile::Simple" to "use LockFileHelper" - no other changes needed!

=head1 LOCK FILE PATTERNS

Supports %F token replacement:

    Pattern: "$ENV{DATADIR}/out_files/%F.lock"
    File: "data123.txt"
    Result: "$ENV{DATADIR}/out_files/data123.txt.lock"

Environment variables are expanded automatically.

=head1 STALE LOCK HANDLING

Locks become stale after hold time (default: 90 seconds):
- Prevents permanent deadlocks from crashed processes
- Automatically removes stale locks before creating new ones
- Based on lock file modification time

=head1 ERROR HANDLING

Matches LockFile::Simple behavior:
- trylock() returns undef on failure
- Sets $! to error message
- release() croaks on failure
- Can be wrapped in eval {} for exception handling

=head1 NFS SAFETY

When -nfs => 1 is specified:
- Uses O_CREAT | O_EXCL for atomic lock file creation
- Checks for stale locks before failing
- Writes PID to lock file for debugging

=head1 MIGRATION

Change only the use statement:
- Replace 'use LockFile::Simple;' with 'use LockFileHelper;'

All existing NfsLock code works without modification.

=head1 DEPENDENCIES

Python backend requires standard library only (no external dependencies).

=head1 SEE ALSO

L<CPANBridge>, L<LockFile::Simple>

=cut
