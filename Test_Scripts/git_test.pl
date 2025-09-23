#!/usr/bin/perl
use strict;
use warnings;
use CPANBridge;

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
    print "Full response:\n";
    use Data::Dumper;
    print Dumper($result);
} else {
    print "Error: " . $result->{error} . "\n";
    print "Full error response:\n";
    use Data::Dumper;
    print Dumper($result);
}