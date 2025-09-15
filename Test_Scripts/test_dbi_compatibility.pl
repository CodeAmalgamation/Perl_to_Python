#!/usr/bin/perl
# test_dbi_compatibility.pl - Test your specific DBI patterns

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin";

# Test the new system
use DBIHelper;

sub test_oracle_connection {
    my ($dsn, $username, $password) = @_;
    
    print "Testing Oracle DBI Compatibility\n";
    print "=" x 50 . "\n";
    print "DSN: $dsn\n";
    print "Username: $username\n\n";
    
    # Test your DbAccess.pm pattern
    print "1. Testing DbAccess.pm connection pattern...\n";
    my %attr = ( RaiseError => 1, AutoCommit => 1, PrintError => 1);
    
    my $dbh;
    if ($dsn =~ m/oracle/i) {
        $dbh = DBIHelper->connect($dsn, $username, $password, \%attr);
    } else {
        print "Not an Oracle DSN\n";
        return 0;
    }
    
    if (!$dbh || $dbh == 1) {
        print "✗ Connection failed\n";
        return 0;
    }
    print "✓ Connection successful\n\n";
    
    # Test your 35492_mi_select_sql.pl pattern
    print "2. Testing Oracle TNS pattern...\n";
    my $dbh2 = DBIHelper->connect("dbi:Oracle:", "${username}\@ORCL", $password, \%attr);
    if ($dbh2 && $dbh2 != 1) {
        print "✓ Oracle TNS connection successful\n";
    } else {
        print "⚠  Oracle TNS connection failed (check SID)\n";
    }
    print "\n";
    
    # Test prepare/execute
    print "3. Testing prepare/execute pattern...\n";
    my $sth = $dbh->prepare("SELECT SYSDATE as current_date, USER as current_user FROM DUAL");
    unless ($sth) {
        print "✗ Prepare failed: " . $dbh->errstr . "\n";
        return 0;
    }
    print "✓ Prepare successful\n";
    
    my $rowcount = $sth->execute();
    unless ($rowcount) {
        print "✗ Execute failed: " . $sth->errstr . "\n";
        return 0;
    }
    print "✓ Execute successful, rows: $rowcount\n\n";
    
    # Test column metadata (your scripts use this)
    print "4. Testing column metadata...\n";
    if ($sth->{NUM_OF_FIELDS}) {
        print "✓ NUM_OF_FIELDS: " . $sth->{NUM_OF_FIELDS} . "\n";
    }
    if ($sth->{NAME_uc} && @{$sth->{NAME_uc}}) {
        print "✓ NAME_uc: " . join(", ", @{$sth->{NAME_uc}}) . "\n";
    }
    print "\n";
    
    # Test fetchrow_array (main pattern in your scripts)
    print "5. Testing fetchrow_array pattern...\n";
    my @row = $sth->fetchrow_array();
    if (@row) {
        print "✓ Data retrieved: " . join(", ", @row) . "\n";
    } else {
        print "⚠  No data returned\n";
    }
    print "\n";
    
    # Test DBI::neat_list (used in your scripts)
    print "6. Testing DBI::neat_list...\n";
    if ($sth->{NAME_uc}) {
        my $formatted = DBI::neat_list($sth->{NAME_uc}, 100, ",");
        print "✓ DBI::neat_list: $formatted\n";
    }
    print "\n";
    
    # Test dump_results (used in 35492_mi_select_sql.pl)
    print "7. Testing dump_results...\n";
    $sth = $dbh->prepare("SELECT 'Test' as col1, 'Data' as col2 FROM DUAL");
    $sth->execute();
    
    open(my $fh, '>', '/tmp/test_dump.txt') or die "Cannot open test file: $!";
    my $dumped = $sth->dump_results(10, "\n", ",", $fh);
    close($fh);
    
    print "✓ dump_results dumped $dumped rows\n";
    if (-f '/tmp/test_dump.txt') {
        my $content = do { local $/; open my $f, '<', '/tmp/test_dump.txt'; <$f> };
        print "  Content: $content" if $content;
        unlink '/tmp/test_dump.txt';
    }
    print "\n";
    
    # Test transaction control
    print "8. Testing transaction control...\n";
    eval {
        $dbh->begin_work();
        print "✓ begin_work successful\n";
        
        $dbh->rollback();
        print "✓ rollback successful\n";
    };
    if ($@) {
        print "⚠  Transaction control error: $@\n";
    }
    print "\n";
    
    # Cleanup
    $sth->finish();
    $dbh->disconnect();
    
    print "✓ All DBI compatibility tests completed\n";
    return 1;
}

# Main test
print "DBI Replacement Compatibility Test\n";
print "=" x 60 . "\n\n";

# Replace with your actual Oracle connection details
my $test_dsn = $ARGV[0] || "dbi:Oracle:host=localhost;port=1521;service_name=XE";
my $test_user = $ARGV[1] || "hr";  
my $test_pass = $ARGV[2] || "password";

print "Usage: $0 [dsn] [username] [password]\n";
print "Using: DSN=$test_dsn, User=$test_user\n\n";

if (test_oracle_connection($test_dsn, $test_user, $test_pass)) {
    print "\n🎉 DBI replacement is fully compatible!\n";
    print "Ready to update your DbAccess.pm\n";
} else {
    print "\n❌ Compatibility issues detected.\n";
    print "Check connection parameters and Oracle setup.\n";
}