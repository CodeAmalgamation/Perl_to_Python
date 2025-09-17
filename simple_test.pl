#!/usr/bin/perl
# Simple test without debug mode to avoid JSON conflicts

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin";

use DBIHelper;

print "=== Simple Test (No Debug) ===\n";

# Test connection
my $dsn = $ARGV[0] || "dbi:Oracle:host=localhost;port=1521;service_name=XE";
my $user = $ARGV[1] || "hr";
my $pass = $ARGV[2] || "password";

print "Connecting to: $dsn as $user\n";

my $dbh = DBIHelper->connect($dsn, $user, $pass, {RaiseError => 0, PrintError => 1});
if (!$dbh) {
    print "Connection failed: " . (DBI->errstr || "Unknown error") . "\n";
    exit 1;
}
print "✓ Connected\n";

# Test simple query
print "Preparing query: SELECT 1 as test_num FROM DUAL\n";
my $sth = $dbh->prepare("SELECT 1 as test_num FROM DUAL");
if (!$sth) {
    print "Prepare failed: " . $dbh->errstr . "\n";
    exit 1;
}
print "✓ Prepared\n";

print "Executing...\n";
my $rows = $sth->execute();
if (!defined $rows) {
    print "Execute failed: " . $sth->errstr . "\n";
    exit 1;
}
print "✓ Executed, rows: $rows\n";

# Check metadata
print "Column count: " . ($sth->{NUM_OF_FIELDS} || "unknown") . "\n";
if ($sth->{NAME_uc}) {
    print "Columns: " . join(", ", @{$sth->{NAME_uc}}) . "\n";
}

print "Fetching data...\n";
my @row = $sth->fetchrow_array();
print "Result: [" . join(", ", map { defined($_) ? $_ : "NULL" } @row) . "]\n";
print "Result count: " . scalar(@row) . "\n";

if (@row) {
    print "✅ SUCCESS: Data retrieved!\n";
} else {
    print "❌ FAILED: No data retrieved\n";
}

$sth->finish();
$dbh->disconnect();

print "=== Test Complete ===\n";