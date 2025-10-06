#!/usr/bin/perl
use strict;
use warnings;
use lib '.';
use LockFileHelper;
use Data::Dumper;

print "=== LockFile Debug Test ===\n\n";

# Enable daemon mode
$CPANBridge::DAEMON_MODE = 1;

print "Step 1: Creating lock manager...\n";
my $lockmgr = LockFile::Simple->make(-nfs => 1, -hold => 90);
print "Manager created: " . Dumper($lockmgr) . "\n";
print "Manager ID: " . $lockmgr->{manager_id} . "\n\n";

print "Step 2: Trying to acquire lock...\n";
my $test_file = "/tmp/debug_test.txt";
my $lock_pattern = "/tmp/%F.lock";

print "Calling trylock with:\n";
print "  File: $test_file\n";
print "  Pattern: $lock_pattern\n";
print "  Manager ID: " . $lockmgr->{manager_id} . "\n\n";

my $lock = $lockmgr->trylock($test_file, $lock_pattern);

if ($lock) {
    print "✅ Lock acquired successfully!\n";
    print "Lock object: " . Dumper($lock) . "\n";
    $lock->release();
    print "✅ Lock released\n";
} else {
    print "❌ Failed to acquire lock: $!\n";
}
