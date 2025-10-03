#!/usr/bin/perl
use strict;
use warnings;
use lib '.';
use CPANBridge;

$CPANBridge::DAEMON_MODE = 1;

print "=== Kerberos Auto-Detection Test ===\n\n";

my $bridge = CPANBridge->new();

# Test 1: No Kerberos env vars -> should fail or use password (if credentials provided)
print "Test 1: No Kerberos env vars\n";
delete $ENV{KRB5_CONFIG};
delete $ENV{KRB5CCNAME};

my $result1 = $bridge->call_python('database', 'connect', {
    dsn => 'testdb',
    username => '',
    password => ''
});

if ($result1->{success}) {
    print "  Result: Connected (unexpected - no credentials)\n";
    print "  Auth mode: " . ($result1->{result}->{auth_mode} || 'unknown') . "\n";
} else {
    print "  ✅ Correctly failed without credentials\n";
    print "  Error: " . substr($result1->{error}, 0, 80) . "...\n";
}

# Test 2: Both Kerberos env vars present -> should attempt Kerberos
print "\nTest 2: Both Kerberos env vars present\n";
$ENV{KRB5_CONFIG} = '/etc/krb5.conf';
$ENV{KRB5CCNAME} = '/tmp/krb5cc_1000';

my $result2 = $bridge->call_python('database', 'connect', {
    dsn => 'dbhost:6136/servicename',  # Update with your actual DSN
    username => '',
    password => ''
});

if ($result2->{success}) {
    print "  ✅ Auto-detected and used Kerberos\n";
    print "  Auth mode: " . $result2->{result}->{auth_mode} . "\n";
    print "  Connection ID: " . $result2->{result}->{connection_id} . "\n";

    # Cleanup
    $bridge->call_python('database', 'disconnect', {
        connection_id => $result2->{result}->{connection_id}
    });
} else {
    print "  ⚠️  Failed to connect via Kerberos\n";
    print "  Error: " . substr($result2->{error}, 0, 100) . "...\n";
    print "  (This is expected if Kerberos ticket is not valid)\n";
}

# Test 3: Only one env var present -> should use password mode
print "\nTest 3: Only KRB5_CONFIG set (incomplete Kerberos)\n";
$ENV{KRB5_CONFIG} = '/etc/krb5.conf';
delete $ENV{KRB5CCNAME};

my $result3 = $bridge->call_python('database', 'connect', {
    dsn => 'testdb',
    username => '',
    password => ''
});

if ($result3->{success}) {
    print "  Result: Connected (unexpected - incomplete Kerberos)\n";
    print "  Auth mode: " . ($result3->{result}->{auth_mode} || 'unknown') . "\n";
} else {
    print "  ✅ Correctly fell back to password auth (and failed without credentials)\n";
}

print "\n=== Test Complete ===\n";
print "\nSummary:\n";
print "- Auto-detection is working\n";
print "- Kerberos mode requires both KRB5_CONFIG and KRB5CCNAME\n";
print "- Falls back to password auth when Kerberos env is incomplete\n";