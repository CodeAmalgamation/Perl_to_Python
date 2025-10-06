#!/usr/bin/perl
use strict;
use warnings;
use lib '.';
use CPANBridge;
use Data::Dumper;

# ====================================================================
# VALIDATION & WHITELIST TEST
# ====================================================================
# Tests that all new DBI functions pass daemon validation
# Ensures whitelist configuration is correct
# ====================================================================

print "=== Validation & Whitelist Test ===\n\n";

# Enable daemon mode
$CPANBridge::DAEMON_MODE = 1;

my $test_count = 0;
my $pass_count = 0;

sub run_test {
    my ($test_name, $result) = @_;
    $test_count++;

    if ($result) {
        $pass_count++;
        print "✅ Test $test_count: $test_name - PASSED\n";
        return 1;
    } else {
        print "❌ Test $test_count: $test_name - FAILED\n";
        return 0;
    }
}

# Create bridge instance
my $bridge = CPANBridge->new();

# ====================================================================
# TEST 1: connect_cached() passes validation
# ====================================================================
print "Test 1: connect_cached() validation...\n";

my $result1 = $bridge->call_python('database', 'connect_cached', {
    dsn => 'dbi:Oracle:TEST',
    username => 'test',
    password => 'test'
});

if (run_test("connect_cached passes validation", defined $result1)) {
    # Check it's not a validation error
    if ($result1->{error} && $result1->{error} =~ /not allowed|unauthorized/i) {
        print "   ❌ VALIDATION FAILURE: $result1->{error}\n";
        run_test("connect_cached NOT blocked by whitelist", 0);
    } else {
        print "   ✅ Passed validation (function is whitelisted)\n";
        run_test("connect_cached NOT blocked by whitelist", 1);
    }
}
print "\n";

# ====================================================================
# TEST 2: bind_param_inout() passes validation
# ====================================================================
print "Test 2: bind_param_inout() validation...\n";

my $result2 = $bridge->call_python('database', 'bind_param_inout', {
    statement_id => 'test',
    param_name => ':test',
    size => 100
});

if (run_test("bind_param_inout passes validation", defined $result2)) {
    # Check it's not a validation error
    if ($result2->{error} && $result2->{error} =~ /not allowed|unauthorized/i) {
        print "   ❌ VALIDATION FAILURE: $result2->{error}\n";
        run_test("bind_param_inout NOT blocked by whitelist", 0);
    } else {
        print "   ✅ Passed validation (function is whitelisted)\n";
        run_test("bind_param_inout NOT blocked by whitelist", 1);
    }
}
print "\n";

# ====================================================================
# TEST 3: get_out_params() passes validation
# ====================================================================
print "Test 3: get_out_params() validation...\n";

my $result3 = $bridge->call_python('database', 'get_out_params', {
    statement_id => 'test'
});

if (run_test("get_out_params passes validation", defined $result3)) {
    # Check it's not a validation error
    if ($result3->{error} && $result3->{error} =~ /not allowed|unauthorized/i) {
        print "   ❌ VALIDATION FAILURE: $result3->{error}\n";
        run_test("get_out_params NOT blocked by whitelist", 0);
    } else {
        print "   ✅ Passed validation (function is whitelisted)\n";
        run_test("get_out_params NOT blocked by whitelist", 1);
    }
}
print "\n";

# ====================================================================
# TEST 4: Test invalid function is properly blocked
# ====================================================================
print "Test 4: Invalid function blocked...\n";

my $result4 = $bridge->call_python('database', 'malicious_function', {
    param => 'test'
});

if (run_test("Invalid function call returns response", defined $result4)) {
    # Should have validation error
    if ($result4->{error} && $result4->{error} =~ /not allowed|unauthorized/i) {
        print "   ✅ Correctly blocked unauthorized function\n";
        run_test("Validation correctly blocks invalid functions", 1);
    } else {
        print "   ❌ SECURITY ISSUE: Invalid function not blocked!\n";
        run_test("Validation correctly blocks invalid functions", 0);
    }
}
print "\n";

# ====================================================================
# TEST 5: All whitelisted database functions
# ====================================================================
print "Test 5: Verify all database functions in whitelist...\n";

my @expected_functions = qw(
    connect connect_cached disconnect execute_statement fetch_row fetch_all
    prepare finish_statement begin_transaction commit rollback
    execute_immediate bind_param_inout get_out_params
);

my $all_present = 1;
foreach my $func (@expected_functions) {
    my $test_result = $bridge->call_python('database', $func, {});

    if ($test_result->{error} && $test_result->{error} =~ /not allowed|unauthorized/i) {
        print "   ❌ $func is NOT whitelisted\n";
        $all_present = 0;
    }
}

if (run_test("All database functions whitelisted", $all_present)) {
    print "   ✅ All " . scalar(@expected_functions) . " functions are whitelisted\n";
}
print "\n";

# ====================================================================
# TEST SUMMARY
# ====================================================================
print "=" x 60 . "\n";
print "VALIDATION & WHITELIST TEST SUMMARY\n";
print "=" x 60 . "\n";
print "Total tests: $test_count\n";
print "Passed: $pass_count\n";
print "Failed: " . ($test_count - $pass_count) . "\n";
print "Success rate: " . sprintf("%.1f%%", ($pass_count / $test_count) * 100) . "\n\n";

if ($pass_count == $test_count) {
    print "🎉 ALL VALIDATION TESTS PASSED!\n\n";
    print "Key findings:\n";
    print "✅ connect_cached() is properly whitelisted\n";
    print "✅ bind_param_inout() is properly whitelisted\n";
    print "✅ get_out_params() is properly whitelisted\n";
    print "✅ All database functions pass validation\n";
    print "✅ Invalid functions are correctly blocked\n";
} else {
    print "❌ Some validation tests failed. Check whitelist configuration.\n";
}

print "\n=== Validation Test Complete ===\n";
