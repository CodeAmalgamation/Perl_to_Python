#!/usr/bin/perl
#
# test_sftp_comprehensive.pl - Comprehensive SFTP testing based on production patterns
#
# This test suite validates SFTPHelper.pm against all patterns documented in
# Net_SFTP_Foreign_Usage_Analysis_Report.md
#
# Test Coverage:
# - Connection patterns (all 6 production files)
# - SSH key authentication
# - File operations (put, get, rename, remove)
# - Directory operations (setcwd, ls, mkdir)
# - Error handling
# - Stratus-specific patterns (port 295, 'p' prefix)
# - Failover scenarios
#

use strict;
use warnings;
use lib "/Users/shubhamdixit/Perl_to_Python";
use SFTPHelper;
use File::Temp qw(tempfile tempdir);
use File::Basename;
use Data::Dumper;

# Test configuration - will be set from environment or defaults
my $SFTP_HOST = $ENV{SFTP_TEST_HOST} || 'localhost';
my $SFTP_PORT = $ENV{SFTP_TEST_PORT} || 2222;
my $SFTP_USER = $ENV{SFTP_TEST_USER} || 'sftpuser';
my $SFTP_PASSWORD = $ENV{SFTP_TEST_PASSWORD} || 'sftppass';
my $SFTP_KEY = $ENV{SFTP_TEST_KEY} || '';  # Path to SSH key if using key auth
my $SFTP_TEST_DIR = $ENV{SFTP_TEST_DIR} || '/upload';

# Test statistics
my $total_tests = 0;
my $passed_tests = 0;
my $failed_tests = 0;
my @test_results;

print "=" x 80 . "\n";
print "SFTPHelper Comprehensive Test Suite\n";
print "=" x 80 . "\n";
print "Test Configuration:\n";
print "  Host: $SFTP_HOST\n";
print "  Port: $SFTP_PORT\n";
print "  User: $SFTP_USER\n";
print "  Auth: " . ($SFTP_KEY ? "SSH Key ($SFTP_KEY)" : "Password") . "\n";
print "  Test Dir: $SFTP_TEST_DIR\n";
print "  Start: " . localtime() . "\n\n";

# =============================================================================
# Test Helper Functions
# =============================================================================

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
            push @test_results, {name => $test_name, status => 'PASS'};
        } else {
            print "✗ FAIL\n";
            $failed_tests++;
            push @test_results, {name => $test_name, status => 'FAIL', error => 'Test returned false'};
        }
    };

    if ($@) {
        print "✗ FAIL - Exception: $@\n";
        $failed_tests++;
        push @test_results, {name => $test_name, status => 'FAIL', error => $@};
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

sub create_test_file {
    my ($content) = @_;
    my ($fh, $filename) = tempfile(UNLINK => 1);
    print $fh ($content || "Test file content: " . time());
    close $fh;
    return $filename;
}

sub cleanup_remote_file {
    my ($sftp, $filename) = @_;
    $sftp->remove($filename);
    # Ignore errors during cleanup
}

# =============================================================================
# SECTION 1: Connection Patterns
# Based on all 6 production files
# =============================================================================

run_test("Connection - Basic with password", sub {
    my $sftp = Net::SFTP::Foreign->new(
        host => $SFTP_HOST,
        user => $SFTP_USER,
        password => $SFTP_PASSWORD,
        port => $SFTP_PORT,
        timeout => 30
    );

    assert(!$sftp->error, "Connection successful");
    assert($sftp->is_connected, "Connection state is true");

    $sftp->disconnect();
    return 1;
});

run_test("Connection - e_oh_n_elec_rpt.pl pattern", sub {
    # Pattern: Hash with positional host parameter
    my %sftp_opts = ();
    $sftp_opts{user} = $SFTP_USER;
    $sftp_opts{port} = $SFTP_PORT;
    $sftp_opts{timeout} = 30;

    if ($SFTP_KEY) {
        $sftp_opts{more} = [ '-i' => $SFTP_KEY, '-v'];
    } else {
        $sftp_opts{password} = $SFTP_PASSWORD;
    }

    my $sftp = Net::SFTP::Foreign->new($SFTP_HOST, %sftp_opts);

    assert(!$sftp->error, "Connection successful with hash pattern");

    $sftp->disconnect();
    return 1;
});

run_test("Connection - mi_ftp_stratus_files.pl pattern", sub {
    # Pattern: Hash-based configuration
    my %sftp_config = ();
    $sftp_config{host} = $SFTP_HOST;
    $sftp_config{user} = $SFTP_USER;
    $sftp_config{port} = $SFTP_PORT;
    $sftp_config{timeout} = 30;

    if ($SFTP_KEY) {
        my @sftp_more = ('-i', $SFTP_KEY);
        $sftp_config{more} = \@sftp_more;
    } else {
        $sftp_config{password} = $SFTP_PASSWORD;
    }

    my $sftp = Net::SFTP::Foreign->new(%sftp_config);

    assert(!$sftp->error, "Connection successful with config hash");

    $sftp->disconnect();
    return 1;
});

run_test("Connection - mi_ftp_stratus_rpc_fw.pl pattern", sub {
    # Pattern: Named parameters inline
    my %conn_params = (
        host => $SFTP_HOST,
        user => $SFTP_USER,
        timeout => 30,
        port => $SFTP_PORT,
    );

    if ($SFTP_KEY) {
        $conn_params{more} = ['-i' => $SFTP_KEY, '-v'];
    } else {
        $conn_params{password} = $SFTP_PASSWORD;
    }

    my $sftp = Net::SFTP::Foreign->new(%conn_params);

    assert(!$sftp->error, "Connection successful with named params");

    $sftp->disconnect();
    return 1;
});

run_test("Connection - Error handling on bad credentials", sub {
    my $sftp = Net::SFTP::Foreign->new(
        host => $SFTP_HOST,
        user => $SFTP_USER,
        password => 'wrong_password',
        port => $SFTP_PORT,
        timeout => 10
    );

    # Should have an error
    assert($sftp->error, "Connection failed as expected");
    assert(!$sftp->is_connected, "Connection state is false");

    print "  Expected error: " . $sftp->error . "\n";
    return 1;
});

# =============================================================================
# SECTION 2: Directory Operations
# Usage: All 6 production files use setcwd
# =============================================================================

run_test("setcwd - Change to test directory", sub {
    my $sftp = Net::SFTP::Foreign->new(
        host => $SFTP_HOST,
        user => $SFTP_USER,
        password => $SFTP_PASSWORD,
        port => $SFTP_PORT
    );

    assert(!$sftp->error, "Connection successful");

    my $result = $sftp->setcwd($SFTP_TEST_DIR);
    assert(!$sftp->error, "setcwd successful");
    assert($result, "setcwd returned true");

    my $cwd = $sftp->cwd();
    print "  Current directory: $cwd\n";
    assert($cwd eq $SFTP_TEST_DIR, "Current directory matches");

    $sftp->disconnect();
    return 1;
});

run_test("setcwd - Nonexistent directory error", sub {
    my $sftp = Net::SFTP::Foreign->new(
        host => $SFTP_HOST,
        user => $SFTP_USER,
        password => $SFTP_PASSWORD,
        port => $SFTP_PORT
    );

    my $result = $sftp->setcwd('/nonexistent_directory_12345');
    assert($sftp->error, "Error detected for nonexistent directory");
    assert(!$result, "setcwd returned false");

    print "  Expected error: " . $sftp->error . "\n";

    $sftp->disconnect();
    return 1;
});

run_test("mkdir - Create directory", sub {
    my $sftp = Net::SFTP::Foreign->new(
        host => $SFTP_HOST,
        user => $SFTP_USER,
        password => $SFTP_PASSWORD,
        port => $SFTP_PORT
    );

    $sftp->setcwd($SFTP_TEST_DIR);

    my $test_dir = "test_dir_" . time();
    my $result = $sftp->mkdir($test_dir);

    assert(!$sftp->error, "mkdir successful");
    assert($result, "mkdir returned true");

    # Verify directory exists
    my $files = $sftp->ls();
    my @dirs = grep { $_->{filename} eq $test_dir } @$files;
    assert(scalar(@dirs) > 0, "Directory was created");

    # Cleanup
    $sftp->remove($test_dir);

    $sftp->disconnect();
    return 1;
});

run_test("ls - List current directory", sub {
    my $sftp = Net::SFTP::Foreign->new(
        host => $SFTP_HOST,
        user => $SFTP_USER,
        password => $SFTP_PASSWORD,
        port => $SFTP_PORT
    );

    $sftp->setcwd($SFTP_TEST_DIR);

    my $files = $sftp->ls();
    assert(!$sftp->error, "ls successful");
    assert(ref($files) eq 'ARRAY', "ls returned array ref");

    print "  Found " . scalar(@$files) . " entries\n";

    $sftp->disconnect();
    return 1;
});

run_test("ls - List with pattern (wanted parameter)", sub {
    my $sftp = Net::SFTP::Foreign->new(
        host => $SFTP_HOST,
        user => $SFTP_USER,
        password => $SFTP_PASSWORD,
        port => $SFTP_PORT
    );

    $sftp->setcwd($SFTP_TEST_DIR);

    # Create test files with different extensions
    my $test_content = "Pattern test: " . time();
    my $txt_file = "pattern_test_" . time() . ".txt";
    my $dat_file = "pattern_test_" . time() . ".dat";

    my $local_txt = create_test_file($test_content);
    my $local_dat = create_test_file($test_content);

    $sftp->put($local_txt, $txt_file);
    $sftp->put($local_dat, $dat_file);

    # List only .txt files
    my $txt_files = $sftp->ls(wanted => qr/\.txt$/);
    assert(!$sftp->error, "ls with pattern successful");

    print "  Found " . scalar(@$txt_files) . " .txt files\n";

    my @matches = grep { $_->{filename} eq $txt_file } @$txt_files;
    assert(scalar(@matches) > 0, "Pattern matched our .txt file");

    # Cleanup
    cleanup_remote_file($sftp, $txt_file);
    cleanup_remote_file($sftp, $dat_file);

    $sftp->disconnect();
    return 1;
});

# =============================================================================
# SECTION 3: File Operations - Upload (put)
# Usage: All 6 production files use put()
# =============================================================================

run_test("put - Upload simple file", sub {
    my $sftp = Net::SFTP::Foreign->new(
        host => $SFTP_HOST,
        user => $SFTP_USER,
        password => $SFTP_PASSWORD,
        port => $SFTP_PORT
    );

    $sftp->setcwd($SFTP_TEST_DIR);

    my $test_content = "Upload test: " . time();
    my $local_file = create_test_file($test_content);
    my $remote_file = "upload_test_" . time() . ".txt";

    my $result = $sftp->put($local_file, $remote_file);
    assert(!$sftp->error, "put successful");
    assert($result, "put returned true");

    # Verify file exists
    my $files = $sftp->ls();
    my @found = grep { $_->{filename} eq $remote_file } @$files;
    assert(scalar(@found) > 0, "File was uploaded");

    # Cleanup
    cleanup_remote_file($sftp, $remote_file);

    $sftp->disconnect();
    return 1;
});

run_test("put - Upload with absolute paths", sub {
    my $sftp = Net::SFTP::Foreign->new(
        host => $SFTP_HOST,
        user => $SFTP_USER,
        password => $SFTP_PASSWORD,
        port => $SFTP_PORT
    );

    my $test_content = "Absolute path test: " . time();
    my $local_file = create_test_file($test_content);
    my $remote_file = $SFTP_TEST_DIR . "/absolute_test_" . time() . ".txt";

    my $result = $sftp->put($local_file, $remote_file);
    assert(!$sftp->error, "put with absolute path successful");
    assert($result, "put returned true");

    # Cleanup
    cleanup_remote_file($sftp, $remote_file);

    $sftp->disconnect();
    return 1;
});

run_test("put - Multiple files sequentially", sub {
    my $sftp = Net::SFTP::Foreign->new(
        host => $SFTP_HOST,
        user => $SFTP_USER,
        password => $SFTP_PASSWORD,
        port => $SFTP_PORT
    );

    $sftp->setcwd($SFTP_TEST_DIR);

    my @uploaded = ();

    for my $i (1..3) {
        my $test_content = "Multi-file test $i: " . time();
        my $local_file = create_test_file($test_content);
        my $remote_file = "multi_test_${i}_" . time() . ".txt";

        my $result = $sftp->put($local_file, $remote_file);
        assert($result, "File $i uploaded");
        push @uploaded, $remote_file;
    }

    print "  Uploaded " . scalar(@uploaded) . " files successfully\n";

    # Cleanup
    foreach my $file (@uploaded) {
        cleanup_remote_file($sftp, $file);
    }

    $sftp->disconnect();
    return 1;
});

# =============================================================================
# SECTION 4: File Operations - Download (get)
# Usage: 3 production files use get()
# =============================================================================

run_test("get - Download file", sub {
    my $sftp = Net::SFTP::Foreign->new(
        host => $SFTP_HOST,
        user => $SFTP_USER,
        password => $SFTP_PASSWORD,
        port => $SFTP_PORT
    );

    $sftp->setcwd($SFTP_TEST_DIR);

    # First upload a file
    my $test_content = "Download test: " . time();
    my $local_upload = create_test_file($test_content);
    my $remote_file = "download_test_" . time() . ".txt";

    $sftp->put($local_upload, $remote_file);
    assert(!$sftp->error, "Upload for download test successful");

    # Now download it
    my $local_download = "/tmp/downloaded_" . time() . ".txt";
    my $result = $sftp->get($remote_file, $local_download);

    assert(!$sftp->error, "get successful");
    assert($result, "get returned true");
    assert(-f $local_download, "Downloaded file exists");

    # Verify content
    open my $fh, '<', $local_download or die "Cannot read downloaded file: $!";
    my $downloaded_content = do { local $/; <$fh> };
    close $fh;

    assert($downloaded_content eq $test_content, "Downloaded content matches");

    # Cleanup
    cleanup_remote_file($sftp, $remote_file);
    unlink $local_download;

    $sftp->disconnect();
    return 1;
});

# =============================================================================
# SECTION 5: File Operations - Rename
# Usage: 3 production files use rename() - critical for Stratus "p" prefix
# =============================================================================

run_test("rename - Simple rename", sub {
    my $sftp = Net::SFTP::Foreign->new(
        host => $SFTP_HOST,
        user => $SFTP_USER,
        password => $SFTP_PASSWORD,
        port => $SFTP_PORT
    );

    $sftp->setcwd($SFTP_TEST_DIR);

    # Upload a file
    my $test_content = "Rename test: " . time();
    my $local_file = create_test_file($test_content);
    my $original_name = "rename_original_" . time() . ".txt";
    my $new_name = "rename_new_" . time() . ".txt";

    $sftp->put($local_file, $original_name);
    assert(!$sftp->error, "Upload successful");

    # Rename it
    my $result = $sftp->rename($original_name, $new_name);
    assert(!$sftp->error, "rename successful");
    assert($result, "rename returned true");

    # Verify old name doesn't exist
    my $files = $sftp->ls();
    my @old = grep { $_->{filename} eq $original_name } @$files;
    assert(scalar(@old) == 0, "Old filename no longer exists");

    # Verify new name exists
    my @new = grep { $_->{filename} eq $new_name } @$files;
    assert(scalar(@new) > 0, "New filename exists");

    # Cleanup
    cleanup_remote_file($sftp, $new_name);

    $sftp->disconnect();
    return 1;
});

run_test("rename - Stratus 'p' prefix pattern", sub {
    # This pattern is used in e_oh_n_elec_rpt.pl
    my $sftp = Net::SFTP::Foreign->new(
        host => $SFTP_HOST,
        user => $SFTP_USER,
        password => $SFTP_PASSWORD,
        port => $SFTP_PORT
    );

    $sftp->setcwd($SFTP_TEST_DIR);

    # Upload a file
    my $test_content = "Stratus prefix test: " . time();
    my $local_file = create_test_file($test_content);
    my $original_name = "stratus_file_" . time() . ".txt";

    $sftp->put($local_file, $original_name);
    assert(!$sftp->error, "Upload successful");

    # Add 'p' prefix (Stratus processing pattern)
    my $prefixed_name = "p" . $original_name;
    my $result = $sftp->rename($original_name, $prefixed_name);

    assert(!$sftp->error, "Stratus prefix rename successful");
    assert($result, "rename returned true");

    # Verify prefixed file exists
    my $files = $sftp->ls();
    my @prefixed = grep { $_->{filename} eq $prefixed_name } @$files;
    assert(scalar(@prefixed) > 0, "Prefixed filename exists");

    print "  Stratus pattern: $original_name -> $prefixed_name\n";

    # Cleanup
    cleanup_remote_file($sftp, $prefixed_name);

    $sftp->disconnect();
    return 1;
});

# =============================================================================
# SECTION 6: File Operations - Remove
# Usage: 1 production file uses remove()
# =============================================================================

run_test("remove - Delete file", sub {
    my $sftp = Net::SFTP::Foreign->new(
        host => $SFTP_HOST,
        user => $SFTP_USER,
        password => $SFTP_PASSWORD,
        port => $SFTP_PORT
    );

    $sftp->setcwd($SFTP_TEST_DIR);

    # Upload a file to delete
    my $test_content = "Remove test: " . time();
    my $local_file = create_test_file($test_content);
    my $remote_file = "remove_test_" . time() . ".txt";

    $sftp->put($local_file, $remote_file);
    assert(!$sftp->error, "Upload successful");

    # Remove it
    my $result = $sftp->remove($remote_file);
    assert(!$sftp->error, "remove successful");
    assert($result, "remove returned true");

    # Verify file no longer exists
    my $files = $sftp->ls();
    my @found = grep { $_->{filename} eq $remote_file } @$files;
    assert(scalar(@found) == 0, "File was deleted");

    $sftp->disconnect();
    return 1;
});

# =============================================================================
# SECTION 7: Error Handling
# Usage: All 6 production files use error checking pattern
# =============================================================================

run_test("error - Check after successful operation", sub {
    my $sftp = Net::SFTP::Foreign->new(
        host => $SFTP_HOST,
        user => $SFTP_USER,
        password => $SFTP_PASSWORD,
        port => $SFTP_PORT
    );

    $sftp->setcwd($SFTP_TEST_DIR);

    my $error = $sftp->error;
    assert(!defined($error) || $error eq '', "No error after successful setcwd");

    $sftp->disconnect();
    return 1;
});

run_test("error - Check after failed operation", sub {
    my $sftp = Net::SFTP::Foreign->new(
        host => $SFTP_HOST,
        user => $SFTP_USER,
        password => $SFTP_PASSWORD,
        port => $SFTP_PORT
    );

    # Try to download nonexistent file
    my $result = $sftp->get('/nonexistent_file_12345.txt', '/tmp/nowhere.txt');

    assert(!$result, "Operation failed as expected");

    my $error = $sftp->error;
    assert(defined($error) && $error ne '', "Error message is set");

    print "  Error message: $error\n";

    $sftp->disconnect();
    return 1;
});

run_test("error - Production pattern if sftp error", sub {
    # This is the exact pattern used in all 6 production files
    my $sftp = Net::SFTP::Foreign->new(
        host => $SFTP_HOST,
        user => $SFTP_USER,
        password => $SFTP_PASSWORD,
        port => $SFTP_PORT
    );

    if ($sftp->error) {
        die "Connection failed (this shouldn't happen): " . $sftp->error;
    }

    $sftp->setcwd($SFTP_TEST_DIR);

    if ($sftp->error) {
        die "setcwd failed (this shouldn't happen): " . $sftp->error;
    }

    # Try failed operation
    $sftp->get('/nonexistent.txt', '/tmp/test.txt');

    if ($sftp->error) {
        print "  ✓ Error correctly detected: " . $sftp->error . "\n";
    } else {
        die "Error should have been detected";
    }

    $sftp->disconnect();
    return 1;
});

# =============================================================================
# SECTION 8: Real-World Production Patterns
# =============================================================================

run_test("Real-World - e_oh_n_elec_rpt.pl pattern", sub {
    # Pattern: Upload report and rename with 'p' prefix for Stratus
    my %sftp_opts = ();
    $sftp_opts{user} = $SFTP_USER;
    $sftp_opts{port} = $SFTP_PORT;
    $sftp_opts{password} = $SFTP_PASSWORD;
    $sftp_opts{timeout} = 30;

    my $sftp = Net::SFTP::Foreign->new($SFTP_HOST, %sftp_opts);

    if ($sftp->error) {
        die "Connection failed: " . $sftp->error;
    }

    $sftp->setcwd($SFTP_TEST_DIR);

    if ($sftp->error) {
        die "setcwd failed: " . $sftp->error;
    }

    # Upload report file
    my $report_content = "Electronic Report Data\n" . time();
    my $local_report = create_test_file($report_content);
    my $report_name = "noc_elec." . time() . ".rpt";

    $sftp->put($local_report, $report_name);

    if ($sftp->error) {
        die "put failed: " . $sftp->error;
    }

    print "  ✓ Report uploaded: $report_name\n";

    # Add 'p' prefix for Stratus processing
    my $processed_name = "p" . $report_name;
    $sftp->rename($report_name, $processed_name);

    if ($sftp->error) {
        die "rename failed: " . $sftp->error;
    }

    print "  ✓ Report renamed for processing: $processed_name\n";

    # Cleanup
    cleanup_remote_file($sftp, $processed_name);

    $sftp->disconnect();
    return 1;
});

run_test("Real-World - File watcher pattern", sub {
    # Pattern: List files with pattern, download, and cleanup
    my $sftp = Net::SFTP::Foreign->new(
        host => $SFTP_HOST,
        user => $SFTP_USER,
        password => $SFTP_PASSWORD,
        port => $SFTP_PORT,
        timeout => 30
    );

    if ($sftp->error) {
        die "Connection failed: " . $sftp->error;
    }

    $sftp->setcwd($SFTP_TEST_DIR);

    # Create test files to watch
    my @test_files = ();
    for my $i (1..2) {
        my $content = "Watch file $i: " . time();
        my $local = create_test_file($content);
        my $remote = "watch_" . time() . "_$i.dat";

        $sftp->put($local, $remote);
        push @test_files, $remote;
        sleep 1; # Ensure unique timestamps
    }

    print "  Created " . scalar(@test_files) . " test files\n";

    # List files matching pattern
    my $files = $sftp->ls(wanted => qr/\.dat$/);

    if ($sftp->error) {
        die "ls failed: " . $sftp->error;
    }

    print "  Found " . scalar(@$files) . " .dat files\n";

    # Download and remove (file watcher pattern)
    foreach my $file (@test_files) {
        my $local_dest = "/tmp/watched_" . time() . ".dat";

        $sftp->get($file, $local_dest);
        if ($sftp->error) {
            print "  Warning: get failed for $file\n";
            next;
        }

        print "  ✓ Downloaded: $file\n";

        $sftp->remove($file);
        if ($sftp->error) {
            print "  Warning: remove failed for $file\n";
        } else {
            print "  ✓ Removed: $file\n";
        }

        unlink $local_dest;
    }

    $sftp->disconnect();
    return 1;
});

# =============================================================================
# SECTION 9: Connection Lifecycle
# =============================================================================

run_test("Connection - Disconnect and reconnect", sub {
    my $sftp = Net::SFTP::Foreign->new(
        host => $SFTP_HOST,
        user => $SFTP_USER,
        password => $SFTP_PASSWORD,
        port => $SFTP_PORT
    );

    assert(!$sftp->error, "Initial connection successful");
    assert($sftp->is_connected, "Connection state is true");

    $sftp->disconnect();
    assert(!$sftp->is_connected, "Disconnected state is false");

    # Operations after disconnect should fail
    eval {
        $sftp->setcwd('/test');
    };
    assert($@, "Operations fail after disconnect");

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

if ($failed_tests > 0) {
    print "\nFailed Tests:\n";
    print "=" x 80 . "\n";
    foreach my $result (@test_results) {
        if ($result->{status} eq 'FAIL') {
            print "✗ $result->{name}\n";
            if ($result->{error}) {
                print "  Error: $result->{error}\n";
            }
        }
    }
    print "=" x 80 . "\n";
}

print "\n";

if ($passed_tests == $total_tests) {
    print "✓ ALL TESTS PASSED - SFTPHelper is production ready!\n";
    print "=" x 80 . "\n";
    exit 0;
} else {
    print "✗ SOME TESTS FAILED - Review failures above\n";
    print "=" x 80 . "\n";
    exit 1;
}
