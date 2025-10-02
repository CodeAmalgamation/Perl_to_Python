#!/usr/bin/perl
use strict;
use warnings;
use CPANBridge;
use Data::Dumper;

$CPANBridge::DAEMON_MODE = 1;

print "=== Debug Crypto Result Structure ===\n\n";

my $bridge = CPANBridge->new();

# Test crypto call and dump the exact structure
my $result = $bridge->call_python('crypto', 'new', {
    key => 'TestKey123',
    cipher => 'Blowfish'
});

print "Full result structure:\n";
print Dumper($result);

print "\nAnalyzing structure:\n";
print "result->{success}: " . ($result->{success} ? "true" : "false") . "\n";

if ($result->{success}) {
    print "result->{result} exists: " . (exists $result->{result} ? "yes" : "no") . "\n";

    if (exists $result->{result}) {
        print "result->{result}->{success}: " . ($result->{result}->{success} ? "true" : "false") . "\n";

        if (exists $result->{result}) {
            print "result->{result}->{result} exists: yes\n";
            print "cipher_id location: result->{result}->{result}->{cipher_id}\n";

            if (exists $result->{result}->{cipher_id}) {
                print "Cipher ID: " . $result->{result}->{cipher_id} . "\n";
            }
        }
    }
}