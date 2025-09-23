#!/usr/bin/perl
use strict;
use warnings;
use CPANBridge;
use Time::HiRes qw(time sleep);

print "=== Testing Connection Cleanup Fix ===\n\n";

# Enable daemon mode
$CPANBridge::DAEMON_MODE = 1;

my $bridge = CPANBridge->new();

print "Making 10 test requests...\n";

my $start_time = time();

for my $i (1..10) {
    my $result = $bridge->call_python('test', 'ping', { call => $i });
    if ($result->{success}) {
        print "Request $i: ✅\n";
    } else {
        print "Request $i: ❌ " . ($result->{error} || 'Unknown error') . "\n";
    }
}

my $duration = time() - $start_time;
printf "\n🚀 Completed 10 requests in %.3f seconds (%.1f req/sec)\n", $duration, 10/$duration;

print "\nNow check daemon logs for connection cleanup messages and active connection count...\n";
print "Expected: Active connections should be 0 or very low after requests complete.\n";
print "\nWait a few seconds then check the health log for final connection count.\n";