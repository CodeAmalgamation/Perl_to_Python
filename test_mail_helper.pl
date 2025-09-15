#!/usr/bin/perl
use strict;
use warnings;
use FindBin;
use lib $FindBin::Bin;
use MailHelper;
use File::Basename;

print "Testing MailHelper (Mail::Sender replacement)\n";
print "=" x 50, "\n\n";

# Test 1: Basic connectivity test
print "Test 1: Module connectivity\n";
eval {
    my $mailer = MailHelper->new(debug => 1);
    print "  ✓ MailHelper object created\n";
};
if ($@) {
    print "  ✗ Failed to create MailHelper: $@\n";
    exit 1;
}

# Test 2: Test with your exact usage pattern from mi_email_resultset.pl
print "\nTest 2: Your exact usage pattern\n";

my $from = 'test@example.com';
my $to = 'recipient@example.com';
my $subject = 'Test Email with Attachment';
my $attach = '/tmp/test_file.txt';  # Create a test file first

# Create test file
open(my $fh, '>', $attach) or die "Cannot create test file: $!";
print $fh "This is a test file for email attachment.\n";
print $fh "Line 2 of test content.\n";
close($fh);
print "  Created test file: $attach\n";

# Test the exact pattern from your code
eval {
    (new MailHelper)
        ->OpenMultipart(
            {
                smtp   => "localhost",
                from   => $from,
                to     => $to,
                subject => $subject
            }
        )
        ->Attach(
            {
                description => "Requested attached file $attach",
                ctype    => "text/plain",
                encoding  => "7BIT",
                disposition => "attachment; filename=" . basename($attach),
                file    => $attach
            }
        )
        ->Close();
    
    print "  ✓ Email sent successfully using method chaining\n";
};
if ($@) {
    print "  ✗ Failed to send email: $@\n";
    print "  Error: $Mail::Sender::Error\n" if $Mail::Sender::Error;
}

# Test 3: Simple mail file sending
print "\nTest 3: MailFile method\n";
eval {
    my $sender = MailHelper->new();
    my $result = $sender->MailFile({
        to => $to,
        from => $from,
        subject => 'Test MailFile',
        msg => "Testing MailFile method",
        file => $attach
    });
    
    if ($result > 0) {
        print "  ✓ MailFile sent successfully\n";
    } else {
        print "  ✗ MailFile failed with code: $result\n";
    }
};
if ($@) {
    print "  ✗ MailFile error: $@\n";
}

# Cleanup
unlink($attach) if -f $attach;
print "\n  Cleaned up test file\n";

print "\n" . "=" x 50 . "\n";
print "Testing complete!\n";
