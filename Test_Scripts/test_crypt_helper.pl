#!/usr/bin/perl
# test_crypt_helper.pl - Test suite for CryptHelper (Crypt::CBC replacement)
# Tests AutoKit encryption patterns from usage analysis

use strict;
use warnings;
use lib '.';
use CryptHelper;
use File::Temp qw(tempfile);

# Test tracking
our $TEST_COUNT = 0;
our $PASS_COUNT = 0;
our $FAIL_COUNT = 0;

print "=" x 60 . "\n";
print "CryptHelper Test Suite - Crypt::CBC Replacement\n";
print "Based on AutoKit usage analysis patterns\n";
print "=" x 60 . "\n\n";

# Test 1: Basic Crypt::CBC constructor pattern
test_basic_constructor();

# Test 2: AutoKit encrypt/decrypt pattern with hex encoding
test_autokit_pattern();

# Test 3: PEM key file processing
test_pem_key_file();

# Test 4: Multiple cipher algorithms
test_cipher_algorithms();

# Test 5: Error handling
test_error_handling();

# Test 6: Crypt::CBC compatibility wrapper
test_crypt_cbc_compatibility();

# Test Summary
print "\n" . "=" x 60 . "\n";
print "TEST SUMMARY\n";
print "=" x 60 . "\n";
print "Total Tests: $TEST_COUNT\n";
print "Passed: $PASS_COUNT\n";
print "Failed: $FAIL_COUNT\n";

if ($FAIL_COUNT == 0) {
    print "\nSUCCESS: CryptHelper ready for AutoKit integration!\n";
    print "Ready to replace: use Crypt::CBC; with use CryptHelper;\n";
    exit 0;
} else {
    print "\nFAILED: Review failures before deployment\n";
    exit 1;
}

#================================================================
# TEST FUNCTIONS
#================================================================

sub test_basic_constructor {
    print_test_header("Basic Constructor Pattern");

    # Test 1a: Simple key constructor
    my $cipher = eval { CryptHelper->new(-key => "TestKey123", -cipher => "Blowfish") };
    test_result("Basic constructor", defined($cipher) && !$@, $@ || "Success");

    # Test 1b: Check cipher properties
    if ($cipher) {
        my $cipher_type = eval { $cipher->cipher() };
        test_result("Cipher type", $cipher_type eq "Blowfish", "Expected Blowfish, got: " . ($cipher_type || "undef"));
    }

    print_test_footer();
}

sub test_autokit_pattern {
    print_test_header("AutoKit Encrypt/Decrypt Pattern");

    # Simulate AutoKit configuration
    my $test_key = "AutoKitTestKey2023";
    my $test_cipher = "Blowfish";
    my $test_plaintext = "DatabasePassword123!";

    # Test 2a: Create cipher (AutoKit style)
    my $cipher = eval {
        CryptHelper->new(
            -key    => $test_key,
            -cipher => $test_cipher
        )
    };
    test_result("AutoKit cipher creation", defined($cipher) && !$@, $@ || "Success");

    if (!$cipher) {
        print_test_footer();
        return;
    }

    # Test 2b: Encrypt (matches: return unpack('H*', $cipher->encrypt($text)))
    my $hex_encrypted = eval { $cipher->encrypt($test_plaintext) };
    test_result("Encryption to hex", defined($hex_encrypted) && !$@, $@ || "Success");

    if ($hex_encrypted) {
        test_result("Hex format check", $hex_encrypted =~ /^[0-9a-fA-F]+$/, "Pattern validation");
        print "  Encrypted: " . substr($hex_encrypted, 0, 32) . "...\n" if length($hex_encrypted) > 32;
    }

    # Test 2c: Decrypt (matches: return $cipher->decrypt(pack('H*', $text)))
    my $decrypted = eval { $cipher->decrypt($hex_encrypted) } if $hex_encrypted;
    test_result("Decryption from hex", defined($decrypted) && !$@, $@ || "Success");

    # Test 2d: Round-trip verification
    if ($decrypted) {
        test_result("Round-trip integrity", $decrypted eq $test_plaintext,
                   "Expected: '$test_plaintext', Got: '$decrypted'");
    }

    print_test_footer();
}

sub test_pem_key_file {
    print_test_header("PEM Key File Processing");

    # Test 3a: Create temporary PEM-like key file
    my ($fh, $key_file) = tempfile(SUFFIX => '.pem', UNLINK => 1);

    # Write PEM-style content (matches AutoKit format)
    my $pem_content = <<'EOF';
-----BEGIN PRIVATE KEY-----
VGhpc0lzQVRlc3RLZXlGb3JBdXRvS2l0VGVzdGluZzEyMw==
-----END PRIVATE KEY-----
EOF

    print $fh $pem_content;
    close $fh;

    test_result("PEM file created", -f $key_file, "File creation");

    # Test 3b: Use key file (AutoKit pattern)
    my $cipher = eval { CryptHelper->new(-key_file => $key_file, -cipher => "Blowfish") };
    test_result("PEM key file loading", defined($cipher) && !$@, $@ || "Success");

    # Test 3c: Encryption with PEM key
    if ($cipher) {
        my $test_text = "ConfigPassword";
        my $encrypted = eval { $cipher->encrypt($test_text) };
        test_result("PEM key encryption", defined($encrypted) && !$@, $@ || "Success");

        if ($encrypted) {
            my $decrypted = eval { $cipher->decrypt($encrypted) };
            test_result("PEM key round-trip", $decrypted eq $test_text, "Verification");
        }
    }

    print_test_footer();
}

sub test_cipher_algorithms {
    print_test_header("Multiple Cipher Algorithms");

    my $test_key = "MultiAlgorithmTestKey";
    my $test_text = "AlgorithmTest";

    # Test different algorithms that AutoKit might use
    my @algorithms = ("Blowfish");  # Start with primary, add others if available

    for my $algorithm (@algorithms) {
        my $cipher = eval { CryptHelper->new(-key => $test_key, -cipher => $algorithm) };
        my $success = defined($cipher) && !$@;
        test_result("$algorithm cipher", $success, $@ || "Success");

        if ($cipher) {
            my $encrypted = eval { $cipher->encrypt($test_text) };
            my $decrypted = eval { $cipher->decrypt($encrypted) } if $encrypted;
            test_result("$algorithm round-trip",
                       $decrypted && $decrypted eq $test_text, "Verification");
        }
    }

    print_test_footer();
}

sub test_error_handling {
    print_test_header("Error Handling");

    # Test 5a: Missing key
    my $cipher = eval { CryptHelper->new(-cipher => "Blowfish") };
    test_result("Missing key error", !defined($cipher), "Should fail without key");

    # Test 5b: Invalid key file
    my $bad_cipher = eval { CryptHelper->new(-key_file => "/nonexistent/file.pem", -cipher => "Blowfish") };
    test_result("Bad key file error", !defined($bad_cipher), "Should fail with bad file");

    # Test 5c: Invalid cipher algorithm
    my $bad_alg = eval { CryptHelper->new(-key => "test", -cipher => "InvalidAlgorithm") };
    test_result("Bad algorithm error", !defined($bad_alg), "Should fail with bad algorithm");

    print_test_footer();
}

sub test_crypt_cbc_compatibility {
    print_test_header("Crypt::CBC Compatibility Wrapper");

    # Test 6a: Direct Crypt::CBC usage (should be redirected to CryptHelper)
    my $cbc_cipher = eval {
        # This should work due to our import compatibility wrapper
        no strict 'refs';
        my $class = "Crypt::CBC";
        $class->new(-key => "CBCTestKey", -cipher => "Blowfish");
    };

    test_result("Crypt::CBC compatibility", defined($cbc_cipher) && !$@, $@ || "Success");

    if ($cbc_cipher) {
        # Test 6b: Methods work through compatibility layer
        my $test_text = "CompatibilityTest";
        my $encrypted = eval { $cbc_cipher->encrypt($test_text) };
        test_result("CBC compatibility encrypt", defined($encrypted) && !$@, $@ || "Success");

        if ($encrypted) {
            my $decrypted = eval { $cbc_cipher->decrypt($encrypted) };
            test_result("CBC compatibility decrypt",
                       $decrypted && $decrypted eq $test_text, "Round-trip test");
        }
    }

    print_test_footer();
}

#================================================================
# UTILITY FUNCTIONS
#================================================================

sub test_result {
    my ($test_name, $condition, $details) = @_;

    $TEST_COUNT++;

    if ($condition) {
        $PASS_COUNT++;
        print "PASS: $test_name\n";
    } else {
        $FAIL_COUNT++;
        print "FAIL: $test_name";
        print " - $details" if $details;
        print "\n";
    }
}

sub print_test_header {
    my $title = shift;
    print "\n" . "-" x 50 . "\n";
    print "$title\n";
    print "-" x 50 . "\n";
}

sub print_test_footer {
    print "\n";
}