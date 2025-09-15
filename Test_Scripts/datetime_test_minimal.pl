#!/usr/bin/perl
# test_datetime_minimal.pl - Focused test suite for DateTimeHelper
# Tests only the DateTime->now->epoch pattern actually used in your codebase

use strict;
use warnings;
use lib '.';
use DateTimeHelper;

# Test tracking
our $TEST_COUNT = 0;
our $PASS_COUNT = 0;
our $FAIL_COUNT = 0;

print "=" x 60 . "\n";
print "DateTimeHelper Minimal Test Suite\n";
print "Based on actual usage: DateTime->now->epoch\n";
print "=" x 60 . "\n\n";

# Test 1: Basic DateTime->now->epoch functionality
test_basic_now_epoch();

# Test 2: Your exact EPV usage pattern
test_epv_pattern();

# Test 3: Multiple calls consistency
test_multiple_calls();

# Test 4: Performance validation
test_performance();

# Test 5: Error handling
test_error_handling();

# Test Summary
print "\n" . "=" x 60 . "\n";
print "TEST SUMMARY\n";
print "=" x 60 . "\n";
print "Total Tests: $TEST_COUNT\n";
print "Passed: $PASS_COUNT\n";
print "Failed: $FAIL_COUNT\n";

if ($FAIL_COUNT == 0) {
    print "\nSUCCESS: DateTimeHelper ready for production!\n";
    print "Ready to replace: chomp(\$ini_KEY = &GetKey(..., DateTime->now->epoch, 20));\n";
    exit 0;
} else {
    print "\nFAILED: Review failures before deployment\n";
    exit 1;
}

#================================================================
# TEST FUNCTIONS
#================================================================

sub test_basic_now_epoch {
    print_test_header("Basic DateTime->now->epoch Pattern");
    
    # Test 1a: DateTime->now() returns object
    my $dt = eval { DateTimeHelper->now() };
    test_result("DateTimeHelper->now()", defined($dt) && !$@, $@ || "Success");
    
    # Test 1b: Object can call ->epoch()
    my $timestamp;
    if ($dt) {
        $timestamp = eval { $dt->epoch() };
        test_result("->epoch() method", defined($timestamp) && !$@, $@ || "Success");
    }
    
    # Test 1c: Timestamp is reasonable (within last 24 hours)
    if (defined($timestamp)) {
        my $current_time = time();
        my $diff = abs($timestamp - $current_time);
        test_result("Timestamp reasonable", $diff < 86400, "Diff: ${diff}s");
    }
    
    # Test 1d: Chained call pattern
    my $chained_timestamp = eval { DateTimeHelper->now->epoch };
    test_result("Chained ->now->epoch", defined($chained_timestamp) && !$@, $@ || "Success");
    
    print_test_footer();
}

sub test_epv_pattern {
    print_test_header("EPV Key Generation Pattern");
    
    # Simulate your exact usage pattern
    my ($ini_EPV_LIB, $ini_APP_ID, $ini_QUERY) = ("lib", "app", "query");
    
    # Test 2a: GetKey function call simulation
    my $ini_KEY;
    eval {
        # Your exact pattern: DateTimeHelper->now->epoch
        chomp($ini_KEY = GetKey($ini_EPV_LIB, $ini_APP_ID, $ini_QUERY, DateTimeHelper->now->epoch, 20));
    };
    
    test_result("EPV GetKey pattern", defined($ini_KEY) && !$@, $@ || "Success");
    
    # Test 2b: Verify timestamp was passed correctly
    if (defined($ini_KEY)) {
        test_result("GetKey received timestamp", $ini_KEY =~ /timestamp:\d+/, "Key format check");
    }
    
    print_test_footer();
}

sub test_multiple_calls {
    print_test_header("Multiple Calls Consistency");
    
    # Test 3a: Multiple calls return increasing timestamps
    my @timestamps;
    for my $i (1..3) {
        my $ts = eval { DateTimeHelper->now->epoch };
        if (defined($ts)) {
            push @timestamps, $ts;
            select(undef, undef, undef, 0.1); # Brief delay
        }
    }
    
    test_result("Got multiple timestamps", scalar(@timestamps) == 3, "Count: " . scalar(@timestamps));
    
    # Test 3b: Timestamps are increasing (or equal due to timing)
    my $increasing = 1;
    for my $i (1..$#timestamps) {
        if ($timestamps[$i] < $timestamps[$i-1]) {
            $increasing = 0;
            last;
        }
    }
    test_result("Timestamps increasing", $increasing, "Time progression check");
    
    print_test_footer();
}

sub test_performance {
    print_test_header("Performance Validation");
    
    # Test 4a: Time multiple operations
    my $iterations = 10;
    my $start_time = time();
    my $success_count = 0;
    
    for my $i (1..$iterations) {
        my $ts = eval { DateTimeHelper->now->epoch };
        $success_count++ if defined($ts) && !$@;
    }
    
    my $duration = time() - $start_time;
    my $avg_ms = ($duration / $iterations) * 1000;
    
    test_result("Performance test", $success_count == $iterations, 
               sprintf("%.1fms avg per call", $avg_ms));
    
    # Test 4b: Performance acceptable for production (< 100ms per call)
    test_result("Performance acceptable", $avg_ms < 100, 
               sprintf("%.1fms < 100ms threshold", $avg_ms));
    
    print_test_footer();
}

sub test_error_handling {
    print_test_header("Error Handling");
    
    # Test 5a: Bridge communication error handling
    # (This would require mocking the bridge failure, so we test basic error cases)
    
    # Test 5b: Object creation with invalid data
    my $obj = eval { DateTimeHelper::Object->new(undef) };
    test_result("Handles undef gracefully", defined($obj), "Object creation");
    
    if ($obj) {
        my $epoch = eval { $obj->epoch() };
        test_result("Epoch from undef", !defined($epoch) || $epoch == 0, "Graceful degradation");
    }
    
    print_test_footer();
}

#================================================================
# UTILITY FUNCTIONS  
#================================================================

sub test_result {
    my ($test_name, $condition, $details) = @_;
    
    $TEST_COUNT++;
    
    if ($condition) {
        $PASS_COUNT++;
        print "PASS: $test_name\n";
    } else {
        $FAIL_COUNT++;
        print "FAIL: $test_name";
        print " - $details" if $details;
        print "\n";
    }
}

sub print_test_header {
    my $title = shift;
    print "\n" . "-" x 50 . "\n";
    print "$title\n";
    print "-" x 50 . "\n";
}

sub print_test_footer {
    print "\n";
}

# Mock GetKey function to simulate EPV usage
sub GetKey {
    my ($epv_lib, $app_id, $query, $timestamp, $timeout) = @_;
    
    # Simulate EPV key generation with timestamp
    return "mock_key_timestamp:$timestamp";
}