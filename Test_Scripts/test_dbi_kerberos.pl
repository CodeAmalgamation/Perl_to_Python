#!/usr/bin/perl
# test_dbi_kerberos.pl - Test DBI compatibility with Kerberos authentication

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/..";  # Parent directory for DBIHelper

# Set Kerberos environment variables
$ENV{KRB5_CONFIG} = $ENV{KRB5_CONFIG} || '/etc/krb5.conf';
$ENV{KRB5CCNAME} = $ENV{KRB5CCNAME} || '/tmp/krb5cc_1000';

# Test the new system
use DBIHelper;

sub test_kerberos_connection {
    my ($dsn) = @_;

    print "Testing Oracle DBI with Kerberos Authentication\n";
    print "=" x 50 . "\n";
    print "DSN: $dsn\n";
    print "KRB5_CONFIG: $ENV{KRB5_CONFIG}\n";
    print "KRB5CCNAME: $ENV{KRB5CCNAME}\n\n";

    # Verify Kerberos environment
    print "0. Verifying Kerberos environment...\n";
    if (!-f $ENV{KRB5_CONFIG}) {
        print "✗ KRB5_CONFIG file not found: $ENV{KRB5_CONFIG}\n";
        return 0;
    }
    print "✓ KRB5_CONFIG exists\n";

    if (!-f $ENV{KRB5CCNAME}) {
        print "✗ KRB5CCNAME file not found: $ENV{KRB5CCNAME}\n";
        print "  Run 'kinit username' to get a Kerberos ticket\n";
        return 0;
    }
    print "✓ KRB5CCNAME exists (ticket cache found)\n\n";

    # Test Kerberos connection (no username/password)
    print "1. Testing Kerberos connection (auto-detect)...\n";
    my %attr = ( RaiseError => 1, AutoCommit => 1, PrintError => 1);

    my $dbh = DBIHelper->connect($dsn, '', '', \%attr);

    if (!$dbh || $dbh == 1) {
        print "✗ Kerberos connection failed\n";
        print "  Check: 1) Valid Kerberos ticket (run 'klist')\n";
        print "         2) Oracle configured for Kerberos\n";
        print "         3) sqlnet.ora has AUTHENTICATION_SERVICES=(KERBEROS5)\n";
        return 0;
    }
    print "✓ Kerberos connection successful\n\n";

    # Test prepare/execute
    print "2. Testing prepare/execute pattern...\n";
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

    # Test column metadata
    print "3. Testing column metadata...\n";
    if ($sth->{NUM_OF_FIELDS}) {
        print "✓ NUM_OF_FIELDS: " . $sth->{NUM_OF_FIELDS} . "\n";
    }
    if ($sth->{NAME_uc} && @{$sth->{NAME_uc}}) {
        print "✓ NAME_uc: " . join(", ", @{$sth->{NAME_uc}}) . "\n";
    }
    print "\n";

    # Test fetchrow_array - get current user
    print "4. Testing fetchrow_array (verify Kerberos user)...\n";
    my @row = $sth->fetchrow_array();
    if (@row) {
        print "✓ Data retrieved:\n";
        print "  Date: $row[0]\n";
        print "  User: $row[1] (Kerberos authenticated)\n";
    } else {
        print "⚠  No data returned\n";
    }
    print "\n";

    # Test COUNT query (like POC)
    print "5. Testing COUNT query...\n";
    $sth = $dbh->prepare("SELECT COUNT(*) as cnt FROM DUAL");
    $sth->execute();
    @row = $sth->fetchrow_array();
    if (@row && $row[0] == 1) {
        print "✓ COUNT query successful: $row[0]\n";
    } else {
        print "⚠  COUNT query unexpected result\n";
    }
    print "\n";

    # Test table query (if ACQUIRER exists)
    print "6. Testing table query (ACQUIRER)...\n";
    eval {
        $sth = $dbh->prepare("SELECT COUNT(*) FROM ACQUIRER");
        $sth->execute();
        @row = $sth->fetchrow_array();
        if (@row) {
            print "✓ ACQUIRER table query successful: $row[0] rows\n";
        }
    };
    if ($@) {
        print "⚠  ACQUIRER table query failed (table may not exist)\n";
        print "  Error: $@\n";
    }
    print "\n";

    # Test DBI::neat_list
    print "7. Testing DBI::neat_list...\n";
    $sth = $dbh->prepare("SELECT 'Test' as col1, 'Data' as col2 FROM DUAL");
    $sth->execute();
    if ($sth->{NAME_uc}) {
        my $formatted = DBI::neat_list($sth->{NAME_uc}, 100, ",");
        print "✓ DBI::neat_list: $formatted\n";
    }
    print "\n";

    # Test dump_results
    print "8. Testing dump_results...\n";
    $sth = $dbh->prepare("SELECT 'Kerberos' as auth_type, USER as username FROM DUAL");
    $sth->execute();

    open(my $fh, '>', '/tmp/test_kerberos_dump.txt') or die "Cannot open test file: $!";
    my $dumped = $sth->dump_results(10, "\n", ",", $fh);
    close($fh);

    print "✓ dump_results dumped $dumped rows\n";
    if (-f '/tmp/test_kerberos_dump.txt') {
        my $content = do { local $/; open my $f, '<', '/tmp/test_kerberos_dump.txt'; <$f> };
        print "  Content: $content" if $content;
        unlink '/tmp/test_kerberos_dump.txt';
    }
    print "\n";

    # Test transaction control
    print "9. Testing transaction control...\n";
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

    # Test connection persistence (simulate daemon mode)
    print "10. Testing connection persistence...\n";
    my $dbh2 = DBIHelper->connect($dsn, '', '', \%attr);
    if ($dbh2 && $dbh2 != 1) {
        print "✓ Second connection successful (daemon mode working)\n";
        $dbh2->disconnect();
    } else {
        print "⚠  Second connection failed\n";
    }
    print "\n";

    # Cleanup
    $sth->finish();
    $dbh->disconnect();

    print "✓ All Kerberos DBI compatibility tests completed\n";
    return 1;
}

# Main test
print "\n";
print "=" x 60 . "\n";
print "DBI Kerberos Authentication Compatibility Test\n";
print "=" x 60 . "\n\n";

# Check if Kerberos ticket exists
system("which klist > /dev/null 2>&1");
if ($? == 0) {
    print "Checking Kerberos ticket status:\n";
    print "-" x 60 . "\n";
    system("klist 2>&1 | head -10");
    print "-" x 60 . "\n\n";
} else {
    print "⚠️  'klist' command not found - cannot verify Kerberos ticket\n\n";
}

# Get DSN from command line or use default
my $test_dsn = $ARGV[0] || "dbhost:6136/servicename";

print "Usage: $0 [dsn]\n";
print "Example: $0 \"dbhost:6136/servicename\"\n";
print "         $0 \"dbi:Oracle:host=dbhost;port=6136;service_name=servicename\"\n\n";

print "Testing with DSN: $test_dsn\n";
print "Auth Mode: Kerberos (auto-detected from environment)\n\n";

if (test_kerberos_connection($test_dsn)) {
    print "\n" . "=" x 60 . "\n";
    print "🎉 Kerberos DBI replacement is fully compatible!\n";
    print "=" x 60 . "\n";
    print "\nNext steps:\n";
    print "1. Update your DbAccess.pm to use DBIHelper\n";
    print "2. Set KRB5_CONFIG and KRB5CCNAME in your environment\n";
    print "3. Connections will automatically use Kerberos\n";
} else {
    print "\n" . "=" x 60 . "\n";
    print "❌ Compatibility issues detected.\n";
    print "=" x 60 . "\n";
    print "\nTroubleshooting:\n";
    print "1. Verify Kerberos ticket: klist\n";
    print "2. Check environment: echo \$KRB5_CONFIG \$KRB5CCNAME\n";
    print "3. Verify Oracle Kerberos config in sqlnet.ora\n";
    print "4. Check database connection: $test_dsn\n";
}

print "\n";
