#!/usr/bin/perl

# debug_oracle_test.pl - Debug Oracle connection and data retrieval



use strict;

use warnings;

use FindBin;

use lib "$FindBin::Bin/..";



use DBIHelper;



# Enable debugging

$DBIHelper::DEBUG_LEVEL = 2;



my $dsn = $ARGV[0] || "dbi:Oracle:localhost:1521/XEPDB1";

my $username = $ARGV[1] || "test_user";

my $password = $ARGV[2] || "test_password";



print "=== DEBUG Oracle Test ===\n";

print "DSN: $dsn\n";

print "User: $username\n\n";



# Test connection

my %attr = (RaiseError => 1, AutoCommit => 1, PrintError => 1);

my $dbh = DBIHelper->connect($dsn, $username, $password, \%attr);



if (!$dbh || $dbh == 1) {

    print "FAILED: Connection failed\n";

    exit 1;

}



# Enable debugging on the connection

$dbh->{debug} = 1;



print "SUCCESS: Connected to Oracle\n\n";



# Test simple query with debug output

print "=== Testing Simple Oracle Query ===\n";

my $sql = "SELECT SYSDATE as current_date, USER as current_user FROM DUAL";

print "SQL: $sql\n\n";



my $sth = $dbh->prepare($sql);

if (!$sth) {

    print "FAILED: Prepare failed: " . $dbh->errstr . "\n";

    exit 1;

}



print "SUCCESS: Statement prepared\n";



# Execute with debug

my $result = $sth->execute();

print "Execute result: " . (defined $result ? $result : 'undef') . "\n";



# Check metadata immediately after execute

print "\n=== Column Metadata Check ===\n";

print "NUM_OF_FIELDS: " . ($sth->{NUM_OF_FIELDS} || 'undef') . "\n";

print "NAME: " . (ref($sth->{NAME}) ? "[" . join(", ", @{$sth->{NAME}}) . "]" : 'undef') . "\n";

print "NAME_uc: " . (ref($sth->{NAME_uc}) ? "[" . join(", ", @{$sth->{NAME_uc}}) . "]" : 'undef') . "\n";



# Try to fetch data

print "\n=== Data Fetch Test ===\n";

my @row = $sth->fetchrow_array();

print "fetchrow_array returned " . scalar(@row) . " values\n";

if (@row) {

    print "Data: [" . join(", ", map { defined $_ ? "'$_'" : 'NULL' } @row) . "]\n";

} else {

    print "No data returned\n";

}



# Test alternative query

print "\n=== Testing Alternative Query ===\n";

$sth = $dbh->prepare("SELECT 1 as test_col FROM DUAL");

$sth->execute();

print "Alternative query metadata:\n";

print "NUM_OF_FIELDS: " . ($sth->{NUM_OF_FIELDS} || 'undef') . "\n";

print "NAME: " . (ref($sth->{NAME}) ? "[" . join(", ", @{$sth->{NAME}}) . "]" : 'undef') . "\n";



@row = $sth->fetchrow_array();

if (@row) {

    print "Alternative query data: [" . join(", ", map { defined $_ ? "'$_'" : 'NULL' } @row) . "]\n";

} else {

    print "Alternative query: No data returned\n";

}



$dbh->disconnect();

print "\n=== Debug Test Complete ===\n";

