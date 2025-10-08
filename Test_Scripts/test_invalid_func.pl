#!/usr/bin/perl
use strict;
use warnings;
use lib '.';
use CPANBridge;
use Data::Dumper;

$CPANBridge::DAEMON_MODE = 1;
my $bridge = CPANBridge->new();

print "Testing invalid function call...\n\n";

my $result = $bridge->call_python('database', 'malicious_function', {
    param => 'test'
});

print "Full result:\n";
print Dumper($result);
