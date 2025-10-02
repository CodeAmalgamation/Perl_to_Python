#!/usr/bin/perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/..";
use DBIHelper;
use Data::Dumper;

print "=" x 80 . "\n";
print "DBIHelper Complete Test Suite - Kerberos Authentication\n";
print "=" x 80 . "\n\n";

# Configuration
my $dsn = "dbi:Oracle:host=<YOUR_HOST>;sid=<YOUR_SID>;port=<YOUR_PORT>";
my $username = "";  # Empty for Kerberos
my $password = "";  # Empty for Kerberos

# Placeholder query - CUSTOMIZE THIS
my $test_query = "SELECT * FROM your_table WHERE rownum <= 5";

print "Configuration:\n";
print "  DSN: $dsn\n";
print "  Auth: Kerberos (empty credentials)\n";
print "  Query: $test_query\n\n";

# Test 1: Connect to database
print "-" x 80 . "\n";
print "Test 1: Database Connection (Kerberos)\n";
print "-" x 80 . "\n";

my $dbh = DBIHelper->connect($dsn, $username, $password);

unless($dbh) {
    print "❌ FAILED: connect() returned error code: undefined\n";
    print "Error: Establishing connection. "\n";
    exit 1;
}

print "✅ PASSED: Connected successfully\n";
print "Connection ID: " . ($dbh->{connection_id} || "N/A") . "\n\n";

# Test 2: Prepare statement
print "-" x 80 . "\n";
print "Test 2: Prepare Statement\n";
print "-" x 80 . "\n";

my $sth = $dbh->prepare($test_query);

unless ($sth) {
    print "❌ FAILED: prepare() returned undef\n";
    print "Error: " . ($dbh->errstr() || "Unknown error") . "\n";
    exit 1;
}

print "✅ PASSED: Statement prepared successfully\n";
print "Statement ID: " . ($sth->{statement_id} || "N/A") . "\n\n";

# Test 3: Execute statement
print "-" x 80 . "\n";
print "Test 3: Execute Statement\n";
print "-" x 80 . "\n";

my $exec_result = $sth->execute();

unless (defined $exec_result) {
    print "❌ FAILED: execute() returned undef\n";
    print "Error: " . ($sth->errstr() || "Unknown error") . "\n";
    exit 1;
}

print "✅ PASSED: Statement executed successfully\n";
print "Rows affected: $exec_result\n";
print "Column count: " . ($sth->{NUM_OF_FIELDS} || 0) . "\n";
print "Column names: " . join(", ", @{$sth->{NAME} || []}) . "\n\n";

# Test 4: fetchrow_array
print "-" x 80 . "\n";
print "Test 4: fetchrow_array() - Fetch first row as array\n";
print "-" x 80 . "\n";

my @row = $sth->fetchrow_array();

if (@row) {
    print "✅ PASSED: fetchrow_array() returned data\n";
    print "Row data: " . join(" | ", map { defined $_ ? $_ : "NULL" } @row) . "\n\n";
} else {
    print "⚠️  WARNING: No rows returned (might be expected)\n\n";
}

# Test 5: Re-execute and fetchrow_arrayref
print "-" x 80 . "\n";
print "Test 5: fetchrow_arrayref() - Fetch row as array reference\n";
print "-" x 80 . "\n";

$sth->execute();
my $row_ref = $sth->fetchrow_arrayref();

if ($row_ref && ref($row_ref) eq 'ARRAY') {
    print "✅ PASSED: fetchrow_arrayref() returned array reference\n";
    print "Row data: " . join(" | ", map { defined $_ ? $_ : "NULL" } @$row_ref) . "\n\n";
} else {
    print "⚠️  WARNING: No rows returned (might be expected)\n\n";
}

# Test 6: Re-execute and fetchrow_hashref
print "-" x 80 . "\n";
print "Test 6: fetchrow_hashref() - Fetch row as hash reference\n";
print "-" x 80 . "\n";

$sth->execute();
my $hash_ref = $sth->fetchrow_hashref();

if ($hash_ref && ref($hash_ref) eq 'HASH') {
    print "✅ PASSED: fetchrow_hashref() returned hash reference\n";
    foreach my $col (sort keys %$hash_ref) {
        my $val = defined $hash_ref->{$col} ? $hash_ref->{$col} : "NULL";
        print "  $col: $val\n";
    }
    print "\n";
} else {
    print "⚠️  WARNING: No rows returned (might be expected)\n\n";
}

# Test 7: Re-execute and fetchall_arrayref
print "-" x 80 . "\n";
print "Test 7: fetchall_arrayref() - Fetch all rows\n";
print "-" x 80 . "\n";

$sth->execute();
my $all_rows = $sth->fetchall_arrayref();

if ($all_rows && ref($all_rows) eq 'ARRAY') {
    my $row_count = scalar @$all_rows;
    print "✅ PASSED: fetchall_arrayref() returned array reference\n";
    print "Total rows fetched: $row_count\n";

    if ($row_count > 0) {
        print "\nFirst row:\n";
        print "  " . join(" | ", map { defined $_ ? $_ : "NULL" } @{$all_rows->[0]}) . "\n";

        if ($row_count > 1) {
            print "\nLast row:\n";
            print "  " . join(" | ", map { defined $_ ? $_ : "NULL" } @{$all_rows->[-1]}) . "\n";
        }
    }
    print "\n";
} else {
    print "⚠️  WARNING: No rows returned (might be expected)\n\n";
}

# Test 8: do() method - Direct execution
print "-" x 80 . "\n";
print "Test 8: do() - Direct SQL execution (non-SELECT)\n";
print "-" x 80 . "\n";

# Safe test query that doesn't modify data
my $do_query = "SELECT COUNT(*) FROM dual";
my $do_result = $dbh->do($do_query);

if (defined $do_result) {
    print "✅ PASSED: do() executed successfully\n";
    print "Rows affected: $do_result\n\n";
} else {
    print "❌ FAILED: do() returned undef\n";
    print "Error: " . ($dbh->errstr() || "Unknown error") . "\n\n";
}

# Test 9: Bind parameters
print "-" x 80 . "\n";
print "Test 9: Bind Parameters with execute()\n";
print "-" x 80 . "\n";

# Modify this query for your use case
my $bind_query = "SELECT * FROM dual WHERE 1 = ?";
my $sth_bind = $dbh->prepare($bind_query);

if ($sth_bind) {
    my $bind_exec = $sth_bind->execute(1);

    if (defined $bind_exec) {
        print "✅ PASSED: Bind parameter execution successful\n";
        my @bind_row = $sth_bind->fetchrow_array();
        if (@bind_row) {
            print "Row data: " . join(" | ", map { defined $_ ? $_ : "NULL" } @bind_row) . "\n";
        }
        print "\n";
    } else {
        print "❌ FAILED: Bind parameter execution failed\n";
        print "Error: " . ($sth_bind->errstr() || "Unknown error") . "\n\n";
    }
} else {
    print "❌ FAILED: Could not prepare bind query\n\n";
}

# Test 10: Statement finish
print "-" x 80 . "\n";
print "Test 10: Statement finish()\n";
print "-" x 80 . "\n";

my $finish_result = $sth->finish();
print "✅ PASSED: Statement finished\n";
print "Result: " . (defined $finish_result ? $finish_result : "undef") . "\n\n";

# Test 11: Disconnect
print "-" x 80 . "\n";
print "Test 11: Database Disconnect\n";
print "-" x 80 . "\n";

my $disconnect_result = $dbh->disconnect();

if ($disconnect_result) {
    print "❌ FAILED: disconnect() returned error code: $disconnect_result\n";
    print "Error: " . ($dbh->errstr() || "Unknown error") . "\n";
} else {
    print "✅ PASSED: Disconnected successfully\n";
}

print "\n" . "=" x 80 . "\n";
print "Test Suite Completed\n";
print "=" x 80 . "\n";
