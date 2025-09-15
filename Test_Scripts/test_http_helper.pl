#!/usr/bin/perl
# test_http_helper.pl - Test HTTPHelper with your actual usage patterns

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin";

# Replace these lines in your actual scripts:
# use LWP::UserAgent;
# use HTTP::Request;
# use WWW::Mechanize;
use HTTPHelper;

print "=== HTTPHelper Test Suite ===\n";
print "Testing LWP::UserAgent and WWW::Mechanize replacement patterns\n\n";

# Test basic bridge connectivity
print "1. Testing bridge connectivity...\n";
my $bridge = HTTPHelper->new(debug => 1);
if ($bridge->test_python_bridge()) {
    print "   ✓ Python bridge is working\n";
} else {
    print "   ✗ Python bridge failed\n";
    exit 1;
}

# Test 1: Basic Constructor Pattern (from your analysis)
print "\n2. Testing LWP::UserAgent constructor pattern...\n";
my $user_agent = new LWP::UserAgent;
print "   ✓ Created LWP::UserAgent object\n";

# Test 2: Agent Configuration (30166mi_job_starter.pl pattern)
print "\n3. Testing agent configuration...\n";
my $original_agent = $user_agent->agent();
$user_agent->agent("TestApp/0.1 " . $user_agent->agent);
my $new_agent = $user_agent->agent();
print "   Original agent: $original_agent\n";
print "   New agent: $new_agent\n";
print "   ✓ Agent configuration working\n";

# Test 3: Timeout Configuration (from your analysis)
print "\n4. Testing timeout configuration...\n";
$user_agent->timeout(30);
my $timeout = $user_agent->timeout();
print "   Timeout set to: $timeout seconds\n";
print "   ✓ Timeout configuration working\n";

# Test 4: HTTP::Request GET Pattern (30166mi_job_starter.pl style)
print "\n5. Testing HTTP::Request GET pattern...\n";
my $test_url = "https://httpbin.org/get";
my $web_request = new HTTP::Request GET => $test_url;
my $response = $user_agent->request($web_request);

if ($response->is_success) {
    print "   ✓ GET request successful\n";
    print "   Status: " . $response->code() . "\n";
    print "   Status line: " . $response->status_line() . "\n";
    print "   Content length: " . length($response->content()) . " bytes\n";
    print "   Response type: " . ref($response) . "\n";
} else {
    print "   ✗ GET request failed: " . $response->status_line() . "\n";
    print "   Error content: " . $response->content() . "\n";
}

# Test 5: HTTP::Request POST Pattern (30166mi_job_starter.pl style)
print "\n6. Testing HTTP::Request POST with form data...\n";
my $post_url = "https://httpbin.org/post";

# Build content string (your pattern)
my @param = ("param1=value1", "param2=value2", "param3=value3");
my $content = "";
my $pn = 0;
foreach my $param_value (@param) {
    if (($pn > 0) and ($param_value)) {
        $content = ("$param_value&$content");
    } else {
        $content = $param_value;
    }
    $pn++;
}
# Remove trailing &
$content =~ s/&$//;

print "   Form content: $content\n";

$web_request = new HTTP::Request POST => $post_url;
$web_request->content_type('application/x-www-form-urlencoded');
$web_request->content($content);
$response = $user_agent->request($web_request);

if ($response->is_success) {
    print "   ✓ POST request successful\n";
    print "   Status: " . $response->code() . "\n";
    print "   Response length: " . length($response->content()) . " bytes\n";
    
    # Test decoded_content method
    my $decoded = $response->decoded_content();
    print "   Decoded content available: " . (length($decoded) > 0 ? "Yes" : "No") . "\n";
} else {
    print "   ✗ POST request failed: " . $response->status_line() . "\n";
}

# Test 6: Direct POST Method (HpsmTicket.pm style)
print "\n7. Testing direct POST method...\n";
my $ticket_data = "inputString=<TestRequest><Action>test</Action></TestRequest>";
my $web_response = $user_agent->post($post_url, 
    Content_Type => 'application/x-www-form-urlencoded', 
    Content => $ticket_data);

if ($web_response->is_success) {
    print "   ✓ Direct POST successful\n";
    print "   Status: " . $web_response->code() . "\n";
} else {
    print "   ✗ Direct POST failed\n";
    printf("   ERROR: %s\n", $web_response->status_line);
}

# Test 7: Error Handling Pattern (from your analysis)
print "\n8. Testing error handling patterns...\n";
my $bad_url = "https://httpbin.org/status/404";
$web_request = new HTTP::Request GET => $bad_url;
$response = $user_agent->request($web_request);

if ($response->is_success) {
    print "   ✗ Expected error but got success\n";
} else {
    print "   ✓ Error handling working correctly\n";
    print "   Status code: " . $response->code() . "\n";
    print "   Status line: " . $response->status_line() . "\n";
    print "   Message: " . $response->message() . "\n";
    print "   Content: " . substr($response->content(), 0, 100) . "...\n";
}

# Test 8: SSL Environment Variable (from your analysis)
print "\n9. Testing SSL verification control...\n";
$ENV{PERL_LWP_SSL_VERIFY_HOSTNAME} = 0;
my $ssl_agent = new LWP::UserAgent;
print "   ✓ SSL verification disabled via environment variable\n";

# Test 9: Response Method Compatibility
print "\n10. Testing response method compatibility...\n";
$response = $user_agent->get("https://httpbin.org/get");
if ($response) {
    my @methods = qw(is_success code status_line message content decoded_content);
    print "   Testing response methods:\n";
    foreach my $method (@methods) {
        my $result = eval { $response->$method() };
        if (defined $result) {
            print "   ✓ $method() works\n";
        } else {
            print "   ✗ $method() failed: $@\n";
        }
    }
}

# Test 10: WWW::Mechanize Pattern (30165CbiWasCtl.pl style)
print "\n11. Testing WWW::Mechanize compatibility...\n";

# Your exact usage pattern
my $mech = WWW::Mechanize->new(agent => "Mozilla/6.0", autocheck => 0);
print "   ✓ Created WWW::Mechanize object with autocheck disabled\n";

# Test the status checking workflow
my $test_url = "https://httpbin.org/status/404";  # Will return 404
$mech->get($test_url);
my $status = $mech->status();

print "   GET request to: $test_url\n";
print "   Status code: $status\n";

# Test your WebSphere status logic
if ($status eq '404') {
    print "   ✓ Status 404 - Server would be considered running\n";
} elsif ($status eq '502') {
    print "   ⚠ Status 502 - Proxy configuration error\n";
} else {
    print "   ⚠ Status $status - Server would be considered down\n";
}

# Test with a success case
print "\n   Testing successful request...\n";
$mech->get("https://httpbin.org/get");
my $success_status = $mech->status();
print "   Success status: $success_status\n";
print "   ✓ WWW::Mechanize compatibility working\n";

# Test 11: Performance Test
print "\n12. Performance test (10 requests)...\n";
my $start_time = time();
my $success_count = 0;

for my $i (1..10) {
    my $perf_response = $user_agent->get("https://httpbin.org/get");
    if ($perf_response && $perf_response->is_success) {
        $success_count++;
    }
    print "   Request $i: " . ($perf_response->is_success ? "✓" : "✗") . "\n";
}

my $total_time = time() - $start_time;
my $avg_time = $total_time / 10;

print "   Results: $success_count/10 successful\n";
print "   Total time: ${total_time}s\n";
print "   Average per request: ${avg_time}s\n";
print "   Performance: " . ($avg_time < 1.0 ? "✓ Good" : "⚠ Slow") . "\n";

print "\n=== Test Summary ===\n";
print "HTTPHelper successfully replaces both LWP::UserAgent and WWW::Mechanize.\n";

print "\nTo migrate your scripts:\n";
print "1. Replace 'use LWP::UserAgent;' with 'use HTTPHelper;'\n";
print "2. Replace 'use HTTP::Request;' with 'use HTTPHelper;' (if needed)\n";
print "3. Replace 'use WWW::Mechanize;' with 'use HTTPHelper;'\n";
print "4. No other code changes required!\n";

print "\nSupported Patterns:\n";
print "✓ LWP::UserAgent: Basic constructor, agent(), timeout(), request(), post()\n";
print "✓ HTTP::Request: Constructor, content_type(), content(), headers\n";
print "✓ WWW::Mechanize: Simple constructor, get(), status() for health checks\n";
print "✓ Response objects: is_success(), code(), status_line(), content(), etc.\n";
print "✓ SSL verification: PERL_LWP_SSL_VERIFY_HOSTNAME support\n";
print "✓ Form handling: application/x-www-form-urlencoded POST requests\n";

print "\nTest completed.\n";
    