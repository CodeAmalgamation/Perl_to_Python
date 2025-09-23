#!/usr/bin/perl
use strict;
use warnings;
use CPANBridge;
use Data::Dumper;

# Enable high-performance daemon mode
$CPANBridge::DAEMON_MODE = 1;

print "=== Testing Crypto Helper Module ===\n\n";

my $bridge = CPANBridge->new();

# Test 1: Create a cipher with Blowfish
print "Test 1: Creating Blowfish cipher...\n";
my $result = $bridge->call_python('crypto', 'new', {
    key => 'MySecretKey123',
    cipher => 'Blowfish'
});

if ($result->{success}) {
    my $cipher_id = $result->{result}->{cipher_id};
    print "✅ Cipher created successfully! ID: $cipher_id\n\n";

    # Test 2: Encrypt some data
    print "Test 2: Encrypting data...\n";
    my $plaintext = "Hello, World! This is a secret message.";
    $result = $bridge->call_python('crypto', 'encrypt', {
        cipher_id => $cipher_id,
        plaintext => $plaintext
    });

    if ($result->{success}) {
        my $encrypted_hex = $result->{result}->{encrypted};
        print "✅ Encryption successful!\n";
        print "Original: $plaintext\n";
        print "Encrypted (hex): $encrypted_hex\n\n";

        # Test 3: Decrypt the data
        print "Test 3: Decrypting data...\n";
        $result = $bridge->call_python('crypto', 'decrypt', {
            cipher_id => $cipher_id,
            hex_ciphertext => $encrypted_hex
        });

        if ($result->{success}) {
            my $decrypted_text = $result->{result}->{decrypted};
            print "✅ Decryption successful!\n";
            print "Decrypted: $decrypted_text\n";

            if ($decrypted_text eq $plaintext) {
                print "✅ Round-trip test PASSED!\n\n";
            } else {
                print "❌ Round-trip test FAILED!\n\n";
            }
        } else {
            print "❌ Decryption failed: " . $result->{error} . "\n\n";
        }

        # Test 4: Test with Unicode
        print "Test 4: Testing Unicode encryption...\n";
        my $unicode_text = "Unicode test: 世界 🌍 café naïve résumé";
        $result = $bridge->call_python('crypto', 'encrypt', {
            cipher_id => $cipher_id,
            plaintext => $unicode_text
        });

        if ($result->{success}) {
            my $unicode_encrypted = $result->{result}->{encrypted};

            # Decrypt it back
            $result = $bridge->call_python('crypto', 'decrypt', {
                cipher_id => $cipher_id,
                hex_ciphertext => $unicode_encrypted
            });

            if ($result->{success} && $result->{result}->{decrypted} eq $unicode_text) {
                print "✅ Unicode encryption test PASSED!\n\n";
            } else {
                print "❌ Unicode encryption test FAILED!\n\n";
            }
        } else {
            print "❌ Unicode encryption failed: " . $result->{error} . "\n\n";
        }

        # Test 5: Cleanup cipher
        print "Test 5: Cleaning up cipher...\n";
        $result = $bridge->call_python('crypto', 'cleanup_cipher', {
            cipher_id => $cipher_id
        });

        if ($result->{success}) {
            print "✅ Cipher cleanup successful!\n\n";
        } else {
            print "⚠️  Cipher cleanup warning: " . $result->{error} . "\n\n";
        }

    } else {
        print "❌ Encryption failed: " . $result->{error} . "\n\n";
    }

} else {
    print "❌ Cipher creation failed: " . $result->{error} . "\n\n";
}

# Test 6: Test AES cipher
print "Test 6: Testing AES cipher...\n";
$result = $bridge->call_python('crypto', 'new', {
    key => 'AESTestKey123456',  # 16-byte key for AES
    cipher => 'AES'
});

if ($result->{success}) {
    my $aes_cipher_id = $result->{result}->{cipher_id};
    print "✅ AES cipher created successfully!\n";

    # Test AES encryption/decryption
    $result = $bridge->call_python('crypto', 'encrypt', {
        cipher_id => $aes_cipher_id,
        plaintext => "AES test message"
    });

    if ($result->{success}) {
        my $aes_encrypted = $result->{result}->{encrypted};

        $result = $bridge->call_python('crypto', 'decrypt', {
            cipher_id => $aes_cipher_id,
            hex_ciphertext => $aes_encrypted
        });

        if ($result->{success} && $result->{result}->{decrypted} eq "AES test message") {
            print "✅ AES round-trip test PASSED!\n\n";
        } else {
            print "❌ AES round-trip test FAILED!\n\n";
        }
    } else {
        print "❌ AES encryption failed: " . $result->{error} . "\n\n";
    }

    # Cleanup AES cipher
    $bridge->call_python('crypto', 'cleanup_cipher', { cipher_id => $aes_cipher_id });
} else {
    print "❌ AES cipher creation failed: " . $result->{error} . "\n\n";
}

# Test 7: Test hash function
print "Test 7: Testing hash function...\n";
$result = $bridge->call_python('crypto', 'hash', {
    data => 'test data for hashing',
    algorithm => 'SHA256'
});

if ($result->{success}) {
    my $hash_result = $result->{result}->{hash};
    print "✅ Hash function successful!\n";
    print "Input: 'test data for hashing'\n";
    print "SHA256: $hash_result\n\n";
} else {
    print "❌ Hash function failed: " . $result->{error} . "\n\n";
}

print "=== Crypto Helper Testing Complete ===\n";