#!/usr/bin/perl
#
# test_ftp_simple_login.pl - Simple FTP login test
#
# This is a minimal test that just connects and logs into the FTP server.
# Perfect for quickly verifying the FTP setup is working.

use strict;
use warnings;
use lib "/Users/shubhamdixit/Perl_to_Python";
use FTPHelper;
use Data::Dumper;

print "=" x 70 . "\n";
print "Simple FTP Login Test\n";
print "=" x 70 . "\n\n";

# Configuration
my $FTP_HOST = $ENV{FTP_TEST_HOST} || '127.0.0.1';
my $FTP_USER = $ENV{FTP_TEST_USER} || 'ftptest';
my $FTP_PASS = $ENV{FTP_TEST_PASS} || 'ftptest123';
my $TIMEOUT  = 10;

print "Configuration:\n";
print "  Host: $FTP_HOST\n";
print "  User: $FTP_USER\n";
print "  Timeout: ${TIMEOUT}s\n\n";

print "Attempting to connect and login...\n\n";

# Create FTP connection
my $ftp = Net::FTP->new($FTP_HOST, Timeout => $TIMEOUT, Debug => 0);

unless ($ftp) {
    print "✗ FAILED: Could not connect to FTP server\n";
    print "  Error: $!\n";
    exit 1;
}

print "✓ Connected to FTP server: $FTP_HOST\n";
print "  Connection ID: " . $ftp->{_connection_id} . "\n\n";

# Login
my $login_result = $ftp->login($FTP_USER, $FTP_PASS);

unless ($login_result) {
    print "✗ FAILED: Login failed\n";
    print "  Error: " . $ftp->message() . "\n";
    $ftp->quit();
    exit 1;
}

print "✓ Login successful\n\n";

# Get current directory
my $pwd = $ftp->pwd();
print "Current directory: $pwd\n";

# Get welcome message
my $msg = $ftp->message();
print "Server message: $msg\n" if $msg;

# Generic routine to create a file and upload to FTP
sub create_and_upload {
    my ($ftp, $filename) = @_;

    print "\nCreating and uploading: $filename\n";
    print "-" x 70 . "\n";

    # Create local file with content
    my $local_file = "/tmp/" . $filename;

    if (open my $fh, '>', $local_file) {
        # Get current date and time
        my ($sec, $min, $hour, $mday, $mon, $year) = localtime();
        $year += 1900;
        $mon += 1;
        my $datetime = sprintf("%04d-%02d-%02d %02d:%02d:%02d",
                              $year, $mon, $mday, $hour, $min, $sec);

        # Write content
        print $fh "This is just a file, however if you want facts, Messi is the GOAT of soccer\n";
        print $fh "\n";
        print $fh "Created on: $datetime\n";
        close $fh;

        print "✓ Local file created: $local_file\n";

        # Upload to FTP server
        my $result = $ftp->put($local_file, $filename);

        if ($result) {
            print "✓ File uploaded successfully to FTP server\n";
        } else {
            print "✗ File upload failed\n";
            print "  Error: " . $ftp->message() . "\n";
        }
    } else {
        print "✗ Could not create local file: $!\n";
    }
}

# Generic routine to delete a file from FTP server
sub delete_file {
    my ($ftp, $filename) = @_;

    print "\nAttempting to delete: $filename\n";
    print "-" x 70 . "\n";

    my $result = $ftp->delete($filename);

    if ($result) {
        print "✓ File deleted successfully from FTP server\n";
    } else {
        print "✗ File deletion failed\n";
        print "  Error: " . $ftp->message() . "\n";
    }
}

# Generic download and display routine
sub download_and_display {
    my ($ftp, $remote_file) = @_;

    print "\nAttempting to download: $remote_file\n";
    print "-" x 70 . "\n";

    my $local_file = "/tmp/downloaded_" . $remote_file;
    my $result = $ftp->get($remote_file, $local_file);

    if ($result) {
        print "✓ File downloaded successfully to: $local_file\n";

        # Read and display file contents
        if (open my $fh, '<', $local_file) {
            print "\nFile Contents:\n";
            print "=" x 70 . "\n";
            while (my $line = <$fh>) {
                print $line;
            }
            close $fh;
            print "=" x 70 . "\n";
        } else {
            print "✗ Could not read downloaded file: $!\n";
        }
    } else {
        print "✗ File download failed\n";
        print "  Error: " . $ftp->message() . "\n";
    }
}

# Test 1: Create and upload a new file
create_and_upload($ftp, "messi_facts.txt");

# Test 2: Download and display the file we just uploaded
download_and_display($ftp, "messi_facts.txt");

# Test 3: Delete the file we just created
delete_file($ftp, "messi_facts.txt");

# Test 4: Try to download the deleted file (should fail)
download_and_display($ftp, "messi_facts.txt");

# Test 5: Try to delete a non-existent file
delete_file($ftp, "file_that_never_existed.txt");

# Test 6: Download existing file
download_and_display($ftp, "ftp_demo.txt");

# Disconnect
print "\nDisconnecting...\n";
$ftp->quit();

print "\n" . "=" x 70 . "\n";
print "✓ ALL TESTS PASSED - FTP Login Successful\n";
print "=" x 70 . "\n";

exit 0;
