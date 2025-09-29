#!/usr/bin/perl
use strict;
use warnings;
use CPANBridge;
use Data::Dumper;

# Enable high-performance daemon mode
$CPANBridge::DAEMON_MODE = 1;

# Use exactly as before - no code changes needed!
my $bridge = CPANBridge->new();
my $result = $bridge->call_python('http_helper', 'lwp_request', {
    method => 'GET',
    url => 'https://api.github.com/users/octocat'
});

if ($result->{success}) {
    print "Success! Got response from GitHub API\n";
    print ($result->{result}->{body});
} else {
    print "Error: " . $result->{error} . "\n";
    print "Full error response:\n";
    print Dumper($result);
}