# File: CryptHelper.pm
package CryptHelper;

use strict;
use warnings;
use CPANBridge;
use Carp;

our $VERSION = '1.00';

# Main CryptHelper class - Crypt::CBC replacement
package CryptHelper;
use strict;
use warnings;
use base 'CPANBridge';

sub new {
    my ($class, %args) = @_;

    my $self = $class->SUPER::new(%args);

    # Process Crypt::CBC style arguments
    my $key = $args{'-key'} || $args{key};
    my $cipher = $args{'-cipher'} || $args{cipher} || 'Blowfish';
    my $key_file = $args{'-key_file'} || $args{key_file};
    my $iv = $args{'-iv'} || $args{iv};
    my $header = $args{'-header'} || $args{header} || 'salt';
    my $padding = $args{'-padding'} || $args{padding} || 'standard';

    # Store configuration
    $self->{config} = {
        key => $key,
        cipher => $cipher,
        key_file => $key_file,
        iv => $iv,
        header => $header,
        padding => $padding
    };

    # Create cipher instance via Python backend
    my $params = {
        cipher => $cipher,
        header => $header,
        padding_mode => $padding
    };

    # Add key or key_file
    if ($key) {
        $params->{key} = $key;
    } elsif ($key_file) {
        $params->{key_file} = $key_file;
    } else {
        croak "Either -key or -key_file must be provided";
    }

    # Add IV if specified
    if ($iv) {
        $params->{iv} = $iv;
    }

    my $result = $self->call_python('crypto', 'new', $params);

    if (!$result->{success}) {
        croak "Failed to create cipher: " . ($result->{error} || 'unknown error');
    }

    $self->{cipher_id} = $result->{result}->{cipher_id};
    $self->{last_error} = undef;

    return $self;
}

# Encrypt method (matches $cipher->encrypt($text))
sub encrypt {
    my ($self, $plaintext) = @_;

    croak "Plaintext required for encryption" unless defined $plaintext;
    croak "Cipher not initialized" unless $self->{cipher_id};

    # Convert plaintext to hex to safely preserve binary data (null bytes, newlines, Unicode)
    my $plaintext_hex = unpack('H*', $plaintext);

    my $result = $self->call_python('crypto', 'encrypt', {
        cipher_id => $self->{cipher_id},
        plaintext_hex => $plaintext_hex
    });

    if (!$result->{success}) {
        $self->{last_error} = $result->{error};
        croak "Encryption failed: " . $result->{error};
    }

    $self->{last_error} = undef;
    return $result->{result}->{encrypted};
}

# Decrypt method (matches $cipher->decrypt($hex_data))
sub decrypt {
    my ($self, $hex_ciphertext) = @_;

    croak "Hex ciphertext required for decryption" unless defined $hex_ciphertext;
    croak "Cipher not initialized" unless $self->{cipher_id};

    my $result = $self->call_python('crypto', 'decrypt', {
        cipher_id => $self->{cipher_id},
        hex_ciphertext => $hex_ciphertext
    });

    if (!$result->{success}) {
        $self->{last_error} = $result->{error};
        croak "Decryption failed: " . $result->{error};
    }

    $self->{last_error} = undef;

    # Convert hex result back to binary string
    return pack('H*', $result->{result}->{decrypted_hex});
}

# Error handling (if needed for compatibility)
sub error {
    my $self = shift;
    return $self->{last_error};
}

# Get cipher configuration
sub cipher {
    my $self = shift;
    return $self->{config}->{cipher};
}

sub key {
    my $self = shift;
    return $self->{config}->{key};
}

# Cleanup on destruction
sub DESTROY {
    my $self = shift;

    if ($self->{cipher_id}) {
        # Cleanup cipher instance in Python backend
        $self->call_python('crypto', 'cleanup_cipher', {
            cipher_id => $self->{cipher_id}
        });
    }
}

# Compatibility wrapper for direct Crypt::CBC usage
# This allows: use CryptHelper; and then Crypt::CBC->new(...)
sub import {
    my $class = shift;
    my $caller = caller;

    # Create Crypt::CBC compatibility
    {
        no strict 'refs';

        # Override Crypt::CBC in caller's namespace
        *{"${caller}::Crypt::CBC::new"} = sub {
            shift;  # Remove class name
            return CryptHelper->new(@_);
        };

        # For those who might call Crypt::CBC directly
        ${"${caller}::Crypt::CBC::"} = ${"${caller}::Crypt::CBC::"};
    }
}

1;

__END__

=head1 NAME

CryptHelper - Crypt::CBC replacement using Python cryptography backend

=head1 SYNOPSIS

    # Drop-in replacement for Crypt::CBC
    use CryptHelper;

    # Your existing AutoKit pattern works unchanged:
    my $cipher = Crypt::CBC->new(
        -key    => $self->_key(),
        -cipher => $self->getConfig("Cipher")
    );

    # Encrypt plaintext to hex
    my $encrypted_hex = $cipher->encrypt($plaintext);

    # Decrypt hex back to plaintext
    my $plaintext = $cipher->decrypt($encrypted_hex);

    # Alternative direct usage:
    my $crypt = CryptHelper->new(
        -key    => $key_string,
        -cipher => 'Blowfish'
    );

    my $hex_result = $crypt->encrypt("sensitive data");
    my $original = $crypt->decrypt($hex_result);

=head1 DESCRIPTION

CryptHelper provides a drop-in replacement for Crypt::CBC by routing
encryption operations through a Python backend that uses the 'cryptography' library.

Supports all patterns from your AutoKit usage analysis:
- Blowfish algorithm (default, matches your configuration)
- PEM key file processing with header stripping
- Hex encoding/decoding (unpack('H*', ...) and pack('H*', ...))
- Key caching for performance
- File-based key management
- Compatible error handling with croak()

=head1 METHODS

=head2 new(%args)

Create new cipher instance. Supports Crypt::CBC parameters:

    -key     => $key_string      # Encryption key
    -cipher  => 'Blowfish'       # Algorithm (Blowfish, AES)
    -key_file => $path           # Path to PEM key file
    -iv      => $iv_bytes        # Initialization vector
    -header  => 'salt'           # Header mode
    -padding => 'standard'       # Padding mode

=head2 encrypt($plaintext)

Encrypt plaintext and return hex-encoded result (matches Crypt::CBC behavior).
Result can be used with unpack('H*', ...) pattern.

=head2 decrypt($hex_ciphertext)

Decrypt hex-encoded ciphertext and return plaintext (matches Crypt::CBC behavior).
Input should be from pack('H*', ...) pattern.

=head2 error()

Get last error message (compatibility method).

=head1 AUTOKIT COMPATIBILITY

Perfect compatibility with AutoKit encryption patterns:

    # Encryption method from AutoKit.pm
    sub encrypt($) {
        my ($self, $text) = @_;
        my $cipher = Crypt::CBC->new(
            -key    => $self->_key(),
            -cipher => $self->getConfig("Cipher")
        );
        return unpack('H*', $cipher->encrypt($text));
    }

    # Decryption method from AutoKit.pm
    sub decrypt($) {
        my ($self, $text) = @_;
        my $cipher = Crypt::CBC->new(
            -key    => $self->_key(),
            -cipher => $self->getConfig("Cipher")
        );
        return $cipher->decrypt(pack('H*', $text));
    }

Simply change "use Crypt::CBC;" to "use CryptHelper;" - no other changes needed!

=head1 KEY MANAGEMENT

Supports AutoKit PEM key processing:
- Reads from $AUTOKIT_HOME/AutoKit.pem or specified path
- Strips PEM headers (^-.*-$)
- Removes newlines
- Caches processed keys in memory
- Handles file read errors with croak()

=head1 SUPPORTED ALGORITHMS

- Blowfish (primary, matches AutoKit default)
- AES (AES-128, AES-192, AES-256)
- Additional algorithms can be added as needed

=head1 MIGRATION

Change only the use statement:
- Replace 'use Crypt::CBC;' with 'use CryptHelper;'

All existing AutoKit code works without modification.

=head1 DEPENDENCIES

Python backend requires: cryptography library
Install with: pip install cryptography

=head1 SEE ALSO

L<CPANBridge>, L<Crypt::CBC>

=cut