#!/usr/bin/perl
use strict;
use warnings;
use lib '.';
use CPANBridge;

$CPANBridge::DAEMON_MODE = 1;

# Set environment (matching POC)
$ENV{KRB5_CONFIG} = $ENV{KRB5_CONFIG} || '/etc/krb5.conf';
$ENV{KRB5CCNAME} = $ENV{KRB5CCNAME} || '/tmp/krb5cc_1000';

print "=== Kerberos POC Replication Test ===\n\n";

print "Environment:\n";
print "  KRB5_CONFIG: $ENV{KRB5_CONFIG}\n";
print "  KRB5CCNAME: $ENV{KRB5CCNAME}\n\n";

my $bridge = CPANBridge->new();

# Connect (matching POC - dbhost:6136/servicename)
# Update this with your actual database details
my $dsn = 'dbhost:6136/servicename';  # Change to your actual host/service

print "Connecting to $dsn via Kerberos...\n";
my $result = $bridge->call_python('database', 'connect', {
    dsn => $dsn,
    username => '',
    password => ''
    # auth_mode defaults to 'auto' - will detect Kerberos from env vars
});

if (!$result->{success}) {
    print "❌ Connection failed: " . $result->{error} . "\n";
    exit 1;
}

my $conn_id = $result->{result}->{connection_id};
my $auth_mode = $result->{result}->{auth_mode};

print "✅ Connected!\n";
print "  Connection ID: $conn_id\n";
print "  Auth Mode: $auth_mode\n\n";

# Query 1: SELECT user FROM dual (matching POC)
print "Query 1: SELECT user FROM dual\n";
my $user_result = $bridge->call_python('database', 'execute_immediate', {
    connection_id => $conn_id,
    sql => 'SELECT user FROM dual'
});

if ($user_result->{success}) {
    print "✅ Query executed successfully\n";
} else {
    print "❌ Query failed: " . $user_result->{error} . "\n";
}

# Query 2: SELECT COUNT(*) FROM ACQUIRER (matching POC)
# Comment this out if ACQUIRER table doesn't exist in your database
print "\nQuery 2: SELECT COUNT(*) FROM ACQUIRER\n";
my $count_result = $bridge->call_python('database', 'execute_immediate', {
    connection_id => $conn_id,
    sql => 'SELECT COUNT(*) FROM ACQUIRER'
});

if ($count_result->{success}) {
    print "✅ Query executed successfully\n";
} else {
    print "⚠️  Query failed (table may not exist): " . $count_result->{error} . "\n";
}

# Cleanup
print "\nDisconnecting...\n";
$bridge->call_python('database', 'disconnect', {
    connection_id => $conn_id
});

print "\n=== Test Complete ===\n";