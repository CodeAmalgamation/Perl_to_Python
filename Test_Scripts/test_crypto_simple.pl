#!/usr/bin/perl
use strict;
use warnings;
use CPANBridge;

# Enable daemon mode and debug
$CPANBridge::DAEMON_MODE = 1;
$CPANBridge::DEBUG_LEVEL = 1;

print "=== Simple Crypto Test ===\n\n";

my $bridge = CPANBridge->new();

# Test: Create a Blowfish cipher
print "Creating Blowfish cipher...\n";
my $result = $bridge->call_python('crypto', 'new', {
    key => 'TestKey123',
    cipher => 'Blowfish'
});

print "Result:\n";
use Data::Dumper;
print Dumper($result);

if ($result->{success}) {
    my $cipher_id = $result->{result}->{cipher_id};
    print "\n✅ Success! Cipher ID: $cipher_id\n";

    # Test encryption
    print "\nTesting encryption...\n";
    my $encrypt_result = $bridge->call_python('crypto', 'encrypt', {
        cipher_id => $cipher_id,
        plaintext => 'Hello World'
    });

    print "Encryption result:\n";
    print Dumper($encrypt_result);

} else {
    print "\n❌ Failed to create cipher\n";
}

print "\n=== Test Complete ===\n";