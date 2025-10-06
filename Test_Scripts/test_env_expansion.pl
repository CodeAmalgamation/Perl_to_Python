#!/usr/bin/perl
use strict;
use warnings;
use lib '.';
use LockFileHelper;

print "=== Environment Variable Expansion Test ===\n\n";

$CPANBridge::DAEMON_MODE = 1;
$ENV{TEST_LOCKDIR} = "/tmp/mytest";
mkdir $ENV{TEST_LOCKDIR} unless -d $ENV{TEST_LOCKDIR};

print "Test 1: Escaped dollar sign (current test)\n";
my $pattern1 = "\$TEST_LOCKDIR/%F.lock";
print "  Pattern: $pattern1\n";
print "  Result: Should NOT expand because backslash-dollar makes it literal\n\n";

print "Test 2: Perl-expanded env var (correct usage)\n";
my $pattern2 = "$ENV{TEST_LOCKDIR}/%F.lock";
print "  Pattern: $pattern2\n";
print "  Result: Should be /tmp/mytest/%F.lock\n\n";

print "Test 3: Python-style env var\n";
my $pattern3 = '$TEST_LOCKDIR/%F.lock';  # Single quotes = literal
print "  Pattern: $pattern3\n";
print "  Result: Python os.path.expandvars() should expand this\n\n";

my $lockmgr = LockFile::Simple->make(-nfs => 1, -hold => 90);

print "Testing pattern 2 (Perl-expanded)...\n";
my $lock = $lockmgr->trylock("test.txt", $pattern2);
if ($lock) {
    print "✅ Lock acquired: " . $lock->lockfile() . "\n";
    $lock->release();
} else {
    print "❌ Failed: $!\n";
}

print "\nTesting pattern 3 (Python-expandable)...\n";
$lock = $lockmgr->trylock("test2.txt", $pattern3);
if ($lock) {
    print "✅ Lock acquired: " . $lock->lockfile() . "\n";
    $lock->release();
} else {
    print "❌ Failed: $!\n";
}

# Cleanup
rmdir $ENV{TEST_LOCKDIR};
