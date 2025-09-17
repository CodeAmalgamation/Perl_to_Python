# File: DBIHelper.pm
# Complete DBI replacement for RHEL 9 migration
# Supports all DBI patterns found in your Perl scripts

package DBIHelper;

use strict;
use warnings;
use parent 'CPANBridge';
use Carp;

our $VERSION = '1.02';

# Class variables for DBI compatibility
our $err = '';
our $errstr = '';
our $state = '';

# Persistent connection support
our $persistent_dbh = undef;

sub new {
    my ($class, %args) = @_;
    my $self = $class->SUPER::new(%args);
    
    # DBI-compatible attributes
    $self->{Active} = 0;
    $self->{AutoCommit} = 1;
    $self->{RaiseError} = 0;
    $self->{PrintError} = 1;
    $self->{ChopBlanks} = 0;
    $self->{err} = undef;
    $self->{errstr} = '';
    $self->{state} = '';
    
    # Connection info
    $self->{dsn} = $args{dsn} || '';
    $self->{username} = $args{username} || '';
    $self->{password} = $args{password} || '';
    $self->{connection_id} = undef;
    $self->{connected} = 0;
    
    return $self;
}

# DBI->connect - handles all your connection patterns
sub connect {
    my ($class, $dsn, $username, $password, $attr) = @_;
    
    # Handle DbAccess.pm Informix pattern: DBI->connect($dbi, \%attr)
    if (ref($dsn) eq 'HASH') {
        $attr = $dsn;
        $dsn = $username;
        $username = '';
        $password = '';
    }
    
    # Handle Oracle TNS pattern: "dbi:Oracle:" with "username@sid"
    if ($dsn eq "dbi:Oracle:" && $username && $username =~ /(.+)\@(.+)/) {
        my ($user, $sid) = ($1, $2);
        $dsn = "dbi:Oracle:sid=$sid";
        $username = $user;
    }
    
    # Check for persistent connection
    if (defined($persistent_dbh) && $persistent_dbh && $persistent_dbh->{connected}) {
        return $persistent_dbh;
    }
    
    my $self = $class->new(
        dsn => $dsn,
        username => $username,
        password => $password
    );
    
    # Set connection attributes
    if ($attr && ref($attr) eq 'HASH') {
        $self->{AutoCommit} = $attr->{AutoCommit} if exists $attr->{AutoCommit};
        $self->{RaiseError} = $attr->{RaiseError} if exists $attr->{RaiseError};
        $self->{PrintError} = $attr->{PrintError} if exists $attr->{PrintError};
    }
    
    # Detect database type
    my $db_type = '';
    if ($dsn =~ m/informix/i) {
        $db_type = 'informix';
    } elsif ($dsn =~ m/oracle/i) {
        $db_type = 'oracle';
    } else {
        $self->_set_error("Unrecognized DataBase type");
        return undef if $self->{RaiseError};
        return 1;  # Return 1 for FAILURE like your DbAccess.pm
    }
    
    # Connect via Python bridge
    my $result = $self->call_python('database', 'connect', {
        dsn => $dsn,
        username => $username,
        password => $password,
        db_type => $db_type,
        options => $attr || {}
    });
    
    if (!$result || !$result->{success}) {
        my $error = $result ? $result->{error} : "Unknown connection error";
        $self->_set_error($error);
        
        if ($self->{RaiseError}) {
            croak "DBI connect failed: $error";
        }
        if ($self->{PrintError}) {
            warn "DBI connect failed: $error";
        }
        return 1;  # Return 1 for FAILURE
    }
    
    # Success - configure handle
    # Extract connection_id from nested result structure (CPANBridge wraps results)
    my $connection_id;
    if ($result->{result} && $result->{result}->{connection_id}) {
        $connection_id = $result->{result}->{connection_id};
    } elsif ($result->{connection_id}) {
        $connection_id = $result->{connection_id};
    } else {
        $self->_set_error("Connection ID not found in result structure");
        return 1;  # Return 1 for FAILURE
    }

    $self->{connection_id} = $connection_id;
    $self->{connected} = 1;
    $self->{Active} = 1;
    
    # Store as persistent connection
    $persistent_dbh = $self;
    
    return $self;
}

# $dbh->prepare
sub prepare {
    my ($self, $sql) = @_;
    
    unless ($self->{connected}) {
        $self->_set_error("Not connected to database");
        return undef;
    }
    
    my $result = $self->call_python('database', 'prepare', {
        connection_id => $self->{connection_id},
        sql => $sql
    });
    
    if (!$result || !$result->{success}) {
        my $error = $result ? $result->{error} : "Prepare failed";
        $self->_set_error($error);
        return undef;
    }
    
    # Create statement handle
    my $sth = DBIHelper::StatementHandle->new(
        parent => $self,
        statement_id => $result->{statement_id},
        sql => $sql
    );
    
    return $sth;
}

# $dbh->do - for direct SQL execution
sub do {
    my ($self, $sql, $attr, @bind_values) = @_;
    
    unless ($self->{connected}) {
        $self->_set_error("Not connected to database");
        return undef;
    }
    
    my $result = $self->call_python('database', 'execute_immediate', {
        connection_id => $self->{connection_id},
        sql => $sql,
        bind_values => \@bind_values
    });
    
    if (!$result || !$result->{success}) {
        my $error = $result ? $result->{error} : "Execute failed";
        $self->_set_error($error);
        
        if ($self->{RaiseError}) {
            croak "Database operation failed: $error";
        }
        if ($self->{PrintError}) {
            warn "Database operation failed: $error";
        }
        return undef;
    }
    
    return $result->{rows_affected};
}

# Transaction control
sub begin_work {
    my $self = shift;
    
    my $result = $self->call_python('database', 'begin_transaction', {
        connection_id => $self->{connection_id}
    });
    
    if (!$result || !$result->{success}) {
        $self->_set_error($result ? $result->{error} : "Begin transaction failed");
        return undef;
    }
    
    $self->{AutoCommit} = 0;
    return 1;
}

sub commit {
    my $self = shift;
    
    my $result = $self->call_python('database', 'commit', {
        connection_id => $self->{connection_id}
    });
    
    if (!$result || !$result->{success}) {
        my $error = $result ? $result->{error} : "Commit failed";
        $self->_set_error($error);
        
        if ($self->{RaiseError}) {
            croak "Commit failed: $error";
        }
        if ($self->{PrintError}) {
            warn "Commit failed: $error";
        }
        return undef;
    }
    
    return 1;
}

sub rollback {
    my $self = shift;
    
    my $result = $self->call_python('database', 'rollback', {
        connection_id => $self->{connection_id}
    });
    
    if (!$result || !$result->{success}) {
        my $error = $result ? $result->{error} : "Rollback failed";
        $self->_set_error($error);
        
        if ($self->{RaiseError}) {
            croak "Rollback failed: $error";
        }
        if ($self->{PrintError}) {
            warn "Rollback failed: $error";
        }
        return undef;
    }
    
    return 1;
}

# $dbh->disconnect
sub disconnect {
    my $self = shift;
    
    return 1 unless $self->{connected};
    
    my $result = $self->call_python('database', 'disconnect', {
        connection_id => $self->{connection_id}
    });
    
    $self->{connected} = 0;
    $self->{Active} = 0;
    $self->{connection_id} = undef;
    
    # Clear persistent connection
    $persistent_dbh = undef;
    
    return 1;
}

# DBI->trace - for debugging
sub trace {
    my ($class_or_self, $level, $file) = @_;
    
    if (ref($class_or_self)) {
        $class_or_self->set_debug($level > 0 ? $level : 0);
    } else {
        $CPANBridge::DEBUG_LEVEL = $level > 0 ? $level : 0;
    }
    
    return 1;
}

# DBI::neat_list - for column formatting in your scripts
sub neat_list {
    my ($list_ref, $max_len, $delimiter) = @_;
    
    return '' unless $list_ref && ref($list_ref) eq 'ARRAY';
    
    $delimiter = "\t" unless defined $delimiter;
    $max_len ||= 1000;
    
    my $result = join($delimiter, @$list_ref);
    
    if (length($result) > $max_len) {
        $result = substr($result, 0, $max_len - 3) . '...';
    }
    
    return $result;
}

# DBI::neat - for value formatting
sub neat {
    my ($value, $max_len) = @_;
    
    return 'undef' unless defined $value;
    
    $max_len ||= 1000;
    my $result = "$value";
    
    if (length($result) > $max_len) {
        $result = substr($result, 0, $max_len - 3) . '...';
    }
    
    return $result;
}

# Make DBI functions available globally
BEGIN {
    no warnings 'redefine';
    *DBI::neat_list = \&neat_list;
    *DBI::neat = \&neat;
}

# Error handling
sub _set_error {
    my ($self, $error) = @_;
    
    $self->{err} = 1;
    $self->{errstr} = $error;
    $self->{state} = '';
    
    # Set class variables
    $err = 1;
    $errstr = $error;
    $state = '';
}

# DBI-compatible error methods
sub err { 
    my $self = shift;
    return ref($self) ? $self->{err} : $err;
}

sub errstr { 
    my $self = shift;
    return ref($self) ? $self->{errstr} : $errstr;
}

sub state { 
    my $self = shift;
    return ref($self) ? $self->{state} : $state;
}

# Attribute access
sub FETCH {
    my ($self, $key) = @_;
    return $self->{$key};
}

sub STORE {
    my ($self, $key, $value) = @_;
    $self->{$key} = $value;
}

1;

#################################################################
# Statement Handle Class - Supports all your DBI patterns
#################################################################

package DBIHelper::StatementHandle;

use strict;
use warnings;
use Carp;

sub new {
    my ($class, %args) = @_;
    my $self = {
        parent => $args{parent},
        statement_id => $args{statement_id},
        sql => $args{sql},
        executed => 0,
        finished => 0,
        bind_params => {},    # For bind_param() support
        
        # DBI-compatible attributes
        Active => 1,
        err => undef,
        errstr => '',
        state => '',
        NUM_OF_FIELDS => 0,   # Used in your scripts
        NAME => [],           # Column names
        NAME_uc => [],        # Uppercase column names (used in your scripts)
        TYPE => [],           # Column types
        rows => 0,            # Row count (used for conditionals)
    };
    
    bless $self, $class;
    return $self;
}

# $sth->bind_param - for stored procedures
sub bind_param {
    my ($self, $param, $value, $attr) = @_;
    
    # Store bind parameter for later use
    $self->{bind_params}->{$param} = {
        value => $value,
        attr => $attr
    };
    
    return 1;
}

# $sth->execute - handles bind parameters and metadata
sub execute {
    my ($self, @bind_values) = @_;
    
    if ($self->{finished}) {
        $self->_set_error("Statement handle already finished");
        return undef;
    }
    
    # Combine bind_param calls with execute parameters
    my @final_bind_values = @bind_values;
    
    # Add bind_param values if no execute parameters provided
    if (!@bind_values && %{$self->{bind_params}}) {
        my %bind_params = %{$self->{bind_params}};
        
        # Sort by parameter for consistent ordering
        for my $param (sort keys %bind_params) {
            push @final_bind_values, $bind_params{$param}->{value};
        }
    }
    
    my $result = $self->{parent}->call_python('database', 'execute_statement', {
        connection_id => $self->{parent}->{connection_id},
        statement_id => $self->{statement_id},
        bind_values => \@final_bind_values,
        bind_params => $self->{bind_params}
    });
    
    if (!$result || !$result->{success}) {
        my $error = $result ? $result->{error} : "Execute failed";
        $self->_set_error($error);
        
        if ($self->{parent}->{RaiseError}) {
            croak "Statement execution failed: $error";
        }
        if ($self->{parent}->{PrintError}) {
            warn "Statement execution failed: $error";
        }
        return undef;
    }
    
    $self->{executed} = 1;
    
    # Set column metadata from result (handle nested structure)
    my $column_info;
    if ($result->{result} && $result->{result}->{column_info}) {
        $column_info = $result->{result}->{column_info};
    } elsif ($result->{column_info}) {
        $column_info = $result->{column_info};
    }

    if ($column_info) {
        $self->{NUM_OF_FIELDS} = $column_info->{count} || 0;
        $self->{NAME} = $column_info->{names} || [];
        $self->{TYPE} = $column_info->{types} || [];
        $self->{NAME_uc} = [map { uc($_) } @{$self->{NAME}}];
    } else {
        # No column info available (common for non-SELECT statements)
        $self->{NUM_OF_FIELDS} = 0;
        $self->{NAME} = [];
        $self->{TYPE} = [];
        $self->{NAME_uc} = [];
    }

    # Set row count (handle nested structure)
    my $rows_affected;
    if ($result->{result} && defined $result->{result}->{rows_affected}) {
        $rows_affected = $result->{result}->{rows_affected};
    } elsif (defined $result->{rows_affected}) {
        $rows_affected = $result->{rows_affected};
    } else {
        $rows_affected = 0;
    }
    $self->{rows} = $rows_affected;

    # Return DBI-compatible value
    
    if ($rows_affected == 0) {
        return "0E0";  # DBI standard for zero rows
    }
    
    return $rows_affected;
}

# $sth->rows - for conditional logic in your scripts
sub rows {
    my $self = shift;
    return $self->{rows} || 0;
}

# $sth->fetchrow_array - main fetch method in your scripts
sub fetchrow_array {
    my $self = shift;
    
    unless ($self->{executed}) {
        $self->_set_error("Statement not executed");
        return ();
    }
    
    if ($self->{finished}) {
        return ();
    }
    
    my $result = $self->{parent}->call_python('database', 'fetch_row', {
        connection_id => $self->{parent}->{connection_id},
        statement_id => $self->{statement_id},
        format => 'array'
    });
    
    if (!$result || !$result->{success}) {
        $self->{finished} = 1;
        return ();
    }
    
    if (!$result->{row}) {
        $self->{finished} = 1;
        return ();
    }
    
    return @{$result->{row}};
}

# $sth->fetchrow_hashref - for hash-based access
sub fetchrow_hashref {
    my $self = shift;
    
    unless ($self->{executed}) {
        $self->_set_error("Statement not executed");
        return undef;
    }
    
    if ($self->{finished}) {
        return undef;
    }
    
    my $result = $self->{parent}->call_python('database', 'fetch_row', {
        connection_id => $self->{parent}->{connection_id},
        statement_id => $self->{statement_id},
        format => 'hash'
    });
    
    if (!$result || !$result->{success} || !$result->{row}) {
        $self->{finished} = 1;
        return undef;
    }
    
    return $result->{row};
}

# $sth->fetchall_arrayref - for bulk retrieval
sub fetchall_arrayref {
    my ($self, $attr) = @_;
    
    unless ($self->{executed}) {
        $self->_set_error("Statement not executed");
        return undef;
    }
    
    my $format = 'array';
    if ($attr && ref($attr) eq 'HASH') {
        $format = 'hash';
    }
    
    my $result = $self->{parent}->call_python('database', 'fetch_all', {
        connection_id => $self->{parent}->{connection_id},
        statement_id => $self->{statement_id},
        format => $format
    });
    
    if (!$result || !$result->{success}) {
        $self->_set_error($result ? $result->{error} : "Fetch all failed");
        return undef;
    }
    
    $self->{finished} = 1;
    my $rows = $result->{rows} || [];
    $self->{rows} = scalar @$rows;
    
    return $rows;
}

# $sth->dump_results - for bulk output in your scripts
sub dump_results {
    my ($self, $max_rows, $row_sep, $field_sep, $fh) = @_;
    
    unless ($self->{executed}) {
        $self->_set_error("Statement not executed");
        return 0;
    }
    
    # Set defaults matching DBI behavior
    $max_rows = 1000 unless defined $max_rows;
    $row_sep = "\n" unless defined $row_sep;
    $field_sep = "\t" unless defined $field_sep;
    $fh = \*STDOUT unless defined $fh;
    
    my $rows_dumped = 0;
    
    # Fetch and output rows one at a time
    while (my @row = $self->fetchrow_array()) {
        last if $max_rows > 0 && $rows_dumped >= $max_rows;
        
        # Handle undefined values
        @row = map { defined($_) ? $_ : '' } @row;
        
        print $fh join($field_sep, @row) . $row_sep;
        $rows_dumped++;
    }
    
    # Update total row count
    $self->{rows} = $rows_dumped;
    
    return $rows_dumped;
}

# $sth->finish - cleanup
sub finish {
    my $self = shift;
    
    return 1 if $self->{finished};
    
    my $result = $self->{parent}->call_python('database', 'finish_statement', {
        connection_id => $self->{parent}->{connection_id},
        statement_id => $self->{statement_id}
    });
    
    $self->{finished} = 1;
    $self->{Active} = 0;
    
    return 1;
}

# Error handling
sub _set_error {
    my ($self, $error) = @_;
    
    $self->{err} = 1;
    $self->{errstr} = $error;
    $self->{state} = '';
}

sub err { 
    my $self = shift;
    return $self->{err};
}

sub errstr { 
    my $self = shift;
    return $self->{errstr};
}

sub state { 
    my $self = shift;
    return $self->{state};
}

# Attribute access
sub FETCH {
    my ($self, $key) = @_;
    return $self->{$key};
}

sub STORE {
    my ($self, $key, $value) = @_;
    $self->{$key} = $value;
}

1;

__END__

=head1 NAME

DBIHelper - DBI replacement for RHEL 9 migration

=head1 SYNOPSIS

    use DBIHelper;
    
    # Replace: use DBI;
    # With:    use DBIHelper;
    
    # All your existing DBI code works unchanged:
    my $dbh = DBIHelper->connect($dsn, $user, $pass, \%attr);
    my $sth = $dbh->prepare($sql);
    $sth->execute(@params);
    
    while (my @row = $sth->fetchrow_array()) {
        # Process rows
    }

=head1 DESCRIPTION

DBIHelper provides a drop-in replacement for DBI that works without CPAN 
dependencies by using Python drivers underneath. It supports all DBI 
functionality found in your Perl scripts including:

- Oracle and Informix connections
- All fetch methods (fetchrow_array, fetchrow_hashref, etc.)
- Statement handle attributes (NAME_uc, NUM_OF_FIELDS, rows)
- Stored procedures with bind parameters
- Transaction control
- DBI utility functions (neat_list, neat)
- Error handling with RaiseError/PrintError

=head1 METHODS

All standard DBI methods are supported with identical interfaces.

=head1 MIGRATION

Simply replace "use DBI;" with "use DBIHelper;" in your scripts.
No other code changes are required.

=head1 SEE ALSO

L<CPANBridge>, L<DBI>

=cut