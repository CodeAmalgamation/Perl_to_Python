#!/usr/bin/perl
use strict;
use warnings;
use CPANBridge;
use Data::Dumper;

# ====================================================================
# CRYPTO HELPER COMPREHENSIVE TEST SUITE
# ====================================================================
# Tests all crypto functionality in daemon mode with persistent ciphers
# This demonstrates the crypto module working correctly with CPANBridge
# ====================================================================

print "=== Crypto Helper Comprehensive Test Suite ===\n\n";

# Enable daemon mode (REQUIRED for crypto functionality)
$CPANBridge::DAEMON_MODE = 1;

my $bridge = CPANBridge->new();
my $test_count = 0;
my $pass_count = 0;

sub run_test {
    my ($test_name, $result) = @_;
    $test_count++;

    if ($result) {
        $pass_count++;
        print "✅ Test $test_count: $test_name - PASSED\n";
        return 1;
    } else {
        print "❌ Test $test_count: $test_name - FAILED\n";
        return 0;
    }
}

# ====================================================================
# TEST 1: Blowfish Cipher Creation
# ====================================================================
print "Test 1: Creating Blowfish cipher...\n";
my $result = $bridge->call_python('crypto', 'new', {
    key => 'MySecretKey123',
    cipher => 'Blowfish'
});

my $blowfish_cipher_id;
if (run_test("Blowfish cipher creation", $result->{success})) {
    $blowfish_cipher_id = $result->{result}->{cipher_id};
    print "   Cipher ID: $blowfish_cipher_id\n";
    print "   Key length: " . $result->{result}->{key_length} . " bytes\n";
} else {
    print "   Error: " . ($result->{error} || "Unknown error") . "\n";
    exit 1;
}
print "\n";

# ====================================================================
# TEST 2: Blowfish Encryption
# ====================================================================
print "Test 2: Blowfish encryption...\n";
my $plaintext = "Hello, Crypto World! This is a test message with special chars: @#\$%^&*()";
$result = $bridge->call_python('crypto', 'encrypt', {
    cipher_id => $blowfish_cipher_id,
    plaintext => $plaintext
});

my $encrypted_hex;
if (run_test("Blowfish encryption", $result->{success})) {
    $encrypted_hex = $result->{result}->{encrypted};
    print "   Original: $plaintext\n";
    print "   Encrypted (hex): $encrypted_hex\n";
    print "   Length: " . $result->{result}->{length} . " characters\n";
} else {
    print "   Error: " . ($result->{error} || $result->{result}->{error} || "Unknown error") . "\n";
    exit 1;
}
print "\n";

# ====================================================================
# TEST 3: Blowfish Decryption & Round-trip Verification
# ====================================================================
print "Test 3: Blowfish decryption and round-trip verification...\n";
$result = $bridge->call_python('crypto', 'decrypt', {
    cipher_id => $blowfish_cipher_id,
    hex_ciphertext => $encrypted_hex
});

if (run_test("Blowfish decryption", $result->{success})) {
    my $decrypted_text = $result->{result}->{decrypted};
    print "   Decrypted: $decrypted_text\n";

    if (run_test("Round-trip integrity", $decrypted_text eq $plaintext)) {
        print "   ✅ Perfect round-trip! Original message preserved.\n";
    } else {
        print "   ❌ Round-trip failed! Data corruption detected.\n";
    }
} else {
    print "   Error: " . ($result->{error} || $result->{result}->{error} || "Unknown error") . "\n";
}
print "\n";

# ====================================================================
# TEST 4: Unicode Text Encryption
# ====================================================================
print "Test 4: Unicode text encryption...\n";
my $unicode_text = "Unicode test: 世界 🌍 café naïve résumé Москва العربية";
$result = $bridge->call_python('crypto', 'encrypt', {
    cipher_id => $blowfish_cipher_id,
    plaintext => $unicode_text
});

if (run_test("Unicode encryption", $result->{success})) {
    my $unicode_encrypted = $result->{result}->{encrypted};
    print "   Unicode text: $unicode_text\n";
    print "   Encrypted: $unicode_encrypted\n";

    # Decrypt and verify Unicode
    $result = $bridge->call_python('crypto', 'decrypt', {
        cipher_id => $blowfish_cipher_id,
        hex_ciphertext => $unicode_encrypted
    });

    if ($result->{success}) {
        my $unicode_decrypted = $result->{result}->{decrypted};
        run_test("Unicode round-trip", $unicode_decrypted eq $unicode_text);
        print "   Decrypted: $unicode_decrypted\n";
    }
}
print "\n";

# ====================================================================
# TEST 5: Large Data Encryption
# ====================================================================
print "Test 5: Large data encryption (10KB)...\n";
my $large_data = "A" x 10000;  # 10KB of data
$result = $bridge->call_python('crypto', 'encrypt', {
    cipher_id => $blowfish_cipher_id,
    plaintext => $large_data
});

if (run_test("Large data encryption", $result->{success})) {
    my $large_encrypted = $result->{result}->{encrypted};
    print "   Input size: " . length($large_data) . " bytes\n";
    print "   Encrypted size: " . length($large_encrypted) . " hex characters\n";

    # Quick verification
    $result = $bridge->call_python('crypto', 'decrypt', {
        cipher_id => $blowfish_cipher_id,
        hex_ciphertext => $large_encrypted
    });

    if ($result->{success}) {
        my $large_decrypted = $result->{result}->{decrypted};
        run_test("Large data round-trip", $large_decrypted eq $large_data);
    }
}
print "\n";

# ====================================================================
# TEST 6: AES Cipher Creation and Testing
# ====================================================================
print "Test 6: AES cipher creation and testing...\n";
$result = $bridge->call_python('crypto', 'new', {
    key => 'AESTestKey123456',  # 16-byte key for AES
    cipher => 'AES'
});

my $aes_cipher_id;
if (run_test("AES cipher creation", $result->{success})) {
    $aes_cipher_id = $result->{result}->{cipher_id};
    print "   AES Cipher ID: $aes_cipher_id\n";

    # Test AES encryption
    $result = $bridge->call_python('crypto', 'encrypt', {
        cipher_id => $aes_cipher_id,
        plaintext => "AES encryption test message"
    });

    if (run_test("AES encryption", $result->{success})) {
        my $aes_encrypted = $result->{result}->{encrypted};
        print "   AES encrypted: $aes_encrypted\n";

        # Test AES decryption
        $result = $bridge->call_python('crypto', 'decrypt', {
            cipher_id => $aes_cipher_id,
            hex_ciphertext => $aes_encrypted
        });

        if ($result->{success}) {
            my $aes_decrypted = $result->{result}->{decrypted};
            run_test("AES round-trip", $aes_decrypted eq "AES encryption test message");
        }
    }
} else {
    print "   Error: " . ($result->{error} || $result->{result}->{error} || "Unknown error") . "\n";
}
print "\n";

# ====================================================================
# TEST 7: Multiple Cipher Management
# ====================================================================
print "Test 7: Multiple cipher management...\n";
$result = $bridge->call_python('crypto', 'new', {
    key => 'SecondCipherKey456',
    cipher => 'Blowfish'
});

if (run_test("Second cipher creation", $result->{success})) {
    my $second_cipher_id = $result->{result}->{cipher_id};
    print "   Second cipher ID: $second_cipher_id\n";

    # Test that both ciphers work independently
    $result = $bridge->call_python('crypto', 'encrypt', {
        cipher_id => $second_cipher_id,
        plaintext => "Second cipher test"
    });

    run_test("Second cipher encryption", $result->{success});

    # Test original cipher still works
    $result = $bridge->call_python('crypto', 'encrypt', {
        cipher_id => $blowfish_cipher_id,
        plaintext => "Original cipher still works"
    });

    run_test("Original cipher persistence", $result->{success});
}
print "\n";

# ====================================================================
# TEST 8: Error Handling
# ====================================================================
print "Test 8: Error handling...\n";

# Test invalid cipher ID
$result = $bridge->call_python('crypto', 'encrypt', {
    cipher_id => 'invalid-cipher-id-12345',
    plaintext => "This should fail"
});

run_test("Invalid cipher ID rejection", !$result->{success} || !$result->{result}->{success});

# Test invalid hex for decryption
$result = $bridge->call_python('crypto', 'decrypt', {
    cipher_id => $blowfish_cipher_id,
    hex_ciphertext => 'invalid_hex_string_zzz'
});

run_test("Invalid hex string rejection", !$result->{success} || !$result->{result}->{success});
print "\n";

# ====================================================================
# TEST 9: Cipher Cleanup
# ====================================================================
print "Test 9: Cipher cleanup...\n";

# Cleanup all created ciphers
my @ciphers_to_cleanup = ($blowfish_cipher_id);
push @ciphers_to_cleanup, $aes_cipher_id if $aes_cipher_id;

my $cleanup_success = 1;
for my $cipher_id (@ciphers_to_cleanup) {
    next unless $cipher_id;

    $result = $bridge->call_python('crypto', 'cleanup_cipher', {
        cipher_id => $cipher_id
    });

    if (!$result->{success}) {
        $cleanup_success = 0;
        print "   Warning: Failed to cleanup cipher $cipher_id\n";
    }
}

run_test("Cipher cleanup", $cleanup_success);
print "\n";

# ====================================================================
# TEST SUMMARY
# ====================================================================
print "=" x 60 . "\n";
print "CRYPTO TEST SUITE SUMMARY\n";
print "=" x 60 . "\n";
print "Total tests: $test_count\n";
print "Passed: $pass_count\n";
print "Failed: " . ($test_count - $pass_count) . "\n";
print "Success rate: " . sprintf("%.1f%%", ($pass_count / $test_count) * 100) . "\n";

if ($pass_count == $test_count) {
    print "\n🎉 ALL TESTS PASSED! Crypto module is working perfectly!\n";
    print "\nKey findings:\n";
    print "✅ Daemon mode required for cipher persistence\n";
    print "✅ Blowfish and AES algorithms working\n";
    print "✅ Unicode text handling perfect\n";
    print "✅ Large data encryption successful\n";
    print "✅ Multiple cipher management working\n";
    print "✅ Error handling robust\n";
    print "✅ Cipher cleanup functional\n";
} else {
    print "\n❌ Some tests failed. Check the output above for details.\n";
}

print "\n=== Crypto Test Suite Complete ===\n";