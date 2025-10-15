#!/usr/bin/perl
#
# test_http_comprehensive.pl - Comprehensive HTTP/LWP/Mechanize testing
#
# This test suite validates HTTPHelper against all patterns documented in
# LWP_UserAgent&WWW_Mechanize_UsageAnalysis.md
#
# Test Coverage:
# - LWP::UserAgent: Object creation, configuration, HTTP methods
# - HTTP::Request: Object creation, headers, content
# - HTTP::Response: Status checking, content extraction
# - WWW::Mechanize: Browser simulation patterns
# - SSL/HTTPS support
# - Error handling patterns
# - Timeout configuration
# - Form-encoded POST
#

use strict;
use warnings;
use lib "/Users/shubhamdixit/Perl_to_Python";
use HTTPHelper;
use Data::Dumper;
use JSON::PP;

# Test configuration
my $VERBOSE = $ENV{TEST_VERBOSE} || 0;
my $TEST_HOST = $ENV{HTTP_TEST_HOST} || 'httpbin.org';

# Test statistics
my $total_tests = 0;
my $passed_tests = 0;
my $failed_tests = 0;
my @test_results;

print "=" x 80 . "\n";
print "HTTPHelper Comprehensive Test Suite\n";
print "=" x 80 . "\n";
print "Test Host: $TEST_HOST\n";
print "Test Start: " . localtime() . "\n\n";

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
    print "  ✓ $message\n" if $VERBOSE;
    return 1;
}

sub assert_equals {
    my ($actual, $expected, $message) = @_;
    if ($actual ne $expected) {
        die "Assertion failed: $message\n  Expected: $expected\n  Actual: $actual\n";
    }
    print "  ✓ $message\n" if $VERBOSE;
    return 1;
}

sub assert_contains {
    my ($haystack, $needle, $message) = @_;
    if (index($haystack, $needle) == -1) {
        die "Assertion failed: $message\n  String '$needle' not found in content\n";
    }
    print "  ✓ $message\n" if $VERBOSE;
    return 1;
}

sub assert_status_code {
    my ($response, $expected, $message) = @_;
    my $actual = $response->code();
    if ($actual != $expected) {
        die "Assertion failed: $message\n  Expected: $expected\n  Actual: $actual\n  Status Line: " . $response->status_line() . "\n";
    }
    print "  ✓ $message (status $actual)\n" if $VERBOSE;
    return 1;
}

# =============================================================================
# SECTION 1: LWP::UserAgent Object Creation (Pattern 1)
# Usage: 30166mi_job_starter.pl, mi_job_starter.pl
# =============================================================================

run_test("LWP::UserAgent - Basic instantiation", sub {
    my $user_agent = new LWP::UserAgent;

    assert(defined $user_agent, "UserAgent object created");
    assert(ref($user_agent) eq 'HTTPHelper', "Object is HTTPHelper instance");

    # Test default timeout (180 seconds per documentation)
    my $timeout = $user_agent->timeout();
    assert_equals($timeout, 180, "Default timeout is 180 seconds");

    return 1;
});

run_test("LWP::UserAgent - Agent string customization", sub {
    my $user_agent = new LWP::UserAgent;

    # Get default agent
    my $default_agent = $user_agent->agent();
    assert($default_agent =~ /LWP/, "Default agent contains 'LWP'");

    # Customize agent (documentation pattern)
    $user_agent->agent("AgentName/0.1 " . $user_agent->agent);
    my $custom_agent = $user_agent->agent();

    assert($custom_agent =~ /^AgentName\/0\.1/, "Custom agent prefix added");
    assert($custom_agent =~ /LWP/, "Original agent string preserved");

    return 1;
});

run_test("LWP::UserAgent - Timeout configuration", sub {
    my $user_agent = new LWP::UserAgent;

    # Set custom timeout (documentation pattern)
    $user_agent->timeout(30);
    my $timeout = $user_agent->timeout();

    assert_equals($timeout, 30, "Timeout set to 30 seconds");

    # Set timeout like job starter scripts (180 seconds)
    $user_agent->timeout(180);
    assert_equals($user_agent->timeout(), 180, "Timeout set to 180 seconds");

    return 1;
});

# =============================================================================
# SECTION 2: LWP::UserAgent Object Creation (Pattern 2)
# Usage: HpsmTicket.pm
# =============================================================================

run_test("LWP::UserAgent - Direct instantiation with defaults", sub {
    my $user_agent = LWP::UserAgent->new;

    assert(defined $user_agent, "UserAgent object created");
    assert_equals($user_agent->timeout(), 180, "Default timeout is 180");
    assert($user_agent->agent() =~ /LWP/, "Default agent is set");

    return 1;
});

# =============================================================================
# SECTION 3: HTTP::Request Object Creation and Usage
# Usage: 30166mi_job_starter.pl, mi_job_starter.pl
# =============================================================================

run_test("HTTP::Request - POST object creation", sub {
    my $URL = "http://$TEST_HOST/post";
    my $web_request = new HTTP::Request POST => $URL;

    assert(defined $web_request, "Request object created");
    assert_equals($web_request->{method}, 'POST', "Method is POST");
    assert_equals($web_request->{url}, $URL, "URL is set");

    return 1;
});

run_test("HTTP::Request - Content-Type setting", sub {
    my $web_request = new HTTP::Request POST => "http://$TEST_HOST/post";

    # Set content type (documentation pattern)
    $web_request->content_type('application/x-www-form-urlencoded');

    my $content_type = $web_request->content_type();
    assert_equals($content_type, 'application/x-www-form-urlencoded',
                  "Content-Type set correctly");

    return 1;
});

run_test("HTTP::Request - Content setting", sub {
    my $web_request = new HTTP::Request POST => "http://$TEST_HOST/post";

    my $content_string = "param1=value1&param2=value2&param3=value3";
    $web_request->content($content_string);

    my $content = $web_request->content();
    assert_equals($content, $content_string, "Content set correctly");

    return 1;
});

run_test("HTTP::Request - GET object creation", sub {
    my $URL = "http://$TEST_HOST/get";
    my $web_request = new HTTP::Request GET => $URL;

    assert(defined $web_request, "Request object created");
    assert_equals($web_request->{method}, 'GET', "Method is GET");
    assert_equals($web_request->{url}, $URL, "URL is set");

    return 1;
});

# =============================================================================
# SECTION 4: HTTP Request Execution via request()
# Usage: All documented scripts
# =============================================================================

run_test("LWP::UserAgent - Execute POST request via HTTP::Request", sub {
    my $user_agent = new LWP::UserAgent;
    $user_agent->timeout(30);

    # Create POST request (documentation pattern)
    my $URL = "http://$TEST_HOST/post";
    my $web_request = new HTTP::Request POST => $URL;
    $web_request->content_type('application/x-www-form-urlencoded');
    $web_request->content("param1=test&param2=value");

    # Execute request
    my $response = $user_agent->request($web_request);

    assert(defined $response, "Response received");
    assert($response->is_success, "Request successful");
    assert_status_code($response, 200, "Status code is 200");

    my $content = $response->content();
    assert($content, "Response has content");
    assert_contains($content, "param1", "Response contains param1");

    return 1;
});

run_test("LWP::UserAgent - Execute GET request via HTTP::Request", sub {
    my $user_agent = new LWP::UserAgent;

    my $URL = "http://$TEST_HOST/get";
    my $web_request = new HTTP::Request GET => $URL;

    my $response = $user_agent->request($web_request);

    assert($response->is_success, "GET request successful");
    assert_status_code($response, 200, "Status code is 200");

    return 1;
});

# =============================================================================
# SECTION 5: Direct HTTP Methods (get and post)
# Usage: HpsmTicket.pm, general usage
# =============================================================================

run_test("LWP::UserAgent - Direct GET method", sub {
    my $user_agent = new LWP::UserAgent;

    my $response = $user_agent->get("http://$TEST_HOST/get");

    assert($response->is_success, "GET request successful");
    assert_status_code($response, 200, "Status code is 200");

    my $content = $response->content();
    assert($content, "Response has content");

    return 1;
});

run_test("LWP::UserAgent - Direct POST with hashref (HpsmTicket.pm pattern)", sub {
    my $user_agent = LWP::UserAgent->new;

    # Documentation pattern: $ua->post($URL, \%postData)
    my %postData = (
        param1 => 'value1',
        param2 => 'value2',
        param3 => 'test data'
    );

    my $response = $user_agent->post("http://$TEST_HOST/post", \%postData);

    assert($response->is_success, "POST with hashref successful");
    assert_status_code($response, 200, "Status code is 200");

    my $content = $response->content();
    assert_contains($content, "param1", "Response contains param1");
    assert_contains($content, "value1", "Response contains value1");

    return 1;
});

run_test("LWP::UserAgent - Direct POST with Content parameter", sub {
    my $user_agent = new LWP::UserAgent;

    my $form_content = "key1=val1&key2=val2";
    my $response = $user_agent->post(
        "http://$TEST_HOST/post",
        Content_Type => 'application/x-www-form-urlencoded',
        Content => $form_content
    );

    assert($response->is_success, "POST with Content successful");
    assert_status_code($response, 200, "Status code is 200");

    return 1;
});

# =============================================================================
# SECTION 6: Response Handling
# Usage: All documented scripts
# =============================================================================

run_test("HTTP::Response - is_success method", sub {
    my $user_agent = new LWP::UserAgent;

    # Test successful response
    my $response = $user_agent->get("http://$TEST_HOST/status/200");
    assert($response->is_success, "200 status is success");

    # Test failure response
    my $error_response = $user_agent->get("http://$TEST_HOST/status/404");
    assert(!$error_response->is_success, "404 status is not success");

    return 1;
});

run_test("HTTP::Response - content method", sub {
    my $user_agent = new LWP::UserAgent;
    my $response = $user_agent->get("http://$TEST_HOST/html");

    assert($response->is_success, "Request successful");

    my $response_content = $response->content;
    assert($response_content, "Content retrieved");
    assert(length($response_content) > 0, "Content is not empty");

    return 1;
});

run_test("HTTP::Response - decoded_content method", sub {
    my $user_agent = new LWP::UserAgent;
    my $response = $user_agent->get("http://$TEST_HOST/html");

    my $decoded = $response->decoded_content;
    assert($decoded, "Decoded content retrieved");
    assert(length($decoded) > 0, "Decoded content is not empty");

    return 1;
});

run_test("HTTP::Response - status_line method", sub {
    my $user_agent = new LWP::UserAgent;
    my $response = $user_agent->get("http://$TEST_HOST/status/200");

    my $status_line = $response->status_line;
    assert($status_line, "Status line retrieved");
    assert($status_line =~ /200/, "Status line contains 200");

    # Test error status line
    my $error_response = $user_agent->get("http://$TEST_HOST/status/404");
    my $error_line = $error_response->status_line;
    assert($error_line =~ /404/, "Error status line contains 404");

    return 1;
});

run_test("HTTP::Response - code method", sub {
    my $user_agent = new LWP::UserAgent;

    my $response = $user_agent->get("http://$TEST_HOST/status/200");
    assert_equals($response->code(), 200, "Code is 200");

    my $response_404 = $user_agent->get("http://$TEST_HOST/status/404");
    assert_equals($response_404->code(), 404, "Code is 404");

    return 1;
});

run_test("HTTP::Response - message method", sub {
    my $user_agent = new LWP::UserAgent;
    my $response = $user_agent->get("http://$TEST_HOST/status/200");

    my $message = $response->message;
    assert($message, "Message retrieved");

    return 1;
});

# =============================================================================
# SECTION 7: Error Handling Patterns
# Usage: Documentation Section 8
# =============================================================================

run_test("Error Handling - HTTP 4xx errors", sub {
    my $user_agent = new LWP::UserAgent;
    my $response = $user_agent->get("http://$TEST_HOST/status/404");

    assert(!$response->is_success, "404 request not successful");
    assert_equals($response->code(), 404, "Status code is 404");

    my $status_line = $response->status_line();
    assert($status_line =~ /404/, "Status line contains 404");

    return 1;
});

run_test("Error Handling - HTTP 5xx errors", sub {
    my $user_agent = new LWP::UserAgent;
    my $response = $user_agent->get("http://$TEST_HOST/status/500");

    assert(!$response->is_success, "500 request not successful");
    assert_equals($response->code(), 500, "Status code is 500");

    return 1;
});

run_test("Error Handling - Timeout configuration", sub {
    my $user_agent = new LWP::UserAgent;

    # Set short timeout for testing
    $user_agent->timeout(5);
    assert_equals($user_agent->timeout(), 5, "Timeout set to 5 seconds");

    # Try request with delay (should succeed if < 5 seconds)
    my $response = $user_agent->get("http://$TEST_HOST/delay/2");
    assert($response->is_success, "Request within timeout succeeded");

    return 1;
});

run_test("Error Handling - Pattern from documentation", sub {
    my $user_agent = new LWP::UserAgent;
    my $response = $user_agent->get("http://$TEST_HOST/status/403");

    # Documentation pattern: if (!$response->is_success)
    if (!$response->is_success) {
        my $error_msg = $response->status_line;
        assert($error_msg, "Error message retrieved");
        assert($error_msg =~ /403/, "Error message contains 403");
        return 1;
    } else {
        die "Expected failure for 403 status";
    }
});

# =============================================================================
# SECTION 8: WWW::Mechanize Compatibility
# Usage: 30165CbiWasCtl.pl
# =============================================================================

run_test("WWW::Mechanize - Object creation with custom agent", sub {
    # Documentation pattern: WWW::Mechanize->new(agent => "Mozilla/6.0", autocheck => 0)
    my $mech = WWW::Mechanize->new(agent => "Mozilla/6.0", autocheck => 0);

    assert(defined $mech, "Mechanize object created");
    assert($mech->{agent} eq "Mozilla/6.0", "Custom agent set");
    assert($mech->{autocheck} == 0, "Autocheck disabled");

    return 1;
});

run_test("WWW::Mechanize - get method", sub {
    my $mech = WWW::Mechanize->new(agent => "Mozilla/6.0", autocheck => 0);

    # Documentation pattern: $mech->get($url)
    $mech->get("http://$TEST_HOST/html");

    my $status = $mech->status();
    assert_equals($status, 200, "Status is 200");

    return 1;
});

run_test("WWW::Mechanize - status method", sub {
    my $mech = WWW::Mechanize->new(agent => "Mozilla/6.0", autocheck => 0);

    # Test 200 status
    $mech->get("http://$TEST_HOST/status/200");
    assert_equals($mech->status(), 200, "Status is 200");

    # Test 404 status (WebSphere monitoring pattern)
    $mech->get("http://$TEST_HOST/status/404");
    assert_equals($mech->status(), 404, "Status is 404");

    return 1;
});

run_test("WWW::Mechanize - autocheck = 0 behavior", sub {
    my $mech = WWW::Mechanize->new(agent => "Mozilla/6.0", autocheck => 0);

    # With autocheck = 0, errors should not die
    eval {
        $mech->get("http://$TEST_HOST/status/500");
        my $status = $mech->status();
        assert_equals($status, 500, "Status is 500 (no exception thrown)");
    };

    assert(!$@, "No exception with autocheck = 0");

    return 1;
});

run_test("WWW::Mechanize - WebSphere monitoring pattern", sub {
    # Documentation use case: Check WAS server status
    my $mech = WWW::Mechanize->new(agent => "Mozilla/6.0", autocheck => 0);

    # Simulate WebSphere status check
    $mech->get("http://$TEST_HOST/status/200");
    my $status = $mech->status();

    # Check if server is running (any response indicates running)
    if ($status == 404 || $status == 200) {
        assert(1, "Server is running (status: $status)");
        return 1;
    } elsif ($status == 502) {
        assert(0, "Server is down (status: 502)");
        return 0;
    } else {
        assert(1, "Server responded with status: $status");
        return 1;
    }
});

# =============================================================================
# SECTION 9: SSL/HTTPS Support
# Usage: HpsmTicket.pm, general usage
# =============================================================================

run_test("SSL/HTTPS - HTTPS GET request", sub {
    my $user_agent = new LWP::UserAgent;

    # Note: httpbin.org supports HTTPS
    my $response = $user_agent->get("https://$TEST_HOST/get");

    assert($response->is_success, "HTTPS GET successful");
    assert_status_code($response, 200, "HTTPS status is 200");

    return 1;
});

run_test("SSL/HTTPS - HTTPS POST request", sub {
    my $user_agent = new LWP::UserAgent;

    my %postData = (field1 => 'value1', field2 => 'value2');
    my $response = $user_agent->post("https://$TEST_HOST/post", \%postData);

    assert($response->is_success, "HTTPS POST successful");
    assert_status_code($response, 200, "HTTPS POST status is 200");

    return 1;
});

run_test("SSL/HTTPS - HTTPS via HTTP::Request", sub {
    my $user_agent = new LWP::UserAgent;

    my $web_request = new HTTP::Request POST => "https://$TEST_HOST/post";
    $web_request->content_type('application/x-www-form-urlencoded');
    $web_request->content("ssl_test=true");

    my $response = $user_agent->request($web_request);

    assert($response->is_success, "HTTPS via request() successful");

    return 1;
});

# =============================================================================
# SECTION 10: Form-Encoded POST
# Usage: Primary pattern in all documented scripts
# =============================================================================

run_test("Form-Encoded POST - application/x-www-form-urlencoded", sub {
    my $user_agent = new LWP::UserAgent;

    my $web_request = new HTTP::Request POST => "http://$TEST_HOST/post";
    $web_request->content_type('application/x-www-form-urlencoded');
    $web_request->content("field1=value1&field2=value2&field3=test+data");

    my $response = $user_agent->request($web_request);

    assert($response->is_success, "Form POST successful");

    my $content = $response->content();
    assert_contains($content, "field1", "Response contains field1");

    return 1;
});

run_test("Form-Encoded POST - Special characters", sub {
    my $user_agent = new LWP::UserAgent;

    my %postData = (
        'param_with_space' => 'value with spaces',
        'param_special' => 'value&special=chars',
        'param_unicode' => 'test',
    );

    my $response = $user_agent->post("http://$TEST_HOST/post", \%postData);

    assert($response->is_success, "POST with special chars successful");

    return 1;
});

run_test("Form-Encoded POST - Complex form data", sub {
    my $user_agent = new LWP::UserAgent;

    # Simulate Java Servlet parameters (documentation use case)
    my $content_string = "action=submit&jobid=12345&status=running&priority=high";

    my $web_request = new HTTP::Request POST => "http://$TEST_HOST/post";
    $web_request->content_type('application/x-www-form-urlencoded');
    $web_request->content($content_string);

    my $response = $user_agent->request($web_request);

    assert($response->is_success, "Complex form POST successful");
    assert_contains($response->content(), "action", "Response contains action param");

    return 1;
});

# =============================================================================
# SECTION 11: Advanced Features
# =============================================================================

run_test("Advanced - Multiple headers", sub {
    my $user_agent = new LWP::UserAgent;

    my $web_request = new HTTP::Request GET => "http://$TEST_HOST/headers";
    $web_request->header('X-Custom-Header' => 'CustomValue');
    $web_request->header('X-Another-Header' => 'AnotherValue');

    my $response = $user_agent->request($web_request);

    assert($response->is_success, "Request with custom headers successful");
    assert_contains($response->content(), "X-Custom-Header", "Custom header present");

    return 1;
});

run_test("Advanced - User-Agent propagation", sub {
    my $user_agent = new LWP::UserAgent;
    $user_agent->agent("TestAgent/1.0");

    my $response = $user_agent->get("http://$TEST_HOST/user-agent");

    assert($response->is_success, "User-Agent request successful");
    assert_contains($response->content(), "TestAgent", "Custom User-Agent propagated");

    return 1;
});

run_test("Advanced - JSON response handling", sub {
    my $user_agent = new LWP::UserAgent;
    my $response = $user_agent->get("http://$TEST_HOST/json");

    assert($response->is_success, "JSON request successful");

    # Documentation pattern: use JSON::PP to parse response
    my $content = $response->content();
    my $json_data = decode_json($content);

    assert(ref($json_data) eq 'HASH', "JSON parsed to hash");

    return 1;
});

run_test("Advanced - HTTP method variations", sub {
    my $user_agent = new LWP::UserAgent;

    # Test various HTTP methods
    my $get_req = new HTTP::Request GET => "http://$TEST_HOST/get";
    my $get_resp = $user_agent->request($get_req);
    assert($get_resp->is_success, "GET method works");

    my $post_req = new HTTP::Request POST => "http://$TEST_HOST/post";
    my $post_resp = $user_agent->request($post_req);
    assert($post_resp->is_success, "POST method works");

    return 1;
});

run_test("Advanced - Empty content POST", sub {
    my $user_agent = new LWP::UserAgent;

    my $web_request = new HTTP::Request POST => "http://$TEST_HOST/post";
    $web_request->content_type('application/x-www-form-urlencoded');
    $web_request->content("");  # Empty content

    my $response = $user_agent->request($web_request);

    assert($response->is_success, "POST with empty content successful");

    return 1;
});

# =============================================================================
# SECTION 12: Real-World Usage Patterns
# =============================================================================

run_test("Real-World - Job Starter Pattern (30166mi_job_starter.pl)", sub {
    # Simulate job starter script pattern
    my $url = "http://$TEST_HOST";
    my $servlet = "/post";
    my $timeout = 180;

    my $user_agent = new LWP::UserAgent;
    $user_agent->agent("JobStarter/0.1 " . $user_agent->agent);
    $user_agent->timeout($timeout);

    my $content_string = "jobid=12345&action=start&environment=prod";
    my $URL = "$url$servlet";

    my $web_request = new HTTP::Request POST => $URL;
    $web_request->content_type('application/x-www-form-urlencoded');
    $web_request->content($content_string);

    my $response = $user_agent->request($web_request);

    assert($response->is_success, "Job starter pattern successful");

    if ($response->is_success) {
        my $response_content = $response->content;
        assert($response_content, "Response content retrieved");
    } else {
        die "Request failed: " . $response->status_line;
    }

    return 1;
});

run_test("Real-World - HP Service Manager Pattern (HpsmTicket.pm)", sub {
    # Simulate HP Service Manager eHub pattern
    my $user_agent = LWP::UserAgent->new;

    my %postData = (
        ticket_id => 'INC12345',
        summary => 'Test ticket',
        description => 'Test description',
        priority => 'high',
    );

    my $response = $user_agent->post("https://$TEST_HOST/post", \%postData);

    assert($response->is_success, "HPSM ticket pattern successful");

    if (!$response->is_success) {
        die "Ticket creation failed: " . $response->status_line;
    }

    return 1;
});

run_test("Real-World - WebSphere Monitoring Pattern (30165CbiWasCtl.pl)", sub {
    # Simulate WebSphere Application Server monitoring
    my $mech = WWW::Mechanize->new(agent => "Mozilla/6.0", autocheck => 0);

    my $wls_url = "http://$TEST_HOST/status/200";
    $mech->get($wls_url);
    my $status = $mech->status();

    # Check server status
    if ($status == 404) {
        # Server running but page not found (typical for WAS admin console)
        assert(1, "WebSphere server is running (404)");
    } elsif ($status == 200) {
        # Server running and responding
        assert(1, "WebSphere server is running (200)");
    } elsif ($status == 502) {
        # Server is down
        die "WebSphere server is down (502)";
    } else {
        # Other status
        assert(1, "WebSphere server status: $status");
    }

    return 1;
});

run_test("Real-World - RESTful URL handling", sub {
    # Simulate RESTful URL construction (application level)
    my $user_agent = new LWP::UserAgent;

    my $base_url = "http://$TEST_HOST";
    my $resource = "/anything/resource";
    my $restfiletype = "json";

    # RESTful URL pattern from documentation
    my $URL = "$base_url$resource/$restfiletype";

    my $response = $user_agent->get($URL);

    assert($response->is_success, "RESTful URL request successful");
    assert_contains($response->content(), "anything", "RESTful path preserved");

    return 1;
});

run_test("Real-World - Dynamic HTTP method selection", sub {
    my $user_agent = new LWP::UserAgent;

    # Simulate command-line HttpMethod parameter
    my $http_method = 'POST';  # Could be 'GET' or 'POST'
    my $URL = "http://$TEST_HOST/" . lc($http_method);

    my $web_request = new HTTP::Request $http_method => $URL;

    if ($http_method eq 'POST') {
        $web_request->content_type('application/x-www-form-urlencoded');
        $web_request->content("data=test");
    }

    my $response = $user_agent->request($web_request);

    assert($response->is_success, "Dynamic method selection successful");

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

if ($failed_tests > 0) {
    print "\n" . "─" x 80 . "\n";
    print "Failed Tests:\n";
    print "─" x 80 . "\n";
    foreach my $result (@test_results) {
        if ($result->{status} eq 'FAIL') {
            print "✗ $result->{name}\n";
            if ($result->{error}) {
                print "  Error: $result->{error}\n";
            }
        }
    }
}

print "\n" . "=" x 80 . "\n";

if ($failed_tests == 0) {
    print "✓ ALL TESTS PASSED - HTTPHelper is production ready!\n";
    print "=" x 80 . "\n";
    exit 0;
} else {
    print "✗ SOME TESTS FAILED - Review failures above\n";
    print "=" x 80 . "\n";
    exit 1;
}
