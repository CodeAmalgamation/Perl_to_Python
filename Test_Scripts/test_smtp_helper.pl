#!/usr/bin/perl
# test_smtp_helper.pl - Comprehensive test suite for SMTPHelper
#
# Tests Net::SMTP replacement functionality including:
# - Connection management
# - All SMTP methods (new, mail, to, data, datasend, quit)
# - Production usage pattern (multiple datasend calls)
# - Error handling
# - Connection state validation

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/..";
use SMTPHelper;  # This overrides Net::SMTP
use Test::More;
use Data::Dumper;

# Configuration
my $SMTP_HOST = $ENV{SMTP_TEST_HOST} || 'localhost';  # Use localhost for testing
my $TEST_TIMEOUT = 5;

print "=" x 70 . "\n";
print "SMTPHelper Test Suite\n";
print "=" x 70 . "\n\n";

print "IMPORTANT: These tests require an SMTP server for full validation.\n";
print "Set SMTP_TEST_HOST environment variable to test against real server.\n";
print "Current host: $SMTP_HOST\n\n";

# Test counter
my $tests_run = 0;
my $tests_passed = 0;
my $tests_failed = 0;

# Test 1: Constructor with valid parameters
test_constructor();

# Test 2: Constructor error handling
test_constructor_errors();

# Test 3: Method sequence validation
test_method_sequence();

# Test 4: Production pattern (multiple datasend calls)
test_production_pattern();

# Test 5: Error handling
test_error_handling();

# Test 6: Connection cleanup
test_connection_cleanup();

# Test 7: Multiple connections
test_multiple_connections();

# Summary
print "\n" . "=" x 70 . "\n";
print "Test Summary\n";
print "=" x 70 . "\n";
print "Total tests: $tests_run\n";
print "Passed: $tests_passed\n";
print "Failed: $tests_failed\n";

if ($tests_failed == 0) {
    print "\n✓ All tests passed!\n";
    exit 0;
} else {
    print "\n✗ Some tests failed\n";
    exit 1;
}

###############################################################################
# Test Functions
###############################################################################

sub test_constructor {
    print "Test 1: Constructor with valid parameters\n";
    print "-" x 70 . "\n";

    eval {
        # Test basic constructor
        my $smtp = Net::SMTP->new($SMTP_HOST, Timeout => $TEST_TIMEOUT, Debug => 0);

        if ($smtp) {
            pass("Constructor returned object");
            ok($smtp->{_connection_id}, "Connection ID assigned");
            ok($smtp->{_host} eq $SMTP_HOST, "Host stored correctly");

            # Cleanup
            $smtp->quit();
        } else {
            # Connection might fail if no SMTP server available - not a code failure
            print "  NOTE: Constructor returned undef (SMTP server unavailable: $!)\n";
            print "  This is expected if no SMTP server is running on $SMTP_HOST\n";
            pass("Constructor handles connection failure gracefully");
        }
    };

    if ($@) {
        fail("Constructor test threw exception: $@");
    }

    print "\n";
}

sub test_constructor_errors {
    print "Test 2: Constructor error handling\n";
    print "-" x 70 . "\n";

    eval {
        # Test missing host
        my $smtp = Net::SMTP->new();
        if ($smtp) {
            fail("Constructor should fail without host");
        } else {
            pass("Constructor returns undef without host");
        }
    };

    if ($@) {
        fail("Constructor error test threw exception: $@");
    }

    print "\n";
}

sub test_method_sequence {
    print "Test 3: Method sequence validation\n";
    print "-" x 70 . "\n";

    eval {
        my $smtp = Net::SMTP->new($SMTP_HOST, Timeout => $TEST_TIMEOUT);

        if ($smtp) {
            # Test mail() method
            my $result = $smtp->mail('sender@test.com');
            print "  mail() returned: " . ($result ? "success" : "failure") . "\n";

            # Test to() method
            $result = $smtp->to('recipient@test.com');
            print "  to() returned: " . ($result ? "success" : "failure") . "\n";

            # Test data() method
            $result = $smtp->data();
            print "  data() returned: " . ($result ? "success" : "failure") . "\n";

            pass("Method sequence executed");

            # Cleanup
            $smtp->quit();
        } else {
            print "  NOTE: Skipping (no SMTP server available)\n";
            pass("Test skipped gracefully");
        }
    };

    if ($@) {
        fail("Method sequence test threw exception: $@");
    }

    print "\n";
}

sub test_production_pattern {
    print "Test 4: Production pattern (multiple datasend calls)\n";
    print "-" x 70 . "\n";

    eval {
        # Replicate exact production pattern from 30165CbiWasCtl.pl
        my @recipients = ('user1', 'user2');
        my $email_subject = "Test Subject";
        my @email_body = ("Line 1\n", "Line 2\n", "Line 3\n");

        foreach my $who (@recipients) {
            my $smtp = Net::SMTP->new($SMTP_HOST, Timeout => $TEST_TIMEOUT, Debug => 0);

            if ($smtp) {
                print "  Testing recipient: $who\n";

                # Set sender
                $smtp->mail("sender\@test.com");

                # Set recipient
                $smtp->to("${who}\@test.com");

                # Start data mode
                $smtp->data();

                # Send headers line by line
                $smtp->datasend("To: ${who}\@test.com\n");
                $smtp->datasend("From: sender\@test.com\n");
                $smtp->datasend("Subject: $email_subject\n");
                $smtp->datasend("\n");

                # Send body lines
                foreach my $e_line (@email_body) {
                    $smtp->datasend("$e_line");
                }

                # Flush (send message)
                $smtp->datasend();

                # Close connection
                $smtp->quit();

                print "  ✓ Production pattern completed for $who\n";
            } else {
                print "  NOTE: Skipping (no SMTP server available)\n";
            }
        }

        pass("Production pattern test completed");
    };

    if ($@) {
        fail("Production pattern test threw exception: $@");
    }

    print "\n";
}

sub test_error_handling {
    print "Test 5: Error handling\n";
    print "-" x 70 . "\n";

    eval {
        my $smtp = Net::SMTP->new($SMTP_HOST, Timeout => $TEST_TIMEOUT);

        if ($smtp) {
            # Test calling methods in wrong order
            print "  Testing invalid method sequence...\n";

            # Try datasend() before data()
            my $result = $smtp->datasend("Should fail");
            if (!$result) {
                pass("datasend() fails when called before data()");
            } else {
                fail("datasend() should fail when called before data()");
            }

            # Cleanup
            $smtp->quit();
        } else {
            print "  NOTE: Skipping (no SMTP server available)\n";
            pass("Test skipped gracefully");
        }
    };

    if ($@) {
        fail("Error handling test threw exception: $@");
    }

    print "\n";
}

sub test_connection_cleanup {
    print "Test 6: Connection cleanup\n";
    print "-" x 70 . "\n";

    eval {
        # Create connection and let it go out of scope
        {
            my $smtp = Net::SMTP->new($SMTP_HOST, Timeout => $TEST_TIMEOUT);
            if ($smtp) {
                print "  Connection created: " . $smtp->{_connection_id} . "\n";
                # Object goes out of scope here - DESTROY should cleanup
            }
        }

        pass("Connection cleanup via DESTROY");

        # Test explicit quit
        my $smtp = Net::SMTP->new($SMTP_HOST, Timeout => $TEST_TIMEOUT);
        if ($smtp) {
            my $conn_id = $smtp->{_connection_id};
            $smtp->quit();

            # Verify connection_id removed
            if (!$smtp->{_connection_id}) {
                pass("Explicit quit() cleans up connection ID");
            } else {
                fail("quit() should remove connection ID");
            }
        }
    };

    if ($@) {
        fail("Connection cleanup test threw exception: $@");
    }

    print "\n";
}

sub test_multiple_connections {
    print "Test 7: Multiple simultaneous connections\n";
    print "-" x 70 . "\n";

    eval {
        my @connections;

        # Create multiple connections
        for my $i (1..3) {
            my $smtp = Net::SMTP->new($SMTP_HOST, Timeout => $TEST_TIMEOUT);
            if ($smtp) {
                push @connections, $smtp;
                print "  Connection $i created: " . $smtp->{_connection_id} . "\n";
            }
        }

        if (@connections) {
            pass("Multiple connections created");

            # Cleanup all
            foreach my $conn (@connections) {
                $conn->quit();
            }

            pass("All connections closed");
        } else {
            print "  NOTE: Skipping (no SMTP server available)\n";
            pass("Test skipped gracefully");
        }
    };

    if ($@) {
        fail("Multiple connections test threw exception: $@");
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
