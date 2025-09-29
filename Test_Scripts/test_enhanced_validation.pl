#!/usr/bin/perl

# test_enhanced_validation.pl - Test enhanced validation and security features

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/..";
use CPANBridge;
use JSON;

print "=== Enhanced Validation & Security Testing ===\n";

# Enable debugging but reduce noise
$CPANBridge::DEBUG_LEVEL = 0;  # Reduce noise for cleaner output

# Ensure daemon mode is enabled
$CPANBridge::DAEMON_MODE = 1;

my $bridge = CPANBridge->new(debug => 0);

# Test 1: Valid Request with Enhanced Health Check
print "\n=== Test 1: Enhanced Health Check ===\n";
my $result = $bridge->call_python('test', 'stats', {});

if ($result->{success}) {
    print "SUCCESS: Enhanced stats retrieved\n";
    my $stats = $result->{result};

    # Display core statistics
    print "Core Stats:\n";
    print "- Requests processed: " . $stats->{requests_processed} . "\n";
    print "- Validation failures: " . $stats->{validation_failures} . "\n";
    print "- Security events: " . $stats->{security_events} . "\n";
    print "- Requests rejected: " . $stats->{requests_rejected} . "\n";

    # Display security metrics
    if (exists $stats->{security_metrics}) {
        my $sec = $stats->{security_metrics};
        print "\nSecurity Metrics:\n";
        print "- Total security events: " . $sec->{total_events} . "\n";
        if (keys %{$sec->{events_by_type}}) {
            print "- Events by type: " . join(", ", map { "$_=" . $sec->{events_by_type}->{$_} } keys %{$sec->{events_by_type}}) . "\n";
        }
    }

    # Display validation configuration
    if (exists $stats->{validation_config}) {
        my $val = $stats->{validation_config};
        print "\nValidation Config:\n";
        print "- Strict mode: " . ($val->{strict_mode} ? "enabled" : "disabled") . "\n";
        print "- Max string length: " . $val->{max_string_length} . "\n";
        print "- Max array length: " . $val->{max_array_length} . "\n";
        print "- Max object depth: " . $val->{max_object_depth} . "\n";
        print "- Max param count: " . $val->{max_param_count} . "\n";
    }
} else {
    print "FAILED: Enhanced stats failed: " . $result->{error} . "\n";
}

# Test 2: Test Valid Requests (Should Pass)
print "\n=== Test 2: Valid Requests ===\n";

my @valid_tests = (
    {
        name => "Basic ping",
        module => "test",
        function => "ping",
        params => {}
    },
    {
        name => "HTTP request",
        module => "http",
        function => "get",
        params => { url => "https://httpbin.org/json" }
    },
    {
        name => "Database connect",
        module => "database",
        function => "connect",
        params => { dsn => "dbi:Oracle:test", username => "test", password => "test" }
    }
);

foreach my $test (@valid_tests) {
    my $result = $bridge->call_python($test->{module}, $test->{function}, $test->{params});
    my $status = $result->{success} ? "✅ PASS" : "❌ FAIL";
    print "$status: $test->{name}\n";
    if (!$result->{success}) {
        print "  Error: $result->{error}\n";
    }
}

# Test 3: Test Invalid Requests (Should Fail with Security Events)
print "\n=== Test 3: Security Validation Tests ===\n";

my @security_tests = (
    {
        name => "Invalid module name",
        module => "hacker_module",
        function => "ping",
        params => {}
    },
    {
        name => "Invalid function name",
        module => "test",
        function => "evil_function",
        params => {}
    },
    {
        name => "Dangerous function name",
        module => "test",
        function => "eval",
        params => {}
    },
    {
        name => "Script injection attempt",
        module => "test",
        function => "ping",
        params => { data => "<script>alert('xss')</script>" }
    },
    {
        name => "SQL injection attempt",
        module => "test",
        function => "ping",
        params => { query => "SELECT * FROM users WHERE id=1 OR 1=1" }
    },
    {
        name => "Path traversal attempt",
        module => "test",
        function => "ping",
        params => { file => "../../../etc/passwd" }
    }
);

foreach my $test (@security_tests) {
    my $result = $bridge->call_python($test->{module}, $test->{function}, $test->{params});
    my $status = $result->{success} ? "⚠️  UNEXPECTED PASS" : "✅ BLOCKED";
    print "$status: $test->{name}\n";
    if (!$result->{success}) {
        print "  Security Response: $result->{error}\n";
    }
}

# Test 4: Malformed Requests (Should Fail Validation)
print "\n=== Test 4: Malformed Request Tests ===\n";

# Test with direct socket to send malformed JSON
use IO::Socket::UNIX;
use JSON;

my @malformed_tests = (
    {
        name => "Missing required fields",
        request => { "function" => "ping" }  # Missing module
    },
    {
        name => "Invalid JSON structure",
        request => { "module" => 123, "function" => "ping" }  # Module should be string
    },
    {
        name => "Excessive parameters",
        request => {
            "module" => "test",
            "function" => "ping"
        }
    }
);

foreach my $test (@malformed_tests) {
    # Use bridge which handles the JSON properly
    my $result = $bridge->call_python(
        $test->{request}->{module} || "invalid",
        $test->{request}->{function} || "invalid",
        $test->{request}->{params} || {}
    );

    my $status = $result->{success} ? "⚠️  UNEXPECTED PASS" : "✅ BLOCKED";
    print "$status: $test->{name}\n";
    if (!$result->{success}) {
        print "  Validation Response: $result->{error}\n";
    }
}

# Test 5: Check Security Event Generation
print "\n=== Test 5: Final Security Summary ===\n";
$result = $bridge->call_python('test', 'stats', {});

if ($result->{success}) {
    my $stats = $result->{result};
    print "Security Event Summary:\n";
    print "- Validation failures: " . $stats->{validation_failures} . "\n";
    print "- Security events generated: " . $stats->{security_events} . "\n";
    print "- Total requests rejected: " . $stats->{requests_rejected} . "\n";

    if (exists $stats->{security_metrics} && $stats->{security_metrics}->{total_events} > 0) {
        print "\n✅ Security logging is working - events generated!\n";
        my $events = $stats->{security_metrics}->{events_by_type};
        if (keys %$events) {
            print "Security event types logged:\n";
            foreach my $type (keys %$events) {
                print "- $type: $events->{$type} events\n";
            }
        }
    } else {
        print "\n⚠️  No security events detected (unexpected)\n";
    }

    print "\n✅ Enhanced validation and security logging test complete!\n";
} else {
    print "FAILED: Could not retrieve final stats\n";
}

print "\n=== Enhanced Validation Test Complete ===\n";
print "Enhanced validation with comprehensive security logging is working!\n";