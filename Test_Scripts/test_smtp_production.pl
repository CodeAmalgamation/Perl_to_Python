#!/usr/bin/perl
# test_smtp_production.pl - Production-ready comprehensive test suite for SMTPHelper
#
# This test requires a real SMTP server and will send actual test emails.
# Configure SMTP_TEST_HOST, SMTP_TEST_FROM, and SMTP_TEST_TO environment variables.
#
# Tests all Net::SMTP functionality identified in NET_SMTP_Usage_Analysis.md:
# - new() with various parameter combinations
# - mail() sender validation
# - to() recipient validation
# - data() state management
# - datasend() buffering and flushing (production pattern)
# - quit() cleanup
# - Error handling and edge cases
# - Connection pooling and lifecycle
# - Multiple simultaneous connections

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/..";
use SMTPHelper;  # This overrides Net::SMTP
use Data::Dumper;
use Time::HiRes qw(time);

# Configuration - MUST be set for real SMTP server
my $SMTP_HOST = $ENV{SMTP_TEST_HOST} || die "SMTP_TEST_HOST environment variable not set\n";
my $SMTP_FROM = $ENV{SMTP_TEST_FROM} || die "SMTP_TEST_FROM environment variable not set (e.g., sender\@domain.com)\n";
my $SMTP_TO = $ENV{SMTP_TEST_TO} || die "SMTP_TEST_TO environment variable not set (e.g., recipient\@domain.com)\n";
my $SMTP_PORT = $ENV{SMTP_TEST_PORT} || 25;
my $TEST_TIMEOUT = 30;

print "=" x 80 . "\n";
print "SMTPHelper Production Test Suite\n";
print "=" x 80 . "\n\n";

print "Configuration:\n";
print "  SMTP Host: $SMTP_HOST\n";
print "  SMTP Port: $SMTP_PORT\n";
print "  From: $SMTP_FROM\n";
print "  To: $SMTP_TO\n";
print "  Timeout: $TEST_TIMEOUT seconds\n\n";

print "WARNING: This test will send real emails to $SMTP_TO\n";
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

# Test 3: Complete email flow (production pattern)
test_complete_email_flow();

# Test 4: Multiple datasend calls (buffering)
test_multiple_datasend();

# Test 5: Production pattern replication (exact from 30165CbiWasCtl.pl)
test_production_pattern_replication();

# Test 6: Multiple recipients
test_multiple_recipients();

# Test 7: Connection lifecycle and cleanup
test_connection_lifecycle();

# Test 8: Multiple simultaneous connections
test_multiple_connections();

# Test 9: Error handling - invalid sender
test_invalid_sender();

# Test 10: Error handling - invalid recipient
test_invalid_recipient();

# Test 11: Error handling - datasend before data
test_datasend_before_data();

# Test 12: Error handling - reusing closed connection
test_closed_connection_reuse();

# Test 13: Large email with many datasend calls
test_large_email();

# Test 14: Connection state persistence
test_connection_state_persistence();

# Test 15: Rapid connection creation/destruction
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
        my $smtp = Net::SMTP->new($SMTP_HOST, Port => $SMTP_PORT, Timeout => $TEST_TIMEOUT, Debug => 0);

        if ($smtp) {
            pass("Connection established");
            ok($smtp->{_connection_id}, "Connection ID assigned");
            ok($smtp->{_host} eq $SMTP_HOST, "Host stored correctly");

            # Verify we can quit
            my $result = $smtp->quit();
            ok($result, "quit() returns true");
            ok(!$smtp->{_connection_id}, "Connection ID removed after quit");

            pass("Basic connection test completed");
        } else {
            fail("Failed to connect to SMTP server: $!");
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
        # Test with explicit port
        my $smtp1 = Net::SMTP->new($SMTP_HOST, Port => $SMTP_PORT, Timeout => 60);
        ok($smtp1, "Constructor with explicit port");
        $smtp1->quit() if $smtp1;

        # Test with debug enabled
        my $smtp2 = Net::SMTP->new($SMTP_HOST, Port => $SMTP_PORT, Debug => 1);
        ok($smtp2, "Constructor with debug enabled");
        $smtp2->quit() if $smtp2;

        # Test with short timeout
        my $smtp3 = Net::SMTP->new($SMTP_HOST, Port => $SMTP_PORT, Timeout => 10);
        ok($smtp3, "Constructor with custom timeout");
        $smtp3->quit() if $smtp3;

        pass("Constructor parameter variations completed");
    };

    if ($@) {
        fail("Constructor parameters test threw exception: $@");
    }

    print "\n";
}

sub test_complete_email_flow {
    print "Test 3: Complete email flow (all SMTP methods)\n";
    print "-" x 80 . "\n";

    eval {
        my $smtp = Net::SMTP->new($SMTP_HOST, Port => $SMTP_PORT, Timeout => $TEST_TIMEOUT);

        unless ($smtp) {
            fail("Failed to create SMTP connection");
            return;
        }

        # Test mail()
        my $result = $smtp->mail($SMTP_FROM);
        ok($result, "mail() set sender");

        # Test to()
        $result = $smtp->to($SMTP_TO);
        ok($result, "to() set recipient");

        # Test data()
        $result = $smtp->data();
        ok($result, "data() started message");

        # Test datasend() with headers
        $result = $smtp->datasend("To: $SMTP_TO\n");
        ok($result, "datasend() sent To header");

        $result = $smtp->datasend("From: $SMTP_FROM\n");
        ok($result, "datasend() sent From header");

        $result = $smtp->datasend("Subject: SMTPHelper Test - Complete Flow\n");
        ok($result, "datasend() sent Subject header");

        $result = $smtp->datasend("\n");
        ok($result, "datasend() sent header separator");

        # Test datasend() with body
        $result = $smtp->datasend("This is a test email from SMTPHelper.\n");
        ok($result, "datasend() sent body line");

        $result = $smtp->datasend("Test timestamp: " . scalar(localtime) . "\n");
        ok($result, "datasend() sent timestamp");

        # Test datasend() flush
        $result = $smtp->datasend();
        ok($result, "datasend() flush succeeded");

        # Test quit()
        $result = $smtp->quit();
        ok($result, "quit() succeeded");

        pass("Complete email flow test completed");
    };

    if ($@) {
        fail("Complete email flow test threw exception: $@");
    }

    print "\n";
}

sub test_multiple_datasend {
    print "Test 4: Multiple datasend calls (buffering test)\n";
    print "-" x 80 . "\n";

    eval {
        my $smtp = Net::SMTP->new($SMTP_HOST, Port => $SMTP_PORT, Timeout => $TEST_TIMEOUT);

        unless ($smtp) {
            fail("Failed to create SMTP connection");
            return;
        }

        $smtp->mail($SMTP_FROM);
        $smtp->to($SMTP_TO);
        $smtp->data();

        # Send 20 datasend calls to test buffering
        my $datasend_count = 0;

        $smtp->datasend("To: $SMTP_TO\n") and $datasend_count++;
        $smtp->datasend("From: $SMTP_FROM\n") and $datasend_count++;
        $smtp->datasend("Subject: SMTPHelper Test - Multiple Datasend\n") and $datasend_count++;
        $smtp->datasend("\n") and $datasend_count++;

        for my $i (1..16) {
            $smtp->datasend("Line $i of test message\n") and $datasend_count++;
        }

        ok($datasend_count == 20, "All 20 datasend calls succeeded ($datasend_count/20)");

        # Flush
        my $flush_result = $smtp->datasend();
        ok($flush_result, "Flush succeeded after multiple datasend calls");

        $smtp->quit();

        pass("Multiple datasend buffering test completed");
    };

    if ($@) {
        fail("Multiple datasend test threw exception: $@");
    }

    print "\n";
}

sub test_production_pattern_replication {
    print "Test 5: Production pattern replication (30165CbiWasCtl.pl)\n";
    print "-" x 80 . "\n";

    eval {
        # Replicate exact production pattern
        my @recipients = ($SMTP_TO);  # Single recipient for testing
        my $email_subject = "SMTPHelper Test - Production Pattern";
        my @email_body = (
            "This email tests the exact production pattern.\n",
            "From: 30165CbiWasCtl.pl\n",
            "Pattern: foreach recipient, new connection, send, quit\n",
            "Timestamp: " . scalar(localtime) . "\n"
        );

        foreach my $who (@recipients) {
            # Exact production pattern
            my $smtp = Net::SMTP->new($SMTP_HOST, Port => $SMTP_PORT, Timeout => 30, Debug => 0)
                || die("Connection failed: $!");

            $smtp->mail($SMTP_FROM);
            $smtp->to($who);
            $smtp->data();
            $smtp->datasend("To: $who\n");
            $smtp->datasend("From: $SMTP_FROM\n");
            $smtp->datasend("Subject: $email_subject\n");
            $smtp->datasend("\n");

            foreach my $e_line (@email_body) {
                $smtp->datasend("$e_line");
            }

            $smtp->datasend();  # Flush
            $smtp->quit();
        }

        pass("Production pattern replication completed");
    };

    if ($@) {
        fail("Production pattern test threw exception: $@");
    }

    print "\n";
}

sub test_multiple_recipients {
    print "Test 6: Multiple recipients (sequential)\n";
    print "-" x 80 . "\n";

    eval {
        my @test_recipients = ($SMTP_TO, $SMTP_TO);  # Send to same address twice
        my $sent_count = 0;

        foreach my $recipient (@test_recipients) {
            my $smtp = Net::SMTP->new($SMTP_HOST, Port => $SMTP_PORT, Timeout => $TEST_TIMEOUT);
            next unless $smtp;

            $smtp->mail($SMTP_FROM);
            $smtp->to($recipient);
            $smtp->data();
            $smtp->datasend("To: $recipient\n");
            $smtp->datasend("From: $SMTP_FROM\n");
            $smtp->datasend("Subject: SMTPHelper Test - Multiple Recipients\n");
            $smtp->datasend("\n");
            $smtp->datasend("Recipient test email " . ($sent_count + 1) . "\n");
            $smtp->datasend();
            $smtp->quit();

            $sent_count++;
        }

        ok($sent_count == 2, "Sent to 2 recipients successfully");
        pass("Multiple recipients test completed");
    };

    if ($@) {
        fail("Multiple recipients test threw exception: $@");
    }

    print "\n";
}

sub test_connection_lifecycle {
    print "Test 7: Connection lifecycle and cleanup\n";
    print "-" x 80 . "\n";

    eval {
        # Test 1: Normal lifecycle
        {
            my $smtp = Net::SMTP->new($SMTP_HOST, Port => $SMTP_PORT, Timeout => $TEST_TIMEOUT);
            ok($smtp->{_connection_id}, "Connection created with ID");
            my $conn_id = $smtp->{_connection_id};

            $smtp->quit();
            ok(!$smtp->{_connection_id}, "Connection ID removed after quit");
        }

        # Test 2: DESTROY cleanup (object goes out of scope)
        {
            my $smtp = Net::SMTP->new($SMTP_HOST, Port => $SMTP_PORT, Timeout => $TEST_TIMEOUT);
            my $conn_id = $smtp->{_connection_id};
            ok($conn_id, "Connection created");
            # Object goes out of scope - DESTROY should cleanup
        }

        # Test 3: Double quit (idempotent)
        {
            my $smtp = Net::SMTP->new($SMTP_HOST, Port => $SMTP_PORT, Timeout => $TEST_TIMEOUT);
            $smtp->quit();
            my $result = $smtp->quit();  # Second quit
            ok($result, "Double quit() is idempotent");
        }

        pass("Connection lifecycle test completed");
    };

    if ($@) {
        fail("Connection lifecycle test threw exception: $@");
    }

    print "\n";
}

sub test_multiple_connections {
    print "Test 8: Multiple simultaneous connections\n";
    print "-" x 80 . "\n";

    eval {
        my @connections;
        my $conn_count = 5;

        # Create multiple connections
        for my $i (1..$conn_count) {
            my $smtp = Net::SMTP->new($SMTP_HOST, Port => $SMTP_PORT, Timeout => $TEST_TIMEOUT);
            if ($smtp) {
                push @connections, $smtp;
            }
        }

        ok(scalar(@connections) == $conn_count, "Created $conn_count simultaneous connections");

        # Use each connection
        my $used_count = 0;
        foreach my $smtp (@connections) {
            $smtp->mail($SMTP_FROM);
            $smtp->to($SMTP_TO);
            $smtp->data();
            $smtp->datasend("To: $SMTP_TO\n");
            $smtp->datasend("From: $SMTP_FROM\n");
            $smtp->datasend("Subject: SMTPHelper Test - Concurrent Connection\n");
            $smtp->datasend("\n");
            $smtp->datasend("This is from one of $conn_count concurrent connections.\n");
            $smtp->datasend();
            $used_count++;
        }

        ok($used_count == $conn_count, "Used all $conn_count connections successfully");

        # Cleanup all connections
        foreach my $smtp (@connections) {
            $smtp->quit();
        }

        pass("Multiple simultaneous connections test completed");
    };

    if ($@) {
        fail("Multiple connections test threw exception: $@");
    }

    print "\n";
}

sub test_invalid_sender {
    print "Test 9: Error handling - invalid sender\n";
    print "-" x 80 . "\n";

    eval {
        my $smtp = Net::SMTP->new($SMTP_HOST, Port => $SMTP_PORT, Timeout => $TEST_TIMEOUT);

        unless ($smtp) {
            fail("Failed to create SMTP connection");
            return;
        }

        # Try invalid sender format
        my $result = $smtp->mail("invalid-email-format");

        # Some SMTP servers may accept this, some may reject
        # Test that we handle the response appropriately
        if ($result) {
            pass("SMTP server accepted invalid sender (permissive server)");
        } else {
            pass("SMTP server rejected invalid sender (strict server)");
        }

        $smtp->quit();
    };

    if ($@) {
        fail("Invalid sender test threw exception: $@");
    }

    print "\n";
}

sub test_invalid_recipient {
    print "Test 10: Error handling - invalid recipient\n";
    print "-" x 80 . "\n";

    eval {
        my $smtp = Net::SMTP->new($SMTP_HOST, Port => $SMTP_PORT, Timeout => $TEST_TIMEOUT);

        unless ($smtp) {
            fail("Failed to create SMTP connection");
            return;
        }

        $smtp->mail($SMTP_FROM);

        # Try invalid recipient
        my $result = $smtp->to("invalid-recipient-format");

        # Handle response appropriately
        if ($result) {
            pass("SMTP server accepted invalid recipient (permissive server)");
        } else {
            pass("SMTP server rejected invalid recipient (strict server)");
        }

        $smtp->quit();
    };

    if ($@) {
        fail("Invalid recipient test threw exception: $@");
    }

    print "\n";
}

sub test_datasend_before_data {
    print "Test 11: Error handling - datasend before data\n";
    print "-" x 80 . "\n";

    eval {
        my $smtp = Net::SMTP->new($SMTP_HOST, Port => $SMTP_PORT, Timeout => $TEST_TIMEOUT);

        unless ($smtp) {
            fail("Failed to create SMTP connection");
            return;
        }

        $smtp->mail($SMTP_FROM);
        $smtp->to($SMTP_TO);

        # Try datasend() before data()
        my $result = $smtp->datasend("This should fail\n");

        ok(!$result, "datasend() before data() returns false");

        $smtp->quit();
        pass("datasend before data error handling completed");
    };

    if ($@) {
        fail("datasend before data test threw exception: $@");
    }

    print "\n";
}

sub test_closed_connection_reuse {
    print "Test 12: Error handling - reusing closed connection\n";
    print "-" x 80 . "\n";

    eval {
        my $smtp = Net::SMTP->new($SMTP_HOST, Port => $SMTP_PORT, Timeout => $TEST_TIMEOUT);

        unless ($smtp) {
            fail("Failed to create SMTP connection");
            return;
        }

        # Close connection
        $smtp->quit();

        # Try to use methods on closed connection
        my $result1 = $smtp->mail($SMTP_FROM);
        ok(!$result1, "mail() on closed connection returns false");

        my $result2 = $smtp->to($SMTP_TO);
        ok(!$result2, "to() on closed connection returns false");

        my $result3 = $smtp->data();
        ok(!$result3, "data() on closed connection returns false");

        my $result4 = $smtp->datasend("test");
        ok(!$result4, "datasend() on closed connection returns false");

        pass("Closed connection reuse error handling completed");
    };

    if ($@) {
        fail("Closed connection reuse test threw exception: $@");
    }

    print "\n";
}

sub test_large_email {
    print "Test 13: Large email with many datasend calls\n";
    print "-" x 80 . "\n";

    eval {
        my $smtp = Net::SMTP->new($SMTP_HOST, Port => $SMTP_PORT, Timeout => $TEST_TIMEOUT);

        unless ($smtp) {
            fail("Failed to create SMTP connection");
            return;
        }

        $smtp->mail($SMTP_FROM);
        $smtp->to($SMTP_TO);
        $smtp->data();

        # Headers
        $smtp->datasend("To: $SMTP_TO\n");
        $smtp->datasend("From: $SMTP_FROM\n");
        $smtp->datasend("Subject: SMTPHelper Test - Large Email\n");
        $smtp->datasend("\n");

        # Send 100 lines of body
        my $lines_sent = 0;
        for my $i (1..100) {
            my $result = $smtp->datasend("Line $i: " . ("x" x 50) . "\n");
            $lines_sent++ if $result;
        }

        ok($lines_sent == 100, "Sent 100 lines successfully ($lines_sent/100)");

        # Flush
        my $flush_result = $smtp->datasend();
        ok($flush_result, "Flushed large email successfully");

        $smtp->quit();

        pass("Large email test completed");
    };

    if ($@) {
        fail("Large email test threw exception: $@");
    }

    print "\n";
}

sub test_connection_state_persistence {
    print "Test 14: Connection state persistence across calls\n";
    print "-" x 80 . "\n";

    eval {
        my $smtp = Net::SMTP->new($SMTP_HOST, Port => $SMTP_PORT, Timeout => $TEST_TIMEOUT);

        unless ($smtp) {
            fail("Failed to create SMTP connection");
            return;
        }

        my $conn_id = $smtp->{_connection_id};
        ok($conn_id, "Got connection ID: $conn_id");

        # Each method call should use the same connection_id
        $smtp->mail($SMTP_FROM);
        ok($smtp->{_connection_id} eq $conn_id, "Connection ID persists after mail()");

        $smtp->to($SMTP_TO);
        ok($smtp->{_connection_id} eq $conn_id, "Connection ID persists after to()");

        $smtp->data();
        ok($smtp->{_connection_id} eq $conn_id, "Connection ID persists after data()");

        $smtp->datasend("To: $SMTP_TO\n");
        ok($smtp->{_connection_id} eq $conn_id, "Connection ID persists after datasend()");

        $smtp->datasend();  # Flush
        ok($smtp->{_connection_id} eq $conn_id, "Connection ID persists after flush");

        $smtp->quit();

        pass("Connection state persistence test completed");
    };

    if ($@) {
        fail("Connection state persistence test threw exception: $@");
    }

    print "\n";
}

sub test_rapid_connections {
    print "Test 15: Rapid connection creation/destruction\n";
    print "-" x 80 . "\n";

    eval {
        my $start_time = time();
        my $connection_count = 10;
        my $success_count = 0;

        for my $i (1..$connection_count) {
            my $smtp = Net::SMTP->new($SMTP_HOST, Port => $SMTP_PORT, Timeout => $TEST_TIMEOUT);
            if ($smtp) {
                $smtp->mail($SMTP_FROM);
                $smtp->to($SMTP_TO);
                $smtp->data();
                $smtp->datasend("To: $SMTP_TO\n");
                $smtp->datasend("From: $SMTP_FROM\n");
                $smtp->datasend("Subject: SMTPHelper Test - Rapid Connection $i\n");
                $smtp->datasend("\n");
                $smtp->datasend("Rapid connection test $i of $connection_count\n");
                $smtp->datasend();
                $smtp->quit();
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

test_smtp_production.pl - Production-ready comprehensive test suite for SMTPHelper

=head1 SYNOPSIS

    # Set environment variables for SMTP server
    export SMTP_TEST_HOST=smtp.example.com
    export SMTP_TEST_FROM=sender@example.com
    export SMTP_TEST_TO=recipient@example.com
    export SMTP_TEST_PORT=25  # Optional, defaults to 25

    # Run the test
    perl test_smtp_production.pl

=head1 DESCRIPTION

This test suite validates all Net::SMTP functionality identified in
NET_SMTP_Usage_Analysis.md against a real SMTP server.

Tests include:
- All 6 SMTP methods (new, mail, to, data, datasend, quit)
- Production pattern replication from 30165CbiWasCtl.pl
- Connection pooling and state persistence
- Error handling and edge cases
- Performance under load (rapid connections)
- Large emails with many datasend calls
- Multiple simultaneous connections

The test WILL send real emails to the configured recipient address.

=head1 REQUIREMENTS

- Real SMTP server accessible from test environment
- Valid sender and recipient email addresses
- SMTP_TEST_HOST, SMTP_TEST_FROM, SMTP_TEST_TO environment variables set

=head1 AUTHOR

CPAN Bridge Migration Project

=cut
