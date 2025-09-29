# Rijndael Encryption Support Implementation Plan

## Overview
This document outlines the implementation plan to add explicit Rijndael encryption support to the crypto.py helper module. While AES is technically Rijndael, many legacy Perl applications specifically use "Rijndael" as the cipher name.

## Current State Analysis

### What We Have
- ✅ AES implementation (which is Rijndael with fixed parameters)
- ✅ Support for AES-128, AES-192, AES-256
- ✅ CBC mode implementation
- ✅ PKCS7 padding

### What's Missing
- ❌ "Rijndael" not recognized as valid cipher name
- ❌ No Rijndael-specific key size handling
- ❌ No Rijndael block size variations (original Rijndael supports 128, 160, 192, 224, 256-bit blocks)
- ❌ No documentation for Rijndael usage

## Implementation Strategy

### Phase 1: Basic Rijndael Support (Alias to AES)
**Goal:** Make "Rijndael" work as an alias to AES for compatibility

**Changes Required:**
1. **Update cipher validation** to accept "Rijndael"
2. **Add cipher name mapping** Rijndael → AES
3. **Update encryption/decryption routing** to handle Rijndael
4. **Maintain backward compatibility** with existing AES usage

### Phase 2: Enhanced Rijndael Features (Optional)
**Goal:** Add full Rijndael specification support if needed

**Potential Enhancements:**
1. **Variable block sizes** (128, 160, 192, 224, 256 bits)
2. **Rijndael-specific key derivation**
3. **Additional padding modes**
4. **Performance optimizations**

## Detailed Implementation Plan

### Step 1: Update Cipher Validation
**File:** `crypto.py` line 68

**Current Code:**
```python
if cipher not in ['Blowfish', 'AES', 'DES', '3DES']:
```

**Updated Code:**
```python
if cipher not in ['Blowfish', 'AES', 'Rijndael', 'DES', '3DES']:
```

### Step 2: Add Cipher Name Normalization
**Location:** After cipher validation, before cipher instance creation

**New Function:**
```python
def _normalize_cipher_name(cipher: str) -> str:
    """
    Normalize cipher names for internal use
    Maps legacy/alias names to standard implementations
    """
    cipher_mapping = {
        'Rijndael': 'AES',
        'rijndael': 'AES',
        'RIJNDAEL': 'AES'
    }
    return cipher_mapping.get(cipher, cipher)
```

### Step 3: Update Encryption/Decryption Routing
**Files:** Encryption and decryption functions

**Current Logic:**
```python
if config['cipher'] == 'Blowfish':
    return _encrypt_blowfish(key, data)
elif config['cipher'] == 'AES':
    return _encrypt_aes(key, data)
```

**Updated Logic:**
```python
normalized_cipher = _normalize_cipher_name(config['cipher'])
if normalized_cipher == 'Blowfish':
    return _encrypt_blowfish(key, data)
elif normalized_cipher == 'AES':  # Handles both AES and Rijndael
    return _encrypt_aes(key, data)
```

### Step 4: Add Rijndael-Specific Functions (Optional)
**Purpose:** Provide Rijndael-specific implementations if needed

**New Functions:**
```python
def _encrypt_rijndael(key: bytes, data: bytes) -> Dict[str, Any]:
    """
    Encrypt data using Rijndael (currently delegates to AES)
    Future: Could implement variable block sizes
    """
    return _encrypt_aes(key, data)

def _decrypt_rijndael(key: bytes, data: bytes) -> Dict[str, Any]:
    """
    Decrypt data using Rijndael (currently delegates to AES)
    Future: Could implement variable block sizes
    """
    return _decrypt_aes(key, data)
```

### Step 5: Update Key Size Handling
**Location:** `_process_key_for_algorithm()` function

**Current AES Handling:**
```python
elif cipher == 'AES':
    # AES requires 16, 24, or 32 bytes
    if len(key) not in [16, 24, 32]:
        if len(key) < 16:
            key = key.ljust(16, b'\0')
        elif len(key) < 24:
            key = key[:16]
        elif len(key) < 32:
            key = key[:24]
        else:
            key = key[:32]
```

**Add Rijndael Handling:**
```python
elif cipher in ['AES', 'Rijndael']:
    # AES/Rijndael requires 16, 24, or 32 bytes
    if len(key) not in [16, 24, 32]:
        if len(key) < 16:
            key = key.ljust(16, b'\0')
        elif len(key) < 24:
            key = key[:16]
        elif len(key) < 32:
            key = key[:24]
        else:
            key = key[:32]
```

### Step 6: Update Documentation and Comments
**Files:** Function docstrings and module header

**Updates Needed:**
1. **Module header** - mention Rijndael support
2. **Function docstrings** - update cipher parameter descriptions
3. **Example usage** - add Rijndael examples

## Implementation Code Changes

### 1. Update Module Header
```python
"""
crypto.py - Crypt::CBC replacement using Python cryptography

Provides CBC encryption functionality matching Crypt::CBC usage patterns.
Supports Blowfish, AES, Rijndael, DES, and 3DES algorithms with PEM key
processing and hex encoding.
"""
```

### 2. Add Cipher Normalization Function
```python
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
```

### 3. Update Validation Logic
```python
# Validate cipher algorithm
if cipher not in ['Blowfish', 'AES', 'Rijndael', 'DES', '3DES']:
    return {
        'success': False,
        'error': f'Unsupported cipher algorithm: {cipher}. Supported: Blowfish, AES, Rijndael, DES, 3DES'
    }

# Normalize cipher name for internal use
normalized_cipher = _normalize_cipher_name(cipher)
```

### 4. Update Encryption Routing
```python
# Encrypt using specified algorithm
normalized_cipher = _normalize_cipher_name(config['cipher'])
if normalized_cipher == 'Blowfish':
    result = _encrypt_blowfish(processed_key, plaintext.encode('utf-8'))
elif normalized_cipher == 'AES':  # Handles both AES and Rijndael
    result = _encrypt_aes(processed_key, plaintext.encode('utf-8'))
```

### 5. Update Decryption Routing
```python
# Decrypt using specified algorithm
normalized_cipher = _normalize_cipher_name(config['cipher'])
if normalized_cipher == 'Blowfish':
    result = _decrypt_blowfish(processed_key, ciphertext_bytes)
elif normalized_cipher == 'AES':  # Handles both AES and Rijndael
    result = _decrypt_aes(processed_key, ciphertext_bytes)
```

## Testing Strategy

### Unit Tests
1. **Basic Rijndael Encryption/Decryption**
   ```python
   def test_rijndael_basic():
       cipher = new(key="test_key_123456", cipher="Rijndael")
       # Test encryption and decryption
   ```

2. **Case Sensitivity Tests**
   ```python
   def test_rijndael_case_variations():
       # Test "Rijndael", "rijndael", "RIJNDAEL"
   ```

3. **AES/Rijndael Compatibility**
   ```python
   def test_aes_rijndael_compatibility():
       # Verify AES and Rijndael produce same results
   ```

### Integration Tests
1. **Existing AES tests continue to pass**
2. **Rijndael works in daemon mode**
3. **Cross-platform compatibility**

### Test Script Creation
Create `test_rijndael_crypto.pl`:
```perl
#!/usr/bin/perl
use strict;
use warnings;
use CPANBridge;

$CPANBridge::DAEMON_MODE = 1;
$CPANBridge::DEBUG_LEVEL = 1;

my $bridge = CPANBridge->new();

# Test Rijndael cipher
my $result = $bridge->call_python('crypto', 'new', {
    key => 'MyRijndaelKey123',
    cipher => 'Rijndael'
});

# Test encryption/decryption cycle
# Verify compatibility with AES
```

## Risk Assessment

### Low Risk Changes
- ✅ Adding "Rijndael" to validation list
- ✅ Adding cipher name normalization
- ✅ Updating routing logic

### Medium Risk Changes
- ⚠️ Key size handling modifications
- ⚠️ Function signature changes

### High Risk Changes
- 🔴 Implementing true Rijndael variable block sizes (Phase 2)
- 🔴 Changing existing AES behavior

## Rollback Plan

### If Issues Arise:
1. **Remove "Rijndael" from validation list**
2. **Remove normalization function calls**
3. **Revert to original encryption routing**
4. **Git revert to previous working state**

### Rollback Triggers:
- Existing AES functionality breaks
- Performance degradation > 10%
- Cross-platform compatibility issues
- Security vulnerabilities introduced

## Success Criteria

### Phase 1 Success Metrics:
- ✅ "Rijndael" accepted as valid cipher name
- ✅ Rijndael encryption/decryption works correctly
- ✅ AES and Rijndael produce identical results
- ✅ All existing crypto tests continue to pass
- ✅ Performance impact < 5%
- ✅ Works across Windows, MSYS, Unix platforms

### Phase 2 Success Metrics (Future):
- ✅ Variable block size Rijndael implementation
- ✅ Full Rijndael specification compliance
- ✅ Performance optimizations
- ✅ Extended test coverage

## Timeline Estimate

### Phase 1: Basic Rijndael Support
- **Implementation:** 2-3 hours
- **Testing:** 2-3 hours
- **Documentation:** 1 hour
- **Total:** 5-7 hours

### Phase 2: Enhanced Features (Optional)
- **Research:** 4-6 hours
- **Implementation:** 8-12 hours
- **Testing:** 4-6 hours
- **Total:** 16-24 hours

## Dependencies

### Required:
- Python cryptography library (already available)
- Existing crypto.py codebase
- CPANBridge framework

### Optional:
- Performance benchmarking tools
- Extended cryptographic test vectors
- Variable block size Rijndael implementation

## Next Steps

1. **Review and approve this implementation plan**
2. **Begin Phase 1 implementation**
3. **Create comprehensive test cases**
4. **Implement changes incrementally with testing**
5. **Document new Rijndael functionality**
6. **Update JIRA test stories to include Rijndael**

---

*Implementation Plan Version: 1.0*
*Created: 2025-09-25*
*Estimated Effort: 5-7 hours (Phase 1)*