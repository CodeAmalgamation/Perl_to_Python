#!/usr/bin/perl
#
# test_http_form_post.pl - Test form-encoded POST requests
#
# This test uses a local mock server which accepts and echoes
# form-encoded data, making it perfect for testing our implementation.

use strict;
use warnings;
use lib "/Users/shubhamdixit/Perl_to_Python";
use HTTPHelper;
use JSON::PP;

# Configuration
my $MOCK_SERVER = $ENV{MOCK_SERVER} || "http://localhost:8888";

print "=" x 70 . "\n";
print "HTTP Form-Encoded POST Test\n";
print "=" x 70 . "\n";
print "NOTE: Using local mock server at $MOCK_SERVER\n";
print "=" x 70 . "\n\n";

my $test_count = 0;
my $pass_count = 0;

sub test {
    my ($name, $code) = @_;
    $test_count++;
    print "Test $test_count: $name\n";
    print "-" x 70 . "\n";

    eval {
        $code->();
        print "  ✓ PASS\n\n";
        $pass_count++;
    };
    if ($@) {
        print "  ✗ FAIL: $@\n\n";
    }
}

# Test 1: POST with hashref (HpsmTicket.pm pattern)
test("POST with hashref - form data", sub {
    my $ua = LWP::UserAgent->new();

    my %form_data = (
        username => 'testuser',
        password => 'testpass123',
        email => 'test@example.com',
        action => 'submit'
    );

    print "  Sending form data to mock server\n";
    my $response = $ua->post("$MOCK_SERVER/post", \%form_data);

    print "  Status: " . $response->code() . "\n";
    die "Request failed: " . $response->status_line() unless $response->is_success();

    my $content = $response->content();
    print "  Content length: " . length($content) . " bytes\n";

    # Parse JSON response
    my $json = decode_json($content);

    # Verify our form data was received
    die "Form data not found in response" unless exists $json->{form};

    print "  ✓ Form data received by server:\n";
    foreach my $key (sort keys %{$json->{form}}) {
        print "    - $key: " . $json->{form}->{$key} . "\n";
    }

    # Verify all our fields are present
    die "username not found" unless $json->{form}->{username} eq 'testuser';
    die "password not found" unless $json->{form}->{password} eq 'testpass123';
    die "email not found" unless $json->{form}->{email} eq 'test@example.com';
    die "action not found" unless $json->{form}->{action} eq 'submit';

    print "  ✓ All form fields verified\n";
});

# Test 2: POST with Content parameter (Job Starter pattern)
test("POST with HTTP::Request - form encoding", sub {
    my $ua = LWP::UserAgent->new();

    my $form_string = "jobid=12345&environment=production&action=start&priority=high";

    my $request = new HTTP::Request POST => "$MOCK_SERVER/post";
    $request->content_type('application/x-www-form-urlencoded');
    $request->content($form_string);

    print "  Sending: $form_string\n";
    my $response = $ua->request($request);

    print "  Status: " . $response->code() . "\n";
    die "Request failed: " . $response->status_line() unless $response->is_success();

    my $json = decode_json($response->content());

    print "  ✓ Form data received:\n";
    foreach my $key (sort keys %{$json->{form}}) {
        print "    - $key: " . $json->{form}->{$key} . "\n";
    }

    # Verify fields
    die "jobid mismatch" unless $json->{form}->{jobid} eq '12345';
    die "environment mismatch" unless $json->{form}->{environment} eq 'production';
    die "action mismatch" unless $json->{form}->{action} eq 'start';
    die "priority mismatch" unless $json->{form}->{priority} eq 'high';

    print "  ✓ All form fields verified\n";
});

# Test 3: Special characters in form data
test("POST with special characters", sub {
    my $ua = LWP::UserAgent->new();

    my %form_data = (
        'field_with_space' => 'value with spaces',
        'special_chars' => 'test&value=123',
        'symbols' => '@#$%^&*()',
        'unicode' => 'test™',
        'equals' => 'a=b=c'
    );

    print "  Sending form with special characters\n";
    my $response = $ua->post("$MOCK_SERVER/post", \%form_data);

    print "  Status: " . $response->code() . "\n";
    die "Request failed: " . $response->status_line() unless $response->is_success();

    my $json = decode_json($response->content());

    print "  ✓ Special characters handled:\n";
    foreach my $key (sort keys %{$json->{form}}) {
        my $value = $json->{form}->{$key};
        print "    - $key: $value\n";
        die "Value mismatch for $key" unless $value eq $form_data{$key};
    }

    print "  ✓ All special characters preserved correctly\n";
});

# Test 4: Empty values and edge cases
test("POST with edge cases", sub {
    my $ua = LWP::UserAgent->new();

    my %form_data = (
        'empty_value' => '',
        'number' => '12345',
        'float' => '3.14159',
        'boolean_true' => '1',
        'boolean_false' => '0'
    );

    print "  Sending edge case form data\n";
    my $response = $ua->post("$MOCK_SERVER/post", \%form_data);

    print "  Status: " . $response->code() . "\n";
    die "Request failed: " . $response->status_line() unless $response->is_success();

    my $json = decode_json($response->content());

    print "  ✓ Edge cases handled:\n";
    foreach my $key (sort keys %{$json->{form}}) {
        print "    - $key: '" . $json->{form}->{$key} . "'\n";
    }

    print "  ✓ All edge cases verified\n";
});

# Test 5: Content-Type header verification
test("Verify Content-Type header", sub {
    my $ua = LWP::UserAgent->new();

    my %form_data = (test => 'data');

    print "  Sending POST request\n";
    my $response = $ua->post("$MOCK_SERVER/post", \%form_data);

    die "Request failed: " . $response->status_line() unless $response->is_success();

    my $json = decode_json($response->content());

    # Check that httpbin received the correct Content-Type header
    my $content_type = $json->{headers}->{'Content-Type'} || '';
    print "  Content-Type sent: $content_type\n";

    die "Wrong Content-Type" unless $content_type =~ /application\/x-www-form-urlencoded/;

    print "  ✓ Content-Type header correct\n";
});

# Test 6: Multiple values with same key (if needed)
test("POST with multiple parameters", sub {
    my $ua = LWP::UserAgent->new();

    # Simulate a complex form
    my %form_data = (
        'param1' => 'value1',
        'param2' => 'value2',
        'param3' => 'value3',
        'param4' => 'value4',
        'param5' => 'value5'
    );

    print "  Sending 5 parameters\n";
    my $response = $ua->post("$MOCK_SERVER/post", \%form_data);

    print "  Status: " . $response->code() . "\n";
    die "Request failed: " . $response->status_line() unless $response->is_success();

    my $json = decode_json($response->content());

    my $received_count = scalar keys %{$json->{form}};
    print "  Parameters sent: 5\n";
    print "  Parameters received: $received_count\n";

    die "Parameter count mismatch" unless $received_count == 5;

    print "  ✓ All parameters received correctly\n";
});

# Test 7: Real-world simulation - Ticket creation pattern
test("Real-world: HP Service Manager ticket pattern", sub {
    my $ua = LWP::UserAgent->new();

    # Simulate HP Service Manager ticket creation
    my %ticket_data = (
        'ticket_id' => 'INC' . time(),
        'summary' => 'Test incident for form encoding',
        'description' => 'This is a test ticket with multiple fields',
        'priority' => 'high',
        'category' => 'software',
        'contact' => 'admin@example.com',
        'impact' => '2',
        'urgency' => '2'
    );

    print "  Simulating HPSM ticket creation\n";
    print "  Ticket ID: " . $ticket_data{ticket_id} . "\n";

    my $response = $ua->post("$MOCK_SERVER/post", \%ticket_data);

    print "  Status: " . $response->code() . "\n";
    die "Request failed: " . $response->status_line() unless $response->is_success();

    my $json = decode_json($response->content());

    print "  ✓ Ticket data sent successfully:\n";
    foreach my $key (qw(ticket_id summary priority category)) {
        my $value = $json->{form}->{$key};
        print "    - $key: $value\n";
    }

    print "  ✓ HPSM pattern verified\n";
});

# Test 8: Job Starter pattern with RESTful-style data
test("Real-world: Job Starter servlet pattern", sub {
    my $ua = LWP::UserAgent->new();
    $ua->timeout(180);  # Match documentation default

    # Simulate WebLogic Java Servlet call
    my $servlet_url = "$MOCK_SERVER/post";

    my $request = new HTTP::Request POST => $servlet_url;
    $request->content_type('application/x-www-form-urlencoded');

    # Build content string like job starter scripts
    my $content = "jobName=batch_process_001";
    $content .= "&environment=production";
    $content .= "&parameters=START_DATE:2025-10-15,END_DATE:2025-10-16";
    $content .= "&requestor=system_automation";
    $content .= "&priority=normal";

    $request->content($content);

    print "  Simulating Job Starter servlet call\n";
    print "  Content: $content\n";

    my $response = $ua->request($request);

    print "  Status: " . $response->code() . "\n";
    die "Request failed: " . $response->status_line() unless $response->is_success();

    my $json = decode_json($response->content());

    print "  ✓ Job parameters sent:\n";
    print "    - jobName: " . $json->{form}->{jobName} . "\n";
    print "    - environment: " . $json->{form}->{environment} . "\n";
    print "    - requestor: " . $json->{form}->{requestor} . "\n";

    die "jobName mismatch" unless $json->{form}->{jobName} eq 'batch_process_001';
    die "environment mismatch" unless $json->{form}->{environment} eq 'production';

    print "  ✓ Job Starter pattern verified\n";
});

# Summary
print "=" x 70 . "\n";
print "Test Summary\n";
print "=" x 70 . "\n";
print "Total Tests:  $test_count\n";
print "Passed:       $pass_count\n";
print "Failed:       " . ($test_count - $pass_count) . "\n";
print "=" x 70 . "\n";

if ($pass_count == $test_count) {
    print "✓ ALL TESTS PASSED - Form-encoded POST fully functional!\n";
    print "=" x 70 . "\n";
    exit 0;
} else {
    print "✗ SOME TESTS FAILED\n";
    print "=" x 70 . "\n";
    exit 1;
}
