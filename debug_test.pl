#!/usr/bin/perl
# Quick debug test to see what's happening

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin";

# Enable debug mode (start with level 1 to avoid JSON conflicts)
$ENV{'CPAN_BRIDGE_DEBUG'} = 1;

use DBIHelper;

print "=== Debug Test ===\n";

# Test connection
my $dsn = $ARGV[0] || "dbi:Oracle:host=localhost;port=1521;service_name=XE";
my $user = $ARGV[1] || "hr";
my $pass = $ARGV[2] || "password";

print "Connecting to: $dsn as $user\n";

my $dbh = DBIHelper->connect($dsn, $user, $pass, {RaiseError => 1});
if (!$dbh) {
    die "Connection failed\n";
}
print "✓ Connected\n";

# Test simple query
print "Preparing query...\n";
my $sth = $dbh->prepare("SELECT 1 as test_num FROM DUAL");
print "✓ Prepared\n";

print "Executing...\n";
my $rows = $sth->execute();
print "✓ Executed, rows: $rows\n";

print "Fetching...\n";
my @row = $sth->fetchrow_array();
print "Fetch result: [" . join(", ", @row) . "]\n";
print "Length: " . scalar(@row) . "\n";

$sth->finish();
$dbh->disconnect();

print "=== Test Complete ===\n";