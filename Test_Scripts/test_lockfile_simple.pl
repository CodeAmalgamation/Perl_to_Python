#!/usr/bin/perl
use strict;
use warnings;
use lib '.';
use CPANBridge;
use Data::Dumper;

print "Testing lockfile make() directly through CPANBridge...\n\n";

$CPANBridge::DAEMON_MODE = 0;

my $bridge = CPANBridge->new(debug => 2);

print "Calling lockfile make...\n";
my $result = $bridge->call_python('lockfile', 'make', {
    nfs => 1,
    hold => 90
});

print "\nResult:\n";
print Dumper($result);

if ($result && ref($result) eq 'HASH') {
    if ($result->{manager_id}) {
        print "\n✅ SUCCESS: Manager ID = $result->{manager_id}\n";
    } else {
        print "\n❌ ERROR: No manager_id in result\n";
    }
} else {
    print "\n❌ ERROR: Invalid result\n";
}
