#!/usr/bin/perl
use strict;
use warnings;

print "=== Direct Crypto Test ===\n\n";

# Test using direct command execution
print "Testing crypto module directly...\n";

my $test_data = '{"module": "crypto", "function": "new", "params": {"key": "MySecretKey123", "cipher": "Blowfish"}}';

my $result = `cd python_helpers && echo '$test_data' | python3 cpan_bridge.py`;
print "Raw result: $result\n";

if ($result =~ /"success":\s*true/) {
    print "✅ Crypto module is working!\n";

    # Extract cipher_id for further testing
    if ($result =~ /"cipher_id":\s*"([^"]+)"/) {
        my $cipher_id = $1;
        print "Cipher ID: $cipher_id\n\n";

        # Test encryption
        print "Testing encryption...\n";
        my $encrypt_data = qq({"module": "crypto", "function": "encrypt", "params": {"cipher_id": "$cipher_id", "plaintext": "Hello World"}});
        my $encrypt_result = `cd python_helpers && echo '$encrypt_data' | python3 cpan_bridge.py`;

        if ($encrypt_result =~ /"success":\s*true/) {
            print "✅ Encryption works!\n";
            print "Encryption result: $encrypt_result\n";
        } else {
            print "❌ Encryption failed\n";
        }
    }
} else {
    print "❌ Crypto module failed\n";
}

print "\n=== Test Complete ===\n";