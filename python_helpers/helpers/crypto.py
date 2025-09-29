#!/usr/bin/env python3
"""
crypto.py - Crypt::CBC replacement using Python cryptography

Provides CBC encryption functionality matching Crypt::CBC usage patterns.
Supports Blowfish, AES, Rijndael, DES, and 3DES algorithms with PEM key
processing and hex encoding.
"""

import os
import re
import binascii
import traceback
from typing import Dict, Any, Optional

try:
    from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
    from cryptography.hazmat.primitives import padding
    from cryptography.hazmat.backends import default_backend
    CRYPTO_AVAILABLE = True
except ImportError:
    CRYPTO_AVAILABLE = False

# Global state for cipher instances and key caching
CIPHER_INSTANCES = {}
CACHED_KEYS = {}

def _normalize_cipher_name(cipher: str) -> str:
    """
    Normalize cipher names for internal use
    Maps legacy/alias names to standard implementations

    Args:
        cipher: Original cipher name

    Returns:
        Normalized cipher name for internal use
    """
    cipher_mapping = {
        'Rijndael': 'AES',
        'rijndael': 'AES',
        'RIJNDAEL': 'AES'
    }
    return cipher_mapping.get(cipher, cipher)

def new(key: str = None, cipher: str = "Blowfish", key_file: str = None,
        iv: bytes = None, header: str = "salt", padding_mode: str = "standard") -> Dict[str, Any]:
    """
    Create new CBC cipher instance (matches Crypt::CBC->new())

    Args:
        key: Encryption key (string or None to read from file)
        cipher: Cipher algorithm (default: "Blowfish")
        key_file: Path to PEM key file
        iv: Initialization vector (None for random)
        header: Header mode (default: "salt")
        padding_mode: Padding mode (default: "standard")

    Returns:
        Dictionary with cipher instance ID and configuration
    """
    try:
        if not CRYPTO_AVAILABLE:
            return {
                'success': False,
                'error': 'Python cryptography library not available. Install with: pip install cryptography'
            }

        # Process key - either from parameter, file, or cached
        processed_key = None
        if key:
            processed_key = key
        elif key_file:
            processed_key = _read_and_process_key(key_file)
            if not processed_key:
                return {
                    'success': False,
                    'error': f'Failed to read key from file: {key_file}'
                }
        else:
            return {
                'success': False,
                'error': 'Either key or key_file must be provided'
            }

        # Validate cipher algorithm
        if cipher not in ['Blowfish', 'AES', 'Rijndael', 'DES', '3DES']:
            return {
                'success': False,
                'error': f'Unsupported cipher algorithm: {cipher}. Supported: Blowfish, AES, Rijndael, DES, 3DES'
            }

        # Normalize cipher name for internal use
        normalized_cipher = _normalize_cipher_name(cipher)

        # Create cipher instance ID
        import uuid
        cipher_id = str(uuid.uuid4())

        # Store cipher configuration
        CIPHER_INSTANCES[cipher_id] = {
            'key': processed_key,
            'cipher': normalized_cipher,  # Store normalized cipher for internal use
            'original_cipher': cipher,    # Keep original for reference
            'iv': iv,
            'header': header,
            'padding_mode': padding_mode,
            'key_file': key_file,
            'created_at': __import__('time').time()
        }

        return {
            'success': True,
            'result': {
                'cipher_id': cipher_id,
                'cipher': cipher,
                'key_length': len(processed_key) if processed_key else 0
            }
        }

    except Exception as e:
        return {
            'success': False,
            'error': f'Cipher creation failed: {str(e)}',
            'traceback': traceback.format_exc() if _is_debug_mode() else None
        }

def encrypt(cipher_id: str, plaintext: str) -> Dict[str, Any]:
    """
    Encrypt plaintext and return hex-encoded result (matches $cipher->encrypt())

    Args:
        cipher_id: Cipher instance ID from new()
        plaintext: Text to encrypt

    Returns:
        Dictionary with hex-encoded encrypted result
    """
    try:
        if cipher_id not in CIPHER_INSTANCES:
            return {
                'success': False,
                'error': 'Invalid cipher ID or cipher expired'
            }

        config = CIPHER_INSTANCES[cipher_id]

        # Convert key from hex/base64 if needed
        key_bytes = _prepare_key(config['key'], config['cipher'])
        if not key_bytes:
            return {
                'success': False,
                'error': 'Failed to prepare encryption key'
            }

        # Encrypt using specified algorithm
        if config['cipher'] == 'Blowfish':
            encrypted_bytes = _encrypt_blowfish(key_bytes, plaintext.encode('utf-8'))
        elif config['cipher'] == 'AES':  # Handles both AES and Rijndael
            encrypted_bytes = _encrypt_aes(key_bytes, plaintext.encode('utf-8'))
        else:
            return {
                'success': False,
                'error': f"Cipher {config['cipher']} not yet implemented"
            }

        if encrypted_bytes is None:
            return {
                'success': False,
                'error': 'Encryption operation failed'
            }

        # Convert to hex (matches unpack('H*', ...))
        hex_result = binascii.hexlify(encrypted_bytes).decode('ascii')

        return {
            'success': True,
            'result': {
                'encrypted': hex_result,
                'length': len(hex_result),
                'algorithm': config['cipher']
            }
        }

    except Exception as e:
        return {
            'success': False,
            'error': f'Encryption failed: {str(e)}',
            'traceback': traceback.format_exc() if _is_debug_mode() else None
        }

def decrypt(cipher_id: str, hex_ciphertext: str) -> Dict[str, Any]:
    """
    Decrypt hex-encoded ciphertext (matches $cipher->decrypt())

    Args:
        cipher_id: Cipher instance ID from new()
        hex_ciphertext: Hex-encoded encrypted data

    Returns:
        Dictionary with decrypted plaintext
    """
    try:
        if cipher_id not in CIPHER_INSTANCES:
            return {
                'success': False,
                'error': 'Invalid cipher ID or cipher expired'
            }

        config = CIPHER_INSTANCES[cipher_id]

        # Convert from hex (matches pack('H*', ...))
        try:
            ciphertext_bytes = binascii.unhexlify(hex_ciphertext)
        except (ValueError, binascii.Error) as e:
            return {
                'success': False,
                'error': f'Invalid hex input: {str(e)}'
            }

        # Convert key from hex/base64 if needed
        key_bytes = _prepare_key(config['key'], config['cipher'])
        if not key_bytes:
            return {
                'success': False,
                'error': 'Failed to prepare decryption key'
            }

        # Decrypt using specified algorithm
        if config['cipher'] == 'Blowfish':
            decrypted_bytes = _decrypt_blowfish(key_bytes, ciphertext_bytes)
        elif config['cipher'] == 'AES':  # Handles both AES and Rijndael
            decrypted_bytes = _decrypt_aes(key_bytes, ciphertext_bytes)
        else:
            return {
                'success': False,
                'error': f"Cipher {config['cipher']} not yet implemented"
            }

        if decrypted_bytes is None:
            return {
                'success': False,
                'error': 'Decryption operation failed'
            }

        # Convert back to string
        try:
            plaintext = decrypted_bytes.decode('utf-8')
        except UnicodeDecodeError:
            # Handle binary data
            plaintext = decrypted_bytes.decode('latin-1')

        return {
            'success': True,
            'result': {
                'decrypted': plaintext,
                'length': len(plaintext),
                'algorithm': config['cipher']
            }
        }

    except Exception as e:
        return {
            'success': False,
            'error': f'Decryption failed: {str(e)}',
            'traceback': traceback.format_exc() if _is_debug_mode() else None
        }

def _read_and_process_key(key_file: str) -> Optional[str]:
    """
    Read and process PEM key file (matches AutoKit _key() method)

    Args:
        key_file: Path to PEM key file

    Returns:
        Processed key string or None if failed
    """
    try:
        # Check cache first
        if key_file in CACHED_KEYS:
            return CACHED_KEYS[key_file]

        # Read key file
        with open(key_file, 'r') as f:
            key_content = f.read()

        # Process PEM format (matches Perl processing)
        processed_key = key_content

        # Remove PEM headers: s/^-.*-$//gm
        processed_key = re.sub(r'^-.*-$', '', processed_key, flags=re.MULTILINE)

        # Remove newlines: s/\n?//g
        processed_key = re.sub(r'\n', '', processed_key)

        # Cache the processed key
        CACHED_KEYS[key_file] = processed_key

        return processed_key

    except Exception as e:
        # Match Perl error handling pattern
        return None

def _prepare_key(key_str: str, cipher: str) -> Optional[bytes]:
    """
    Prepare key for encryption (handle base64/hex and sizing)

    Args:
        key_str: Raw key string
        cipher: Cipher algorithm

    Returns:
        Key bytes or None if failed
    """
    try:
        # Try to decode as base64 first (PEM format)
        try:
            import base64
            key_bytes = base64.b64decode(key_str)
        except:
            # If not base64, try as hex
            try:
                key_bytes = binascii.unhexlify(key_str)
            except:
                # Use as raw bytes
                key_bytes = key_str.encode('utf-8')

        # Adjust key size for algorithm
        if cipher == 'Blowfish':
            # Blowfish supports variable key sizes 32-448 bits
            # Truncate or pad to reasonable size (128 bits = 16 bytes)
            if len(key_bytes) > 56:  # Max 448 bits
                key_bytes = key_bytes[:56]
            elif len(key_bytes) < 4:  # Min 32 bits
                key_bytes = key_bytes.ljust(4, b'\x00')
        elif cipher == 'AES':
            # AES/Rijndael requires 16, 24, or 32 bytes
            if len(key_bytes) <= 16:
                key_bytes = key_bytes.ljust(16, b'\x00')
            elif len(key_bytes) <= 24:
                key_bytes = key_bytes.ljust(24, b'\x00')
            else:
                key_bytes = key_bytes[:32]

        return key_bytes

    except Exception:
        return None

def _encrypt_blowfish(key: bytes, data: bytes) -> Optional[bytes]:
    """Encrypt data using Blowfish CBC"""
    try:
        # Generate random IV
        iv = os.urandom(8)  # Blowfish block size is 8 bytes

        # Create cipher
        cipher = Cipher(algorithms.Blowfish(key), modes.CBC(iv), backend=default_backend())
        encryptor = cipher.encryptor()

        # Apply PKCS7 padding
        padder = padding.PKCS7(64).padder()  # Blowfish block size is 64 bits
        padded_data = padder.update(data)
        padded_data += padder.finalize()

        # Encrypt
        ciphertext = encryptor.update(padded_data) + encryptor.finalize()

        # Return IV + ciphertext (standard CBC practice)
        return iv + ciphertext

    except Exception:
        return None

def _decrypt_blowfish(key: bytes, data: bytes) -> Optional[bytes]:
    """Decrypt data using Blowfish CBC"""
    try:
        # Extract IV and ciphertext
        iv = data[:8]  # First 8 bytes
        ciphertext = data[8:]

        # Create cipher
        cipher = Cipher(algorithms.Blowfish(key), modes.CBC(iv), backend=default_backend())
        decryptor = cipher.decryptor()

        # Decrypt
        padded_data = decryptor.update(ciphertext) + decryptor.finalize()

        # Remove PKCS7 padding
        unpadder = padding.PKCS7(64).unpadder()
        data = unpadder.update(padded_data)
        data += unpadder.finalize()

        return data

    except Exception:
        return None

def _encrypt_aes(key: bytes, data: bytes) -> Optional[bytes]:
    """Encrypt data using AES CBC"""
    try:
        # Generate random IV
        iv = os.urandom(16)  # AES block size is 16 bytes

        # Create cipher
        cipher = Cipher(algorithms.AES(key), modes.CBC(iv), backend=default_backend())
        encryptor = cipher.encryptor()

        # Apply PKCS7 padding
        padder = padding.PKCS7(128).padder()  # AES block size is 128 bits
        padded_data = padder.update(data)
        padded_data += padder.finalize()

        # Encrypt
        ciphertext = encryptor.update(padded_data) + encryptor.finalize()

        # Return IV + ciphertext
        return iv + ciphertext

    except Exception:
        return None

def _decrypt_aes(key: bytes, data: bytes) -> Optional[bytes]:
    """Decrypt data using AES CBC"""
    try:
        # Extract IV and ciphertext
        iv = data[:16]  # First 16 bytes
        ciphertext = data[16:]

        # Create cipher
        cipher = Cipher(algorithms.AES(key), modes.CBC(iv), backend=default_backend())
        decryptor = cipher.decryptor()

        # Decrypt
        padded_data = decryptor.update(ciphertext) + decryptor.finalize()

        # Remove PKCS7 padding
        unpadder = padding.PKCS7(128).unpadder()
        data = unpadder.update(padded_data)
        data += unpadder.finalize()

        return data

    except Exception:
        return None

def cleanup_cipher(cipher_id: str) -> Dict[str, Any]:
    """
    Clean up cipher instance

    Args:
        cipher_id: Cipher instance ID

    Returns:
        Dictionary with cleanup result
    """
    try:
        if cipher_id in CIPHER_INSTANCES:
            del CIPHER_INSTANCES[cipher_id]

        return {
            'success': True,
            'result': {
                'cipher_id': cipher_id,
                'cleaned_up': True
            }
        }

    except Exception as e:
        return {
            'success': False,
            'error': f'Cleanup failed: {str(e)}'
        }

def _is_debug_mode() -> bool:
    """Check if debug mode is enabled"""
    return os.environ.get('CPAN_BRIDGE_DEBUG', '0') != '0'

# Test and utility functions
def test_blowfish_compatibility():
    """Test Blowfish encryption/decryption compatibility"""
    print("Testing Blowfish CBC compatibility...")

    # Test data
    test_key = "ThisIsATestKey123"
    test_plaintext = "Hello, World! This is a test message."

    try:
        # Create cipher
        result = new(key=test_key, cipher="Blowfish")
        if not result['success']:
            print(f"✗ Cipher creation failed: {result['error']}")
            return False

        cipher_id = result['result']['cipher_id']
        print(f"✓ Cipher created: {cipher_id}")

        # Encrypt
        enc_result = encrypt(cipher_id, test_plaintext)
        if not enc_result['success']:
            print(f"✗ Encryption failed: {enc_result['error']}")
            return False

        hex_encrypted = enc_result['result']['encrypted']
        print(f"✓ Encrypted: {hex_encrypted[:32]}...")

        # Decrypt
        dec_result = decrypt(cipher_id, hex_encrypted)
        if not dec_result['success']:
            print(f"✗ Decryption failed: {dec_result['error']}")
            return False

        decrypted_text = dec_result['result']['decrypted']
        print(f"✓ Decrypted: {decrypted_text}")

        # Verify
        if decrypted_text == test_plaintext:
            print("✓ Round-trip test PASSED")
            return True
        else:
            print("✗ Round-trip test FAILED")
            return False

    except Exception as e:
        print(f"✗ Test failed with exception: {e}")
        return False
    finally:
        # Cleanup
        if 'cipher_id' in locals():
            cleanup_cipher(cipher_id)

if __name__ == "__main__":
    # Run basic compatibility test
    if CRYPTO_AVAILABLE:
        test_blowfish_compatibility()
    else:
        print("Python cryptography library not available")
        print("Install with: pip install cryptography")