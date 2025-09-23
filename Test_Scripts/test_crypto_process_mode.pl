#!/usr/bin/perl
use strict;
use warnings;
use CPANBridge;

# Force process mode to test crypto module
$CPANBridge::DAEMON_MODE = 0;

print "=== Testing Crypto Helper (Process Mode) ===\n\n";

my $bridge = CPANBridge->new();

# Test 1: Create Blowfish cipher
print "Test 1: Creating Blowfish cipher...\n";
my $result = $bridge->call_python('crypto', 'new', {
    key => 'MySecretKey123',
    cipher => 'Blowfish'
});

if ($result->{success}) {
    my $cipher_id = $result->{result}->{cipher_id};
    print "✅ Cipher created! ID: $cipher_id\n\n";

    # Test 2: Encrypt data
    print "Test 2: Encrypting data...\n";
    my $plaintext = "Hello, Crypto World!";
    $result = $bridge->call_python('crypto', 'encrypt', {
        cipher_id => $cipher_id,
        plaintext => $plaintext
    });

    if ($result->{success}) {
        my $encrypted = $result->{result}->{encrypted};
        print "✅ Encryption successful!\n";
        print "Original: $plaintext\n";
        print "Encrypted: $encrypted\n\n";

        # Test 3: Decrypt data
        print "Test 3: Decrypting data...\n";
        $result = $bridge->call_python('crypto', 'decrypt', {
            cipher_id => $cipher_id,
            hex_ciphertext => $encrypted
        });

        if ($result->{success}) {
            my $decrypted = $result->{result}->{decrypted};
            print "✅ Decryption successful!\n";
            print "Decrypted: $decrypted\n";

            if ($decrypted eq $plaintext) {
                print "✅ ROUND-TRIP TEST PASSED!\n\n";
            } else {
                print "❌ Round-trip test failed!\n\n";
            }
        } else {
            print "❌ Decryption failed: " . $result->{error} . "\n\n";
        }

        # Cleanup
        $bridge->call_python('crypto', 'cleanup_cipher', { cipher_id => $cipher_id });

    } else {
        print "❌ Encryption failed: " . $result->{error} . "\n\n";
    }

} else {
    print "❌ Cipher creation failed: " . $result->{error} . "\n\n";
}

# Test AES
print "Test 4: Testing AES cipher...\n";
$result = $bridge->call_python('crypto', 'new', {
    key => 'AESTestKey123456',  # 16-byte key
    cipher => 'AES'
});

if ($result->{success}) {
    print "✅ AES cipher created successfully!\n";
    my $aes_id = $result->{result}->{cipher_id};

    # Quick AES test
    $result = $bridge->call_python('crypto', 'encrypt', {
        cipher_id => $aes_id,
        plaintext => "AES Test"
    });

    if ($result->{success}) {
        print "✅ AES encryption works!\n";
    }

    $bridge->call_python('crypto', 'cleanup_cipher', { cipher_id => $aes_id });
} else {
    print "❌ AES failed: " . $result->{error} . "\n";
}

print "\n=== Crypto Testing Complete ===\n";