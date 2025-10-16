#!/usr/bin/perl
#
# test_sftp_ssh_key.pl - Test SFTP with SSH key authentication
#
# This test validates that SFTPHelper.pm correctly handles SSH key authentication
# using the 'more' parameter with identity file, as used in production.
#

use strict;
use warnings;
use lib "/Users/shubhamdixit/Perl_to_Python";
use SFTPHelper;
use File::Temp qw(tempfile);

# Test configuration
my $SFTP_HOST = $ENV{SFTP_TEST_HOST} || 'localhost';
my $SFTP_PORT = $ENV{SFTP_TEST_PORT} || 2222;
my $SFTP_USER = $ENV{SFTP_TEST_USER} || 'sftpuser';
my $SFTP_KEY = $ENV{SFTP_TEST_KEY} || '/tmp/sftp_test_keys/test_key';
my $SFTP_TEST_DIR = $ENV{SFTP_TEST_DIR} || '/upload';

# Test statistics
my $total_tests = 0;
my $passed_tests = 0;
my $failed_tests = 0;

print "=" x 80 . "\n";
print "SSH Key Authentication Test Suite\n";
print "=" x 80 . "\n";
print "Configuration:\n";
print "  Host: $SFTP_HOST\n";
print "  Port: $SFTP_PORT\n";
print "  User: $SFTP_USER\n";
print "  Key:  $SFTP_KEY\n";
print "  Dir:  $SFTP_TEST_DIR\n";
print "  Time: " . localtime() . "\n\n";

sub run_test {
    my ($test_name, $test_code) = @_;

    $total_tests++;
    print "\n" . "─" x 80 . "\n";
    print "Test $total_tests: $test_name\n";
    print "─" x 80 . "\n";

    eval {
        my $result = $test_code->();
        if ($result) {
            print "✓ PASS\n";
            $passed_tests++;
        } else {
            print "✗ FAIL\n";
            $failed_tests++;
        }
    };

    if ($@) {
        print "✗ FAIL - Exception: $@\n";
        $failed_tests++;
    }
}

sub assert {
    my ($condition, $message) = @_;
    if (!$condition) {
        die "Assertion failed: $message\n";
    }
    print "  ✓ $message\n";
    return 1;
}

# =============================================================================
# SSH Key Authentication Tests
# =============================================================================

run_test("SSH Key Auth - Basic connection with -i flag", sub {
    # This is the production pattern used in all 6 files
    my %sftp_opts = ();
    $sftp_opts{user} = $SFTP_USER;
    $sftp_opts{port} = $SFTP_PORT;
    $sftp_opts{timeout} = 30;
    $sftp_opts{more} = [ '-i' => $SFTP_KEY, '-v' ];

    my $sftp = Net::SFTP::Foreign->new($SFTP_HOST, %sftp_opts);

    if ($sftp->error) {
        print "  Error: " . $sftp->error . "\n";
        return 0;
    }

    assert(!$sftp->error, "Connection successful with SSH key");
    assert($sftp->is_connected, "Connection state is true");

    $sftp->disconnect();
    return 1;
});

run_test("SSH Key Auth - Array ref format", sub {
    # Alternative production pattern
    my @sftp_more = ('-i', $SFTP_KEY, '-v');

    my %sftp_config = (
        host => $SFTP_HOST,
        user => $SFTP_USER,
        port => $SFTP_PORT,
        more => \@sftp_more,
        timeout => 30
    );

    my $sftp = Net::SFTP::Foreign->new(%sftp_config);

    if ($sftp->error) {
        print "  Error: " . $sftp->error . "\n";
        return 0;
    }

    assert(!$sftp->error, "Connection successful with array ref");

    $sftp->disconnect();
    return 1;
});

run_test("SSH Key Auth - Inline more parameter", sub {
    my $sftp = Net::SFTP::Foreign->new(
        host => $SFTP_HOST,
        user => $SFTP_USER,
        port => $SFTP_PORT,
        timeout => 30,
        more => ['-i' => $SFTP_KEY, '-v']
    );

    if ($sftp->error) {
        print "  Error: " . $sftp->error . "\n";
        return 0;
    }

    assert(!$sftp->error, "Connection successful with inline more");

    $sftp->disconnect();
    return 1;
});

run_test("SSH Key Auth - File operations", sub {
    my $sftp = Net::SFTP::Foreign->new(
        host => $SFTP_HOST,
        user => $SFTP_USER,
        port => $SFTP_PORT,
        more => ['-i', $SFTP_KEY],
        timeout => 30
    );

    if ($sftp->error) {
        print "  Error: " . $sftp->error . "\n";
        return 0;
    }

    # Test setcwd
    $sftp->setcwd($SFTP_TEST_DIR);
    assert(!$sftp->error, "setcwd successful");

    # Test put
    my ($fh, $local_file) = tempfile(UNLINK => 1);
    print $fh "SSH key test: " . time();
    close $fh;

    my $remote_file = "ssh_key_test_" . time() . ".txt";
    $sftp->put($local_file, $remote_file);
    assert(!$sftp->error, "put successful");

    # Test ls
    my $files = $sftp->ls();
    assert(!$sftp->error, "ls successful");

    my @found = grep { $_->{filename} eq $remote_file } @$files;
    assert(scalar(@found) > 0, "File was uploaded");

    # Test get
    my $download_file = "/tmp/ssh_key_download_" . time() . ".txt";
    $sftp->get($remote_file, $download_file);
    assert(!$sftp->error, "get successful");
    assert(-f $download_file, "Downloaded file exists");

    # Cleanup
    $sftp->remove($remote_file);
    unlink $download_file;

    $sftp->disconnect();
    return 1;
});

run_test("SSH Key Auth - Invalid key path", sub {
    my $sftp = Net::SFTP::Foreign->new(
        host => $SFTP_HOST,
        user => $SFTP_USER,
        port => $SFTP_PORT,
        more => ['-i', '/nonexistent/key/path'],
        timeout => 10
    );

    # Should fail to connect
    assert($sftp->error, "Connection failed as expected");
    assert(!$sftp->is_connected, "Connection state is false");

    print "  Expected error: " . $sftp->error . "\n";
    return 1;
});

run_test("SSH Key Auth - Production e_oh_n_elec_rpt.pl pattern", sub {
    # Exact production pattern from e_oh_n_elec_rpt.pl
    my $remote_host = $SFTP_HOST;
    my $user = $SFTP_USER;
    my $identity_file = $SFTP_KEY;

    my %sftp_opts = ();
    $sftp_opts{user} = $user;
    $sftp_opts{port} = $SFTP_PORT;
    $sftp_opts{more} = [ -i => $identity_file, '-v'];
    $sftp_opts{timeout} = 30;

    my $sftp = Net::SFTP::Foreign->new($remote_host, %sftp_opts);

    if ($sftp->error) {
        print "  Connection error: " . $sftp->error . "\n";
        return 0;
    }

    $sftp->setcwd($SFTP_TEST_DIR);

    if ($sftp->error) {
        print "  setcwd error: " . $sftp->error . "\n";
        return 0;
    }

    # Upload and rename (Stratus pattern)
    my ($fh, $local_file) = tempfile(UNLINK => 1);
    print $fh "Production pattern test: " . time();
    close $fh;

    my $report_name = "test_report_" . time() . ".rpt";
    $sftp->put($local_file, $report_name);

    if ($sftp->error) {
        print "  put error: " . $sftp->error . "\n";
        return 0;
    }

    print "  ✓ Report uploaded: $report_name\n";

    # Add 'p' prefix for Stratus processing
    my $processed_name = "p" . $report_name;
    $sftp->rename($report_name, $processed_name);

    if ($sftp->error) {
        print "  rename error: " . $sftp->error . "\n";
        return 0;
    }

    print "  ✓ Report renamed for processing: $processed_name\n";

    # Cleanup
    $sftp->remove($processed_name);

    assert(1, "Production pattern completed successfully");

    $sftp->disconnect();
    return 1;
});

run_test("SSH Key Auth - Multiple SSH options", sub {
    # Test with multiple SSH options
    my $sftp = Net::SFTP::Foreign->new(
        host => $SFTP_HOST,
        user => $SFTP_USER,
        port => $SFTP_PORT,
        more => [
            '-i', $SFTP_KEY,
            '-v',
            '-o', 'StrictHostKeyChecking=no',
            '-o', 'UserKnownHostsFile=/dev/null'
        ],
        timeout => 30
    );

    if ($sftp->error) {
        print "  Error: " . $sftp->error . "\n";
        return 0;
    }

    assert(!$sftp->error, "Connection successful with multiple SSH options");

    $sftp->disconnect();
    return 1;
});

run_test("SSH Key Auth - Verify no password needed", sub {
    # Connect with SSH key but explicitly no password
    my $sftp = Net::SFTP::Foreign->new(
        host => $SFTP_HOST,
        user => $SFTP_USER,
        port => $SFTP_PORT,
        more => ['-i', $SFTP_KEY],
        password => undef,  # Explicitly no password
        timeout => 30
    );

    if ($sftp->error) {
        print "  Error: " . $sftp->error . "\n";
        return 0;
    }

    assert(!$sftp->error, "Connection successful without password");
    assert($sftp->is_connected, "Connection state is true");

    # Verify we can do operations
    $sftp->setcwd($SFTP_TEST_DIR);
    assert(!$sftp->error, "Operations work with key-only auth");

    $sftp->disconnect();
    return 1;
});

# =============================================================================
# Test Summary
# =============================================================================

print "\n" . "=" x 80 . "\n";
print "Test Summary\n";
print "=" x 80 . "\n";
print "Total Tests:  $total_tests\n";
print "Passed:       $passed_tests (" . sprintf("%.1f", ($passed_tests/$total_tests)*100) . "%)\n";
print "Failed:       $failed_tests\n";
print "Test End:     " . localtime() . "\n";
print "=" x 80 . "\n";

if ($passed_tests == $total_tests) {
    print "\n✓ ALL SSH KEY TESTS PASSED!\n";
    print "=" x 80 . "\n";
    exit 0;
} else {
    print "\n✗ SOME TESTS FAILED\n";
    print "=" x 80 . "\n";
    exit 1;
}
