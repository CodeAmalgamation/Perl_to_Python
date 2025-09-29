#!/usr/bin/perl
use strict;
use warnings;
use CPANBridge;
use Data::Dumper;

# Enable high-performance daemon mode
$CPANBridge::DAEMON_MODE = 1;
$CPANBridge::DEBUG_LEVEL = 0;

print "=== Testing Rijndael Encryption Support ===\n\n";

my $bridge = CPANBridge->new();

# Test 1: Create a cipher with Rijndael
print "Test 1: Creating Rijndael cipher...\n";
my $result = $bridge->call_python('crypto', 'new', {
    key => 'MyRijndaelKey123',
    cipher => 'Rijndael'
});

if ($result->{success}) {
    my $cipher_id = $result->{result}->{result}->{cipher_id};
    print "✅ Rijndael cipher created successfully! ID: $cipher_id\n\n";

    # Test 2: Encrypt some data with Rijndael
    print "Test 2: Encrypting data with Rijndael...\n";
    my $plaintext = "Hello, World! This is a secret message encrypted with Rijndael.";
    $result = $bridge->call_python('crypto', 'encrypt', {
        cipher_id => $cipher_id,
        plaintext => $plaintext
    });

    if ($result->{success}) {
        my $encrypted_hex = $result->{result}->{result}->{encrypted};
        print "✅ Rijndael encryption successful!\n";
        print "Original: $plaintext\n";
        print "Encrypted (hex): $encrypted_hex\n\n";

        # Test 3: Decrypt the data
        print "Test 3: Decrypting data with Rijndael...\n";
        $result = $bridge->call_python('crypto', 'decrypt', {
            cipher_id => $cipher_id,
            hex_ciphertext => $encrypted_hex
        });

        if ($result->{success}) {
            my $decrypted_text = $result->{result}->{result}->{decrypted};
            print "✅ Rijndael decryption successful!\n";
            print "Decrypted: $decrypted_text\n";

            if ($decrypted_text eq $plaintext) {
                print "✅ Rijndael round-trip test PASSED!\n\n";
            } else {
                print "❌ Rijndael round-trip test FAILED!\n";
                print "Expected: $plaintext\n";
                print "Got: $decrypted_text\n\n";
            }
        } else {
            print "❌ Rijndael decryption failed: " . $result->{error} . "\n\n";
        }

        # Test 4: Test case variations
        print "Test 4: Testing Rijndael case variations...\n";
        for my $cipher_name ('rijndael', 'RIJNDAEL', 'Rijndael') {
            print "  Testing cipher name: '$cipher_name'\n";
            my $test_result = $bridge->call_python('crypto', 'new', {
                key => 'TestKey123',
                cipher => $cipher_name
            });

            if ($test_result->{success}) {
                print "  ✅ '$cipher_name' accepted successfully\n";
                # Cleanup
                my $test_cipher_id = $test_result->{result}->{result}->{cipher_id};
                $bridge->call_python('crypto', 'cleanup_cipher', {
                    cipher_id => $test_cipher_id
                });
            } else {
                print "  ❌ '$cipher_name' failed: " . $test_result->{error} . "\n";
            }
        }
        print "\n";

        # Test 5: Compare Rijndael vs AES (should be identical)
        print "Test 5: Comparing Rijndael vs AES compatibility...\n";

        # Create AES cipher with same key
        my $aes_result = $bridge->call_python('crypto', 'new', {
            key => 'MyRijndaelKey123',
            cipher => 'AES'
        });

        if ($aes_result->{success}) {
            my $aes_cipher_id = $aes_result->{result}->{result}->{cipher_id};

            # Encrypt same text with AES
            my $aes_encrypt = $bridge->call_python('crypto', 'encrypt', {
                cipher_id => $aes_cipher_id,
                plaintext => $plaintext
            });

            if ($aes_encrypt->{success}) {
                my $aes_encrypted = $aes_encrypt->{result}->{result}->{encrypted};
                print "Rijndael encrypted: $encrypted_hex\n";
                print "AES encrypted:      $aes_encrypted\n";

                if ($encrypted_hex eq $aes_encrypted) {
                    print "✅ Rijndael and AES produce identical results!\n";
                } else {
                    print "ℹ️  Rijndael and AES produce different results (expected due to random IV)\n";
                }
            }

            # Cleanup AES cipher
            $bridge->call_python('crypto', 'cleanup_cipher', {
                cipher_id => $aes_cipher_id
            });
        }
        print "\n";

        # Test 6: Test Unicode with Rijndael
        print "Test 6: Testing Unicode encryption with Rijndael...\n";
        my $unicode_text = "Unicode test with Rijndael: 世界 🌍 café naïve résumé";
        $result = $bridge->call_python('crypto', 'encrypt', {
            cipher_id => $cipher_id,
            plaintext => $unicode_text
        });

        if ($result->{success}) {
            my $unicode_encrypted = $result->{result}->{result}->{encrypted};

            # Decrypt it back
            $result = $bridge->call_python('crypto', 'decrypt', {
                cipher_id => $cipher_id,
                hex_ciphertext => $unicode_encrypted
            });

            if ($result->{success} && $result->{result}->{result}->{decrypted} eq $unicode_text) {
                print "✅ Rijndael Unicode encryption test PASSED!\n\n";
            } else {
                print "❌ Rijndael Unicode encryption test FAILED!\n\n";
            }
        } else {
            print "❌ Rijndael Unicode encryption failed: " . $result->{error} . "\n\n";
        }

        # Test 7: Cleanup cipher
        print "Test 7: Cleaning up Rijndael cipher...\n";
        $result = $bridge->call_python('crypto', 'cleanup_cipher', {
            cipher_id => $cipher_id
        });

        if ($result->{success}) {
            print "✅ Rijndael cipher cleanup successful!\n\n";
        } else {
            print "⚠️  Rijndael cipher cleanup warning: " . $result->{error} . "\n\n";
        }

    } else {
        print "❌ Rijndael encryption failed: " . $result->{error} . "\n\n";
    }

} else {
    print "❌ Rijndael cipher creation failed: " . $result->{error} . "\n\n";
}

print "=== Rijndael Encryption Testing Complete ===\n";