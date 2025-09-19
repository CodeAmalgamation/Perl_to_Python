#!/usr/bin/perl

# test_daemon_simple.pl - Simple daemon connectivity test

use strict;
use warnings;
use IO::Socket::UNIX;
use JSON;

print "=== Simple Daemon Connectivity Test ===\n";

# Test 1: Check if socket exists
print "Test 1: Socket file check\n";
my $socket_path = '/tmp/cpan_bridge.sock';

if (-S $socket_path) {
    print "SUCCESS: Socket file exists at $socket_path\n";
} else {
    print "FAILED: Socket file does not exist at $socket_path\n";
    exit 1;
}

# Test 2: Connect to socket
print "\nTest 2: Socket connection\n";
my $socket = IO::Socket::UNIX->new(
    Peer => $socket_path,
    Type => SOCK_STREAM,
    Timeout => 5
);

unless ($socket) {
    print "FAILED: Cannot connect to socket: $!\n";
    exit 1;
}

print "SUCCESS: Connected to daemon socket\n";

# Test 3: Send ping request
print "\nTest 3: Ping request\n";
my $request = {
    module => 'test',
    function => 'ping',
    params => {},
    timestamp => time()
};

my $request_json = encode_json($request);
print "Sending: $request_json\n";

$socket->print($request_json);
$socket->shutdown(1);  # Close write end

# Test 4: Read response
print "\nTest 4: Read response\n";
my $response = '';
while (my $line = <$socket>) {
    $response .= $line;
}
$socket->close();

print "Received: $response\n";

if ($response) {
    my $result = decode_json($response);
    if ($result->{success}) {
        print "SUCCESS: Ping successful\n";
        print "Message: " . $result->{result}->{message} . "\n";
        print "Daemon version: " . $result->{result}->{daemon_version} . "\n";
        print "Uptime: " . $result->{result}->{uptime} . " seconds\n";
    } else {
        print "FAILED: Ping failed: " . $result->{error} . "\n";
    }
} else {
    print "FAILED: Empty response\n";
}

print "\n=== Simple Daemon Test Complete ===\n";