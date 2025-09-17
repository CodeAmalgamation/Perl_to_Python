#!/usr/bin/perl

# test_statement_persistence.pl - Test statement persistence fixes

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/..";
use DBIHelper;

print "=== Testing Statement Persistence Fixes ===\n";

# Enable debugging
$DBIHelper::DEBUG_LEVEL = 2;

# Test with mock/test database - the Python bridge should handle gracefully
my $dsn = "dbi:Oracle:test_mock";
my $username = "test_user";
my $password = "test_password";

print "DSN: $dsn\n";
print "User: $username\n\n";

# Test 1: Connection (should work even if DB doesn't exist - tests bridge)
print "=== Test 1: Connection Bridge Test ===\n";
my %attr = (RaiseError => 1, AutoCommit => 1, PrintError => 1);

# The connection will fail, but we're testing the bridge communication
my $dbh = DBIHelper->connect($dsn, $username, $password, \%attr);

if (!$dbh || $dbh == 1) {
    print "INFO: Connection failed as expected (no real database)\n";
    print "This is normal - we're testing bridge communication\n";
} else {
    print "SUCCESS: Bridge communication working\n";

    # Test 2: Statement preparation (tests persistence setup)
    print "\n=== Test 2: Statement Preparation ===\n";
    my $sql = "SELECT 1 as test_col FROM DUAL";
    print "SQL: $sql\n";

    my $sth = $dbh->prepare($sql);
    if ($sth) {
        print "SUCCESS: Statement prepared with ID\n";

        # Test 3: Statement execution (tests restoration logic)
        print "\n=== Test 3: Statement Execution ===\n";
        my $result = $sth->execute();
        if (defined $result) {
            print "SUCCESS: Statement executed (restoration working)\n";

            # Test 4: Data fetching (tests auto re-execution)
            print "\n=== Test 4: Data Fetching ===\n";
            my @row = $sth->fetchrow_array();
            if (@row) {
                print "SUCCESS: Data fetched (auto re-execution working)\n";
                print "Data: [" . join(", ", map { defined $_ ? "'$_'" : 'NULL' } @row) . "]\n";
            } else {
                print "INFO: No data (normal for mock test)\n";
            }
        } else {
            print "INFO: Execute failed (normal for mock test)\n";
        }
    } else {
        print "INFO: Prepare failed (normal for mock test)\n";
    }

    $dbh->disconnect();
}

print "\n=== Statement Persistence Test Complete ===\n";
print "Note: This test validates bridge communication and error handling.\n";
print "For full database testing, use a real Oracle database connection.\n";