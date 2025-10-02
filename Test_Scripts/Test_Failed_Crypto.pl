#!/usr/bin/perl

use strict;

use warnings;

use lib '.';

use CPANBridge;

use Data::Dumper;

use utf8;

use open ':std', ':encoding(UTF-8)';

use Encode qw(decode encode);



# ====================================================================

# FAILED CRYPTO TEST CASES - FOCUSED DEBUGGING 

# ====================================================================

# This script focuses on the 5 failed test cases from the main suite

# to debug and understand the root causes of failures

# ====================================================================



print "=== Failed Crypto Test Cases - Focused Debugging ===\n\n";



# Enable daemon mode (REQUIRED for crypto functionality)

$CPANBridge::DAEMON_MODE = 1;



my $bridge = CPANBridge->new();

my $test_count = 0;

my $pass_count = 0;



sub run_test {

  my ($test_name, $result, $debug_info) = @_;

  $test_count++;



  if ($result) {

    $pass_count++;

    print "✅ Test $test_count: $test_name - PASSED\n";

    return 1;

  } else {

    print "❌ Test $test_count: $test_name - FAILED\n";

    if ($debug_info) {

      print "  DEBUG: $debug_info\n";

    }

    return 0;

  }

}



# Create a working cipher for testing

print "Setting up test cipher...\n";

my $result = $bridge->call_python('crypto', 'new', {

  key => 'TestKey123456789',

  cipher => 'Blowfish'

});



my $test_cipher_id;

if ($result->{success}) {

  $test_cipher_id = $result->{result}->{cipher_id};

  print "✅ Test cipher created: $test_cipher_id\n\n";

} else {

  print "❌ Failed to create test cipher: " . ($result->{error} || "Unknown error") . "\n";

  exit 1;

}


# ====================================================================

# FAILED TEST 1 & 2: Invalid Key Size Errors

# ====================================================================

print "=== Testing Invalid Key Size Error Handling ===\n";



# Test invalid AES key size (too short)

print "Test 1: Invalid AES key size error handling...\n";

$result = $bridge->call_python('crypto', 'new', {

  key => 'tooshort', # Only 8 bytes, AES needs 16/24/32

  cipher => 'AES'

});



print "  AES short key result: " . Dumper($result) . "\n";

my $aes_error_check = !$result->{success};

run_test("Invalid AES key size should fail", $aes_error_check,

  "Expected failure but got success: " . ($result->{success} ? "YES" : "NO"));



if ($result->{error}) {

  print "  AES Error message: " . $result->{error} . "\n";

  my $has_key_error = $result->{error} =~ /key|size|invalid|length/i;

  run_test("AES error message mentions key/size", $has_key_error,

    "Error message: '" . $result->{error} . "'");

} else {

  print "  ❌ No error message provided for invalid AES key\n";

}



# Test invalid Blowfish key size (too short)

print "\nTest 2: Invalid Blowfish key size error handling...\n";

$result = $bridge->call_python('crypto', 'new', {

  key => 'x', # Only 1 byte, too short for Blowfish minimum

  cipher => 'Blowfish'

});



print "  Blowfish short key result: " . Dumper($result) . "\n";

my $blowfish_error_check = !$result->{success};

run_test("Invalid Blowfish key size should fail", $blowfish_error_check,

  "Expected failure but got success: " . ($result->{success} ? "YES" : "NO"));



if ($result->{error}) {

  print "  Blowfish Error message: " . $result->{error} . "\n";

  my $has_key_error = $result->{error} =~ /key|size|invalid|length/i;

  run_test("Blowfish error message mentions key/size", $has_key_error,

    "Error message: '" . $result->{error} . "'");

} else {

  print "  ❌ No error message provided for invalid Blowfish key\n";

}



print "\n";


# ====================================================================

# FAILED TEST 3: Newlines Round-trip

# ====================================================================

print "=== Testing Newlines Round-trip ===\n";



my $newlines_data = "Line1\nLine2\r\nLine3\tTabbed";

print "Test 3: Newlines round-trip...\n";

print "  Original data: " . join("", map { sprintf("\\x%02x", ord($_)) } split //, $newlines_data) . "\n";

print "  Original readable: '$newlines_data'\n";



$result = $bridge->call_python('crypto', 'encrypt', {

  cipher_id => $test_cipher_id,

  plaintext_hex => unpack('H*', $newlines_data)

});



if ($result->{success}) {

  my $encrypted = $result->{result}->{encrypted};

  print "  Encrypted: $encrypted\n";



  $result = $bridge->call_python('crypto', 'decrypt', {

    cipher_id => $test_cipher_id,

    hex_ciphertext => $encrypted

  });



  if ($result->{success}) {

    my $decrypted_hex = $result->{result}->{decrypted_hex};
    my $decrypted = pack('H*', $decrypted_hex);

    print "  Decrypted data: " . join("", map { sprintf("\\x%02x", ord($_)) } split //, $decrypted) . "\n";

    print "  Decrypted readable: '$decrypted'\n";

    print "  Original length: " . length($newlines_data) . "\n";

    print "  Decrypted length: " . length($decrypted) . "\n";



    my $matches = ($decrypted eq $newlines_data);

    run_test("Newlines round-trip", $matches,

      "Original != Decrypted - may be newline conversion issue");



    # Character-by-character comparison

    if (!$matches) {

      print "  Character-by-character comparison:\n";

      my @orig_chars = split //, $newlines_data;

      my @dec_chars = split //, $decrypted;

      my $max_len = (length($newlines_data) > length($decrypted)) ? length($newlines_data) : length($decrypted);



      for my $i (0..$max_len-1) {

        my $orig_char = $i < @orig_chars ? sprintf("\\x%02x", ord($orig_chars[$i])) : "EOF";

        my $dec_char = $i < @dec_chars ? sprintf("\\x%02x", ord($dec_chars[$i])) : "EOF";

        if ($orig_char ne $dec_char) {

          print "  Position $i: Original=$orig_char, Decrypted=$dec_char\n";

        }

      }

    }

  } else {

    print "  ❌ Decryption failed: " . ($result->{error} || "Unknown error") . "\n";

  }

} else {

  print "  ❌ Encryption failed: " . ($result->{error} || "Unknown error") . "\n";

}



print "\n";


# ====================================================================

# FAILED TEST 4: Null Bytes Round-trip

# ====================================================================

print "=== Testing Null Bytes Round-trip ===\n";



my $null_data = "\x00Null\x00";

print "Test 4: Null bytes round-trip...\n";

print "  Original data: " . join("", map { sprintf("\\x%02x", ord($_)) } split //, $null_data) . "\n";

print "  Original readable: '$null_data'\n";



$result = $bridge->call_python('crypto', 'encrypt', {

  cipher_id => $test_cipher_id,

  plaintext_hex => unpack('H*', $null_data)

});



if ($result->{success}) {

  my $encrypted = $result->{result}->{encrypted};

  print "  Encrypted: $encrypted\n";



  $result = $bridge->call_python('crypto', 'decrypt', {

    cipher_id => $test_cipher_id,

    hex_ciphertext => $encrypted

  });



  if ($result->{success}) {

    my $decrypted_hex = $result->{result}->{decrypted_hex};
    my $decrypted = pack('H*', $decrypted_hex);

    print "  Decrypted data: " . join("", map { sprintf("\\x%02x", ord($_)) } split //, $decrypted) . "\n";

    print "  Decrypted readable: '$decrypted'\n";

    print "  Original length: " . length($null_data) . "\n";

    print "  Decrypted length: " . length($decrypted) . "\n";



    my $matches = ($decrypted eq $null_data);

    run_test("Null bytes round-trip", $matches,

      "Null bytes may be truncated during processing");



    # Check if null bytes are preserved

    if (!$matches) {

      my $orig_nulls = () = $null_data =~ /\x00/g;

      my $dec_nulls = () = $decrypted =~ /\x00/g;

      print "  Original null bytes: $orig_nulls\n";

      print "  Decrypted null bytes: $dec_nulls\n";

    }

  } else {

    print "  ❌ Decryption failed: " . ($result->{error} || "Unknown error") . "\n";

  }

} else {

  print "  ❌ Encryption failed: " . ($result->{error} || "Unknown error") . "\n";

}



print "\n";



# ====================================================================

# FAILED TEST 5: Unicode Round-trip (Most Critical)

# ====================================================================

print "=== Testing Unicode Round-trip (Critical Failure) ===\n";



my $unicode_text = "Unicode test: 世界 🌍 café naïve résumé Москва العربية";

print "Test 5: Unicode round-trip debugging...\n";

print "  Original Unicode: '$unicode_text'\n";

print "  UTF-8 bytes: " . join("", map { sprintf("\\x%02x", ord($_)) } split //, encode('UTF-8', $unicode_text)) . "\n";



# Try encryption

# Unicode must be UTF-8 encoded before encryption
my $utf8_encoded = encode('UTF-8', $unicode_text);

$result = $bridge->call_python('crypto', 'encrypt', {

  cipher_id => $test_cipher_id,

  plaintext_hex => unpack('H*', $utf8_encoded)

});



if ($result->{success}) {

  my $encrypted = $result->{result}->{encrypted};

  print "  ✅ Encryption successful: $encrypted\n";



  # Try decryption - this is where the "Empty response" error occurred

  print "  Attempting decryption...\n";

  $result = $bridge->call_python('crypto', 'decrypt', {

    cipher_id => $test_cipher_id,

    hex_ciphertext => $encrypted

  });



  print "  Decryption result: " . Dumper($result) . "\n";



  if ($result->{success}) {

    my $decrypted_hex = $result->{result}->{decrypted_hex};
    my $decrypted = pack('H*', $decrypted_hex);

    print "  ✅ Decryption successful: '$decrypted'\n";

    print "  Decrypted bytes: " . join("", map { sprintf("\\x%02x", ord($_)) } split //, $decrypted) . "\n";



    # Try different encoding approaches

    my $unicode_success = 0;



    # Decrypt returns raw bytes, must decode UTF-8 to get Unicode

    eval {

      my $decoded = decode('UTF-8', $decrypted);

      if ($decoded eq $unicode_text) {

        $unicode_success = 1;

        print "  ✅ UTF-8 decode successful - Unicode matches!\n";

      } else {

        print "  ❌ UTF-8 decode comparison failed\n";

        print "  Expected: '$unicode_text'\n";

        print "  Got: '$decoded'\n";

      }

    };

    if ($@) {

      print "  ❌ UTF-8 decode failed: $@\n";

    }



    run_test("Unicode round-trip", $unicode_success,

      "Unicode encoding/decoding mismatch");



  } else {

    print "  ❌ Decryption failed: " . ($result->{error} || "Unknown error") . "\n";

    print "  This is the 'Empty response' error from the main test!\n";

    run_test("Unicode round-trip", 0, "Decryption failed with: " . ($result->{error} || "Unknown error"));

  }

} else {

  print "  ❌ Encryption failed: " . ($result->{error} || "Unknown error") . "\n";

  run_test("Unicode round-trip", 0, "Encryption failed");

}



print "\n";



# ====================================================================

# ADDITIONAL DEBUGGING: UTF-8 Encoding Variations

# ====================================================================

print "=== Additional UTF-8 Encoding Tests ===\n";



# Test with pre-encoded UTF-8 bytes

my $utf8_bytes = encode('UTF-8', $unicode_text);

print "Test 5a: Pre-encoded UTF-8 bytes...\n";

print "  UTF-8 encoded length: " . length($utf8_bytes) . " bytes\n";



$result = $bridge->call_python('crypto', 'encrypt', {

  cipher_id => $test_cipher_id,

  plaintext_hex => unpack('H*', $utf8_bytes)

});



if ($result->{success}) {

  my $encrypted = $result->{result}->{encrypted};

  print "  ✅ UTF-8 bytes encryption successful\n";



  $result = $bridge->call_python('crypto', 'decrypt', {

    cipher_id => $test_cipher_id,

    hex_ciphertext => $encrypted

  });



  if ($result->{success}) {

    my $decrypted_hex = $result->{result}->{decrypted_hex};
    my $decrypted_bytes = pack('H*', $decrypted_hex);

    print "  ✅ UTF-8 bytes decryption successful\n";



    eval {

      my $decoded_unicode = decode('UTF-8', $decrypted_bytes);

      my $matches = ($decoded_unicode eq $unicode_text);

      run_test("Pre-encoded UTF-8 round-trip", $matches,

        "UTF-8 pre-encoding approach");

      if ($matches) {

        print "  ✅ This approach works! Unicode should be pre-encoded to UTF-8\n";

      }

    };

    if ($@) {

      print "  ❌ UTF-8 decode of result failed: $@\n";

    }

  } else {

    print "  ❌ UTF-8 bytes decryption failed: " . ($result->{error} || "Unknown error") . "\n";

  }

} else {

  print "  ❌ UTF-8 bytes encryption failed: " . ($result->{error} || "Unknown error") . "\n";

}



# ====================================================================

# CLEANUP

# ====================================================================

print "\n=== Cleanup ===\n";

$bridge->call_python('crypto', 'cleanup_cipher', {cipher_id => $test_cipher_id});

print "✅ Test cipher cleaned up\n";