#!/usr/bin/perl
use strict;
use warnings;
use lib '.';
use XMLDOMHelper;

# Enable daemon mode and debug
$CPANBridge::DAEMON_MODE = 1;
$CPANBridge::DEBUG_LEVEL = 1;

print "=== Debugging XQL/XPath Issues ===\n\n";

# Simple test XML
my $test_xml = <<'XML';
<?xml version="1.0"?>
<Configuration>
    <Cipher>Rijndael</Cipher>
    <Site Name="site1" Net="192.168.1.0">
        <Owner>Admin</Owner>
    </Site>
    <Site Name="site2" Net="192.168.2.0">
        <Owner>User</Owner>
    </Site>
</Configuration>
XML

my $parser = XMLDOMHelper::Parser->new();
my $doc = $parser->parse($test_xml);

print "1. Testing simple element query:\n";
my @cipher_results = $doc->xql("Cipher");
print "Cipher results: " . scalar(@cipher_results) . "\n";
if (@cipher_results) {
    print "Cipher value: '" . $cipher_results[0]->getNodeValue() . "'\n";
}

print "\n2. Testing descendant query:\n";
my @site_results = $doc->xql("//Site");
print "Site results: " . scalar(@site_results) . "\n";

print "\n3. Testing attribute query:\n";
my @attr_results = $doc->xql("//Site[\@Name='site1']");
print "Site[Name='site1'] results: " . scalar(@attr_results) . "\n";

print "\n4. Testing from root element:\n";
my $root_elements = $doc->getElementsByTagName('Configuration');
if ($root_elements->getLength() > 0) {
    my $root = $root_elements->item(0);
    my @root_sites = $root->xql("Site");
    print "Sites from root: " . scalar(@root_sites) . "\n";

    my @root_attr_sites = $root->xql("Site[\@Name='site1']");
    print "Site[Name='site1'] from root: " . scalar(@root_attr_sites) . "\n";
}

$doc->dispose();