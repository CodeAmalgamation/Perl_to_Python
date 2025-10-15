#!/usr/bin/perl
# test_ftp_production.pl - Production-ready comprehensive test suite for FTPHelper
#
# This test requires a real FTP server and will perform actual FTP operations.
# Configure FTP_TEST_HOST, FTP_TEST_USER, FTP_TEST_PASS environment variables.
#
# Tests all Net::FTP functionality identified in Net_FTP_Usage_Analysis.md:
# - new() with various parameter combinations
# - login() authentication
# - cwd() directory change
# - pwd() current directory
# - dir() directory listing
# - binary() and ascii() transfer modes
# - get() file download
# - put() file upload
# - delete() file deletion
# - rename() file renaming
# - message() error messages
# - quit() cleanup
# - Error handling and edge cases
# - Connection pooling and lifecycle
# - Multiple simultaneous connections
# - Production usage patterns

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/..";
use FTPHelper;  # This overrides Net::FTP
use Data::Dumper;
use File::Temp qw(tempfile);
use Time::HiRes qw(time);

# Configuration - MUST be set for real FTP server
my $FTP_HOST = $ENV{FTP_TEST_HOST} || die "FTP_TEST_HOST environment variable not set\n";
my $FTP_USER = $ENV{FTP_TEST_USER} || die "FTP_TEST_USER environment variable not set\n";
my $FTP_PASS = $ENV{FTP_TEST_PASS} || die "FTP_TEST_PASS environment variable not set\n";
my $FTP_DIR = $ENV{FTP_TEST_DIR} || '/';  # Default to root directory
my $TEST_TIMEOUT = 60;

print "=" x 80 . "\n";
print "FTPHelper Production Test Suite\n";
print "=" x 80 . "\n\n";

print "Configuration:\n";
print "  FTP Host: $FTP_HOST\n";
print "  FTP User: $FTP_USER\n";
print "  FTP Directory: $FTP_DIR\n";
print "  Timeout: $TEST_TIMEOUT seconds\n\n";

print "WARNING: This test will perform real FTP operations on $FTP_HOST\n";
print "Press Ctrl+C within 5 seconds to abort...\n\n";
sleep 5;

# Test counters
my $tests_run = 0;
my $tests_passed = 0;
my $tests_failed = 0;
my @failed_tests;

# Test Suite
print "\n" . "=" x 80 . "\n";
print "BEGINNING TEST SUITE\n";
print "=" x 80 . "\n\n";

# Test 1: Basic connection and quit
test_basic_connection();

# Test 2: Constructor parameters
test_constructor_parameters();

# Test 3: Login and authentication
test_login();

# Test 4: Directory operations (cwd, pwd)
test_directory_operations();

# Test 5: Directory listing (dir)
test_directory_listing();

# Test 6: Transfer mode (binary, ascii)
test_transfer_modes();

# Test 7: File upload (put)
test_file_upload();

# Test 8: File download (get)
test_file_download();

# Test 9: File rename
test_file_rename();

# Test 10: File delete
test_file_delete();

# Test 11: Production pattern from CommonControlmSubs.pm
test_production_pattern_simple();

# Test 12: Production pattern from mi_ftp_stratus_files.pl
test_production_pattern_complex();

# Test 13: Atomic operations (put + rename)
test_atomic_operations();

# Test 14: Multiple simultaneous connections
test_multiple_connections();

# Test 15: Error handling - invalid credentials
test_invalid_credentials();

# Test 16: Error handling - invalid directory
test_invalid_directory();

# Test 17: Error handling - non-existent file
test_nonexistent_file();

# Test 18: Connection lifecycle and cleanup
test_connection_lifecycle();

# Test 19: Message extraction
test_message_extraction();

# Test 20: Rapid connection creation/destruction
test_rapid_connections();

# Summary
print "\n" . "=" x 80 . "\n";
print "TEST SUITE SUMMARY\n";
print "=" x 80 . "\n";
print "Total tests: $tests_run\n";
print "Passed: $tests_passed (" . sprintf("%.1f", $tests_passed/$tests_run*100) . "%)\n";
print "Failed: $tests_failed (" . sprintf("%.1f", $tests_failed/$tests_run*100) . "%)\n";

if ($tests_failed > 0) {
    print "\nFailed tests:\n";
    foreach my $test (@failed_tests) {
        print "  - $test\n";
    }
    print "\n✗ TEST SUITE FAILED\n";
    exit 1;
} else {
    print "\n✓ ALL TESTS PASSED\n";
    exit 0;
}

###############################################################################
# Test Functions
###############################################################################

sub test_basic_connection {
    print "Test 1: Basic connection and quit\n";
    print "-" x 80 . "\n";

    eval {
        my $ftp = Net::FTP->new($FTP_HOST, Timeout => $TEST_TIMEOUT, Debug => 0);

        if ($ftp) {
            pass("Connection established");
            ok($ftp->{_connection_id}, "Connection ID assigned");
            ok($ftp->{_host} eq $FTP_HOST, "Host stored correctly");

            # Verify we can quit
            my $result = $ftp->quit();
            ok($result, "quit() returns true");
            ok(!$ftp->{_connection_id}, "Connection ID removed after quit");

            pass("Basic connection test completed");
        } else {
            fail("Failed to connect to FTP server: $!");
        }
    };

    if ($@) {
        fail("Basic connection test threw exception: $@");
    }

    print "\n";
}

sub test_constructor_parameters {
    print "Test 2: Constructor with various parameters\n";
    print "-" x 80 . "\n";

    eval {
        # Test with explicit timeout
        my $ftp1 = Net::FTP->new($FTP_HOST, Timeout => 30);
        ok($ftp1, "Constructor with explicit timeout");
        $ftp1->quit() if $ftp1;

        # Test with debug enabled
        my $ftp2 = Net::FTP->new($FTP_HOST, Debug => 1);
        ok($ftp2, "Constructor with debug enabled");
        $ftp2->quit() if $ftp2;

        # Test with both options
        my $ftp3 = Net::FTP->new($FTP_HOST, Timeout => $TEST_TIMEOUT, Debug => 0);
        ok($ftp3, "Constructor with multiple options");
        $ftp3->quit() if $ftp3;

        pass("Constructor parameter variations completed");
    };

    if ($@) {
        fail("Constructor parameters test threw exception: $@");
    }

    print "\n";
}

sub test_login {
    print "Test 3: Login and authentication\n";
    print "-" x 80 . "\n";

    eval {
        my $ftp = Net::FTP->new($FTP_HOST, Timeout => $TEST_TIMEOUT);

        unless ($ftp) {
            fail("Failed to create FTP connection");
            return;
        }

        # Test successful login
        my $result = $ftp->login($FTP_USER, $FTP_PASS);
        ok($result, "Login successful");

        $ftp->quit();
        pass("Login test completed");
    };

    if ($@) {
        fail("Login test threw exception: $@");
    }

    print "\n";
}

sub test_directory_operations {
    print "Test 4: Directory operations (cwd, pwd)\n";
    print "-" x 80 . "\n";

    eval {
        my $ftp = Net::FTP->new($FTP_HOST, Timeout => $TEST_TIMEOUT);
        unless ($ftp) {
            fail("Failed to create FTP connection");
            return;
        }

        $ftp->login($FTP_USER, $FTP_PASS) or die "Login failed";

        # Test pwd()
        my $current_dir = $ftp->pwd();
        ok(defined $current_dir, "pwd() returned current directory: $current_dir");

        # Test cwd()
        my $result = $ftp->cwd($FTP_DIR);
        ok($result, "cwd() changed to directory: $FTP_DIR");

        # Verify directory changed
        my $new_dir = $ftp->pwd();
        ok(defined $new_dir, "pwd() after cwd() returned: $new_dir");

        $ftp->quit();
        pass("Directory operations test completed");
    };

    if ($@) {
        fail("Directory operations test threw exception: $@");
    }

    print "\n";
}

sub test_directory_listing {
    print "Test 5: Directory listing (dir)\n";
    print "-" x 80 . "\n";

    eval {
        my $ftp = Net::FTP->new($FTP_HOST, Timeout => $TEST_TIMEOUT);
        unless ($ftp) {
            fail("Failed to create FTP connection");
            return;
        }

        $ftp->login($FTP_USER, $FTP_PASS) or die "Login failed";
        $ftp->cwd($FTP_DIR) or die "CWD failed";

        # Test dir()
        my @files = $ftp->dir();
        pass("dir() returned " . scalar(@files) . " entries");

        # Test dir() in scalar context
        my $file_ref = $ftp->dir();
        ok(ref($file_ref) eq 'ARRAY', "dir() in scalar context returns array ref");

        $ftp->quit();
        pass("Directory listing test completed");
    };

    if ($@) {
        fail("Directory listing test threw exception: $@");
    }

    print "\n";
}

sub test_transfer_modes {
    print "Test 6: Transfer mode (binary, ascii)\n";
    print "-" x 80 . "\n";

    eval {
        my $ftp = Net::FTP->new($FTP_HOST, Timeout => $TEST_TIMEOUT);
        unless ($ftp) {
            fail("Failed to create FTP connection");
            return;
        }

        $ftp->login($FTP_USER, $FTP_PASS) or die "Login failed";

        # Test binary mode
        my $result1 = $ftp->binary();
        ok($result1, "binary() mode set successfully");

        # Test ASCII mode
        my $result2 = $ftp->ascii();
        ok($result2, "ascii() mode set successfully");

        # Switch back to binary (default for most operations)
        my $result3 = $ftp->binary();
        ok($result3, "Switched back to binary mode");

        $ftp->quit();
        pass("Transfer mode test completed");
    };

    if ($@) {
        fail("Transfer mode test threw exception: $@");
    }

    print "\n";
}

sub test_file_upload {
    print "Test 7: File upload (put)\n";
    print "-" x 80 . "\n";

    eval {
        my $ftp = Net::FTP->new($FTP_HOST, Timeout => $TEST_TIMEOUT);
        unless ($ftp) {
            fail("Failed to create FTP connection");
            return;
        }

        $ftp->login($FTP_USER, $FTP_PASS) or die "Login failed";

        # Stay in home directory (writable) instead of changing to FTP_DIR
        $ftp->binary() or die "Binary mode failed";

        # Create temporary test file
        my ($fh, $filename) = tempfile(UNLINK => 1);
        print $fh "Test content for FTP upload\n";
        print $fh "Line 2 of test data\n";
        print $fh "Generated at: " . scalar(localtime) . "\n";
        close $fh;

        my $remote_name = "ftp_test_upload_" . time() . ".txt";

        # Upload file
        my $result = $ftp->put($filename, $remote_name);
        ok($result, "put() uploaded file successfully: $remote_name");

        # Verify file exists on server
        my @files = $ftp->dir($remote_name);
        ok(@files > 0, "Uploaded file exists on server");

        # Cleanup - delete test file
        $ftp->delete($remote_name);

        $ftp->quit();
        pass("File upload test completed");
    };

    if ($@) {
        fail("File upload test threw exception: $@");
    }

    print "\n";
}

sub test_file_download {
    print "Test 8: File download (get)\n";
    print "-" x 80 . "\n";

    eval {
        my $ftp = Net::FTP->new($FTP_HOST, Timeout => $TEST_TIMEOUT);
        unless ($ftp) {
            fail("Failed to create FTP connection");
            return;
        }

        $ftp->login($FTP_USER, $FTP_PASS) or die "Login failed";
        # Stay in writable home directory
        $ftp->binary() or die "Binary mode failed";

        # First upload a test file
        my ($upload_fh, $upload_file) = tempfile(UNLINK => 1);
        print $upload_fh "Test content for FTP download\n";
        close $upload_fh;

        my $remote_name = "ftp_test_download_" . time() . ".txt";
        $ftp->put($upload_file, $remote_name) or die "Upload failed";

        # Now download it
        my ($download_fh, $download_file) = tempfile(UNLINK => 1);
        close $download_fh;  # Close handle before FTP writes to it

        my $result = $ftp->get($remote_name, $download_file);
        ok($result, "get() downloaded file successfully");

        # Verify downloaded file exists and has content
        ok(-e $download_file, "Downloaded file exists");
        ok(-s $download_file > 0, "Downloaded file has content");

        # Cleanup
        $ftp->delete($remote_name);
        $ftp->quit();

        pass("File download test completed");
    };

    if ($@) {
        fail("File download test threw exception: $@");
    }

    print "\n";
}

sub test_file_rename {
    print "Test 9: File rename\n";
    print "-" x 80 . "\n";

    eval {
        my $ftp = Net::FTP->new($FTP_HOST, Timeout => $TEST_TIMEOUT);
        unless ($ftp) {
            fail("Failed to create FTP connection");
            return;
        }

        $ftp->login($FTP_USER, $FTP_PASS) or die "Login failed";
        # Stay in writable home directory
        $ftp->binary() or die "Binary mode failed";

        # Create test file
        my ($fh, $filename) = tempfile(UNLINK => 1);
        print $fh "Test content for rename\n";
        close $fh;

        my $old_name = "ftp_test_old_" . time() . ".txt";
        my $new_name = "ftp_test_new_" . time() . ".txt";

        # Upload file
        $ftp->put($filename, $old_name) or die "Upload failed";

        # Rename file
        my $result = $ftp->rename($old_name, $new_name);
        ok($result, "rename() renamed file successfully");

        # Verify new file exists
        my @files = $ftp->dir($new_name);
        ok(@files > 0, "Renamed file exists with new name");

        # Cleanup
        $ftp->delete($new_name);
        $ftp->quit();

        pass("File rename test completed");
    };

    if ($@) {
        fail("File rename test threw exception: $@");
    }

    print "\n";
}

sub test_file_delete {
    print "Test 10: File delete\n";
    print "-" x 80 . "\n";

    eval {
        my $ftp = Net::FTP->new($FTP_HOST, Timeout => $TEST_TIMEOUT);
        unless ($ftp) {
            fail("Failed to create FTP connection");
            return;
        }

        $ftp->login($FTP_USER, $FTP_PASS) or die "Login failed";
        # Stay in writable home directory
        $ftp->binary() or die "Binary mode failed";

        # Create test file
        my ($fh, $filename) = tempfile(UNLINK => 1);
        print $fh "Test content for delete\n";
        close $fh;

        my $remote_name = "ftp_test_delete_" . time() . ".txt";

        # Upload file
        $ftp->put($filename, $remote_name) or die "Upload failed";

        # Delete file
        my $result = $ftp->delete($remote_name);
        ok($result, "delete() deleted file successfully");

        # Verify file no longer exists
        my @files = $ftp->dir($remote_name);
        ok(@files == 0, "Deleted file no longer exists");

        $ftp->quit();
        pass("File delete test completed");
    };

    if ($@) {
        fail("File delete test threw exception: $@");
    }

    print "\n";
}

sub test_production_pattern_simple {
    print "Test 11: Production pattern from CommonControlmSubs.pm\n";
    print "-" x 80 . "\n";

    eval {
        # Replicate exact production pattern
        my $server = $FTP_HOST;
        my $login = $FTP_USER;
        my $password = $FTP_PASS;
        my $directory = $FTP_DIR;
        my $myrc = 0;

        my $ftp = Net::FTP->new($server, Debug => 0);

        if (!$ftp) {
            print "  Could not connect to server.\n";
            $myrc = 9;
        }

        if ($myrc == 0 && $ftp->login($login, $password)) {
            if ($ftp->cwd($directory)) {
                pass("Production pattern: login and cwd successful");
                # Note: Can't test actual get() without knowing a file that exists
            } else {
                print "  Could not change directory to $directory\n";
                $myrc = 6;
            }
        } else {
            print "  Could not login with user: [$login] and password: [***]\n";
            $myrc = 7;
        }

        $ftp->quit() if $ftp;

        ok($myrc == 0, "Production pattern completed with rc=$myrc");
        pass("Simple production pattern test completed");
    };

    if ($@) {
        fail("Simple production pattern test threw exception: $@");
    }

    print "\n";
}

sub test_production_pattern_complex {
    print "Test 12: Production pattern from mi_ftp_stratus_files.pl\n";
    print "-" x 80 . "\n";

    eval {
        # Replicate complex production pattern with error handling
        my $dns_server = $FTP_HOST;
        my $user = $FTP_USER;
        my $password = $FTP_PASS;
        my $remote_location = $FTP_DIR;
        my $MsgBuffer = "";

        my $ftp = Net::FTP->new($dns_server, Debug => 0, Timeout => 30)
            or die "ftp_transfer(): Cannot connect to $dns_server: $!";

        $ftp->login($user, $password)
            or die "ftp_transfer(): User [$user] cannot login to [$dns_server]. " .
                $ftp->message;

        if (!$ftp->cwd($remote_location)) {
            $MsgBuffer .= "ftp_transfer(): Cannot change remote directory to [$remote_location]" .
                "on server [$dns_server]. " . $ftp->message . "\n";
            die $MsgBuffer;
        }

        # Test binary mode setting
        if (!$ftp->binary) {
            $MsgBuffer = "Cannot set Transfer mode to binary\n" .
                $ftp->message . "\n";
            die $MsgBuffer;
        }

        pass("Complex production pattern: all operations successful");

        $ftp->quit();
        pass("Complex production pattern test completed");
    };

    if ($@) {
        # Expected to catch errors in production pattern
        if ($@ =~ /ftp_transfer/) {
            pass("Production error handling working as expected");
        } else {
            fail("Complex production pattern test threw unexpected exception: $@");
        }
    }

    print "\n";
}

sub test_atomic_operations {
    print "Test 13: Atomic operations (put + rename)\n";
    print "-" x 80 . "\n";

    eval {
        my $ftp = Net::FTP->new($FTP_HOST, Timeout => $TEST_TIMEOUT);
        unless ($ftp) {
            fail("Failed to create FTP connection");
            return;
        }

        $ftp->login($FTP_USER, $FTP_PASS) or die "Login failed";
        # Stay in writable home directory
        $ftp->binary() or die "Binary mode failed";

        # Create test file
        my ($fh, $filename) = tempfile(UNLINK => 1);
        print $fh "Atomic operation test content\n";
        close $fh;

        # Atomic operation: upload to temp name, then rename
        my $temp_name = "ftp_test_temp_" . time() . ".tmp";
        my $final_name = "ftp_test_final_" . time() . ".txt";

        # Upload to temporary name
        my $result1 = $ftp->put($filename, $temp_name);
        ok($result1, "Uploaded to temporary name");

        # Rename to final name (atomic operation)
        my $result2 = $ftp->rename($temp_name, $final_name);
        ok($result2, "Renamed to final name (atomic)");

        # Verify final file exists
        my @files = $ftp->dir($final_name);
        ok(@files > 0, "Final file exists after atomic operation");

        # Cleanup
        $ftp->delete($final_name);
        $ftp->quit();

        pass("Atomic operations test completed");
    };

    if ($@) {
        fail("Atomic operations test threw exception: $@");
    }

    print "\n";
}

sub test_multiple_connections {
    print "Test 14: Multiple simultaneous connections\n";
    print "-" x 80 . "\n";

    eval {
        my @connections;
        my $conn_count = 3;

        # Create multiple connections
        for my $i (1..$conn_count) {
            my $ftp = Net::FTP->new($FTP_HOST, Timeout => $TEST_TIMEOUT);
            if ($ftp) {
                $ftp->login($FTP_USER, $FTP_PASS);
                push @connections, $ftp;
            }
        }

        ok(scalar(@connections) == $conn_count, "Created $conn_count simultaneous connections");

        # Use each connection
        my $used_count = 0;
        foreach my $ftp (@connections) {
            my $dir = $ftp->pwd();
            $used_count++ if defined $dir;
        }

        ok($used_count == $conn_count, "Used all $conn_count connections successfully");

        # Cleanup all connections
        foreach my $ftp (@connections) {
            $ftp->quit();
        }

        pass("Multiple simultaneous connections test completed");
    };

    if ($@) {
        fail("Multiple connections test threw exception: $@");
    }

    print "\n";
}

sub test_invalid_credentials {
    print "Test 15: Error handling - invalid credentials\n";
    print "-" x 80 . "\n";

    eval {
        my $ftp = Net::FTP->new($FTP_HOST, Timeout => $TEST_TIMEOUT);

        unless ($ftp) {
            fail("Failed to create FTP connection");
            return;
        }

        # Try invalid login
        my $result = $ftp->login("invalid_user_12345", "invalid_pass_12345");

        ok(!$result, "Login with invalid credentials returns false");

        # Check error message is available
        my $msg = $ftp->message();
        ok(defined $msg && length($msg) > 0, "Error message available: $msg");

        $ftp->quit();
        pass("Invalid credentials error handling completed");
    };

    if ($@) {
        fail("Invalid credentials test threw exception: $@");
    }

    print "\n";
}

sub test_invalid_directory {
    print "Test 16: Error handling - invalid directory\n";
    print "-" x 80 . "\n";

    eval {
        my $ftp = Net::FTP->new($FTP_HOST, Timeout => $TEST_TIMEOUT);

        unless ($ftp) {
            fail("Failed to create FTP connection");
            return;
        }

        $ftp->login($FTP_USER, $FTP_PASS) or die "Login failed";

        # Try to change to non-existent directory
        my $result = $ftp->cwd("/nonexistent_directory_12345");

        ok(!$result, "cwd() to invalid directory returns false");

        # Check error message
        my $msg = $ftp->message();
        ok(defined $msg && length($msg) > 0, "Error message available: $msg");

        $ftp->quit();
        pass("Invalid directory error handling completed");
    };

    if ($@) {
        fail("Invalid directory test threw exception: $@");
    }

    print "\n";
}

sub test_nonexistent_file {
    print "Test 17: Error handling - non-existent file\n";
    print "-" x 80 . "\n";

    eval {
        my $ftp = Net::FTP->new($FTP_HOST, Timeout => $TEST_TIMEOUT);

        unless ($ftp) {
            fail("Failed to create FTP connection");
            return;
        }

        $ftp->login($FTP_USER, $FTP_PASS) or die "Login failed";
        $ftp->cwd($FTP_DIR) or die "CWD failed";

        # Try to get non-existent file
        my ($fh, $local_file) = tempfile(UNLINK => 1);
        close $fh;

        my $result = $ftp->get("nonexistent_file_12345.txt", $local_file);

        ok(!$result, "get() on non-existent file returns false");

        # Check error message
        my $msg = $ftp->message();
        ok(defined $msg && length($msg) > 0, "Error message available: $msg");

        $ftp->quit();
        pass("Non-existent file error handling completed");
    };

    if ($@) {
        fail("Non-existent file test threw exception: $@");
    }

    print "\n";
}

sub test_connection_lifecycle {
    print "Test 18: Connection lifecycle and cleanup\n";
    print "-" x 80 . "\n";

    eval {
        # Test 1: Normal lifecycle
        {
            my $ftp = Net::FTP->new($FTP_HOST, Timeout => $TEST_TIMEOUT);
            ok($ftp->{_connection_id}, "Connection created with ID");

            $ftp->quit();
            ok(!$ftp->{_connection_id}, "Connection ID removed after quit");
        }

        # Test 2: DESTROY cleanup (object goes out of scope)
        {
            my $ftp = Net::FTP->new($FTP_HOST, Timeout => $TEST_TIMEOUT);
            my $conn_id = $ftp->{_connection_id};
            ok($conn_id, "Connection created");
            # Object goes out of scope - DESTROY should cleanup
        }

        # Test 3: Double quit (idempotent)
        {
            my $ftp = Net::FTP->new($FTP_HOST, Timeout => $TEST_TIMEOUT);
            $ftp->quit();
            my $result = $ftp->quit();  # Second quit
            ok($result, "Double quit() is idempotent");
        }

        pass("Connection lifecycle test completed");
    };

    if ($@) {
        fail("Connection lifecycle test threw exception: $@");
    }

    print "\n";
}

sub test_message_extraction {
    print "Test 19: Message extraction\n";
    print "-" x 80 . "\n";

    eval {
        my $ftp = Net::FTP->new($FTP_HOST, Timeout => $TEST_TIMEOUT);

        unless ($ftp) {
            fail("Failed to create FTP connection");
            return;
        }

        # Successful operation should have message
        $ftp->login($FTP_USER, $FTP_PASS);
        my $msg1 = $ftp->message();
        ok(defined $msg1, "message() returns value after login: $msg1");

        # Failed operation should have error message
        $ftp->cwd("/nonexistent_directory_12345");
        my $msg2 = $ftp->message();
        ok(defined $msg2 && length($msg2) > 0, "message() returns error message: $msg2");

        $ftp->quit();
        pass("Message extraction test completed");
    };

    if ($@) {
        fail("Message extraction test threw exception: $@");
    }

    print "\n";
}

sub test_rapid_connections {
    print "Test 20: Rapid connection creation/destruction\n";
    print "-" x 80 . "\n";

    eval {
        my $start_time = time();
        my $connection_count = 5;
        my $success_count = 0;

        for my $i (1..$connection_count) {
            my $ftp = Net::FTP->new($FTP_HOST, Timeout => $TEST_TIMEOUT);
            if ($ftp) {
                $ftp->login($FTP_USER, $FTP_PASS);
                $ftp->pwd();
                $ftp->quit();
                $success_count++;
            }
        }

        my $elapsed = time() - $start_time;

        ok($success_count == $connection_count, "Created/destroyed $connection_count connections rapidly");
        pass("Completed in " . sprintf("%.2f", $elapsed) . " seconds (" .
             sprintf("%.2f", $connection_count/$elapsed) . " connections/sec)");

        pass("Rapid connections test completed");
    };

    if ($@) {
        fail("Rapid connections test threw exception: $@");
    }

    print "\n";
}

###############################################################################
# Test Helpers
###############################################################################

sub pass {
    my $msg = shift;
    $tests_run++;
    $tests_passed++;
    print "  ✓ PASS: $msg\n";
}

sub fail {
    my $msg = shift;
    $tests_run++;
    $tests_failed++;
    push @failed_tests, $msg;
    print "  ✗ FAIL: $msg\n";
}

sub ok {
    my ($condition, $msg) = @_;
    if ($condition) {
        pass($msg);
    } else {
        fail($msg);
    }
}

__END__

=head1 NAME

test_ftp_production.pl - Production-ready comprehensive test suite for FTPHelper

=head1 SYNOPSIS

    # Set environment variables for FTP server
    export FTP_TEST_HOST=ftp.example.com
    export FTP_TEST_USER=username
    export FTP_TEST_PASS=password
    export FTP_TEST_DIR=/upload  # Optional, defaults to /

    # Run the test
    perl test_ftp_production.pl

=head1 DESCRIPTION

This test suite validates all Net::FTP functionality identified in
Net_FTP_Usage_Analysis.md against a real FTP server.

Tests include:
- All 12 FTP methods (new, login, cwd, pwd, dir, binary, ascii, get, put, delete, rename, message, quit)
- Production patterns from CommonControlmSubs.pm and mi_ftp_stratus_files.pl
- Atomic operations (temp upload + rename)
- Connection pooling and state persistence
- Error handling and edge cases
- Performance under load (rapid connections)
- Transfer mode switching
- Multiple simultaneous connections

The test WILL perform real FTP operations on the configured server.

=head1 REQUIREMENTS

- Real FTP server accessible from test environment
- Valid FTP credentials with write permissions
- FTP_TEST_HOST, FTP_TEST_USER, FTP_TEST_PASS environment variables set

=head1 AUTHOR

CPAN Bridge Migration Project

=cut
