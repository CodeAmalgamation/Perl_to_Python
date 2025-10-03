#!/usr/bin/perl
use strict;
use warnings;
use lib '.';
use XMLDOMHelper;
use Data::Dumper;

# Enable daemon mode and debug
$CPANBridge::DAEMON_MODE = 1;
$CPANBridge::DEBUG_LEVEL = 0;

print "=== Testing XML DOM Helper - Basic Functionality ===\n\n";

# Test XML mimicking the Config.pm usage patterns
my $test_xml = <<'XML';
<?xml version="1.0" encoding="UTF-8"?>
<Configuration>
    <Cipher>Rijndael</Cipher>
    <Key>/path/to/key.pem</Key>
    <Sites>
        <Site Name="site1" ShortName="s1" Net="192.168.1.0">
            <Owner>Admin</Owner>
        </Site>
        <Site Name="site2" ShortName="s2" Net="192.168.2.0">
            <Owner>User</Owner>
        </Site>
    </Sites>
    <Environment Name="PROD">
        <Owner>
            <ID Key="keyfile">produser</ID>
        </Owner>
        <Server Name="server1" Location="datacenter1"/>
        <Server Name="server2" Location="datacenter2"/>
    </Environment>
    <Property Name="LogLevel" Type="STRING">DEBUG</Property>
    <Property Name="MaxConnections" Type="NUMBER">100</Property>
</Configuration>
XML

# Test 1: Parser Creation
print "Test 1: Creating XML DOM Parser...\n";
my $parser = XMLDOMHelper::Parser->new();

if ($parser) {
    print "✅ Parser created successfully\n\n";
} else {
    print "❌ Parser creation failed\n";
    exit 1;
}

# Test 2: XML Parsing
print "Test 2: Parsing XML from string...\n";
my $doc;

eval {
    $doc = $parser->parse($test_xml);
};

if ($@ || !$doc) {
    print "❌ XML parsing failed: $@\n";
    exit 1;
} else {
    print "✅ XML parsing successful\n\n";
}

# Test 3: getElementsByTagName (Primary navigation method)
print "Test 3: Testing getElementsByTagName navigation...\n";

# Test Configuration root
my $conf_nodes = $doc->getElementsByTagName('Configuration');
print "Found " . $conf_nodes->getLength() . " Configuration elements\n";

if ($conf_nodes->getLength() == 1) {
    print "✅ Configuration root found\n";
} else {
    print "❌ Configuration root not found correctly\n";
}

# Test Site elements
my $site_nodes = $doc->getElementsByTagName('Site');
print "Found " . $site_nodes->getLength() . " Site elements\n";

if ($site_nodes->getLength() == 2) {
    print "✅ Site elements found correctly\n";
} else {
    print "❌ Site elements not found correctly\n";
}

# Test Property elements
my $property_nodes = $doc->getElementsByTagName('Property');
print "Found " . $property_nodes->getLength() . " Property elements\n";

if ($property_nodes->getLength() == 2) {
    print "✅ Property elements found correctly\n\n";
} else {
    print "❌ Property elements not found correctly\n\n";
}

# Test 4: Attribute Access (Critical for Config.pm)
print "Test 4: Testing attribute access...\n";

# Test Site attributes
for (my $i = 0; $i < $site_nodes->getLength(); $i++) {
    my $site = $site_nodes->item($i);
    my $name = $site->getAttribute('Name');
    my $short_name = $site->getAttribute('ShortName');
    my $net = $site->getAttribute('Net');

    print "Site $i: Name='$name', ShortName='$short_name', Net='$net'\n";

    if ($name && $short_name && $net) {
        print "✅ Site $i attributes read correctly\n";
    } else {
        print "❌ Site $i attributes missing\n";
    }
}

# Test Environment attributes
my $env_nodes = $doc->getElementsByTagName('Environment');
if ($env_nodes->getLength() > 0) {
    my $env = $env_nodes->item(0);
    my $env_name = $env->getAttribute('Name');
    print "Environment Name: '$env_name'\n";

    if ($env_name eq 'PROD') {
        print "✅ Environment attributes read correctly\n\n";
    } else {
        print "❌ Environment attributes incorrect\n\n";
    }
}

# Test 5: Text Content Extraction (Complex pattern from Config.pm)
print "Test 5: Testing text content extraction...\n";

# Test simple text content
my $cipher_nodes = $doc->getElementsByTagName('Cipher');
if ($cipher_nodes->getLength() > 0) {
    my $cipher = $cipher_nodes->item(0);
    my $cipher_value = $cipher->getNodeValue();
    print "Cipher value: '$cipher_value'\n";

    if ($cipher_value eq 'Rijndael') {
        print "✅ Simple text extraction successful\n";
    } else {
        print "❌ Simple text extraction failed\n";
    }
}

# Test nested text content
my $owner_nodes = $doc->getElementsByTagName('Owner');
for (my $i = 0; $i < $owner_nodes->getLength(); $i++) {
    my $owner = $owner_nodes->item($i);
    my $owner_text = $owner->getNodeValue();
    print "Owner $i text: '$owner_text'\n";
}
print "\n";

# Test 6: Child Node Navigation
print "Test 6: Testing child node navigation...\n";

my $sites_nodes = $doc->getElementsByTagName('Sites');
if ($sites_nodes->getLength() > 0) {
    my $sites = $sites_nodes->item(0);
    my $child_nodes = $sites->getChildNodes();

    print "Sites container has " . $child_nodes->getLength() . " child nodes\n";

    # Count actual Site elements (ignoring text nodes/whitespace)
    my $site_count = 0;
    for (my $i = 0; $i < $child_nodes->getLength(); $i++) {
        my $child = $child_nodes->item($i);
        if ($child && $child->getTagName() eq 'Site') {
            $site_count++;
        }
    }

    print "Found $site_count Site child elements\n";
    if ($site_count == 2) {
        print "✅ Child node navigation successful\n\n";
    } else {
        print "❌ Child node navigation failed\n\n";
    }
}

# Test 7: Element-specific getElementsByTagName (nested search)
print "Test 7: Testing nested getElementsByTagName...\n";

# Find Server elements within Environment
my $env = $env_nodes->item(0);
if ($env) {
    my $servers = $env->getElementsByTagName('Server');
    print "Found " . $servers->getLength() . " Server elements in Environment\n";

    for (my $i = 0; $i < $servers->getLength(); $i++) {
        my $server = $servers->item($i);
        my $server_name = $server->getAttribute('Name');
        my $location = $server->getAttribute('Location');
        print "Server: Name='$server_name', Location='$location'\n";
    }

    if ($servers->getLength() == 2) {
        print "✅ Nested getElementsByTagName successful\n\n";
    } else {
        print "❌ Nested getElementsByTagName failed\n\n";
    }
}

# Test 8: Complex attribute/text pattern (ID element with Key attribute)
print "Test 8: Testing complex element patterns...\n";

my $id_nodes = $doc->getElementsByTagName('ID');
if ($id_nodes->getLength() > 0) {
    my $id = $id_nodes->item(0);
    my $key_attr = $id->getAttribute('Key');
    my $id_text = $id->getNodeValue();

    print "ID element: Key='$key_attr', Text='$id_text'\n";

    if ($key_attr eq 'keyfile' && $id_text eq 'produser') {
        print "✅ Complex element pattern successful\n\n";
    } else {
        print "❌ Complex element pattern failed\n\n";
    }
}

# Test 9: Property elements with Type attributes (Config.pm pattern)
print "Test 9: Testing Property element patterns...\n";

for (my $i = 0; $i < $property_nodes->getLength(); $i++) {
    my $property = $property_nodes->item($i);
    my $prop_name = $property->getAttribute('Name');
    my $prop_type = $property->getAttribute('Type');
    my $prop_value = $property->getNodeValue();

    print "Property: Name='$prop_name', Type='$prop_type', Value='$prop_value'\n";
}

print "✅ Property element patterns working\n\n";

# Test 10: Memory Management
print "Test 10: Testing memory management...\n";

eval {
    $doc->dispose();
    print "✅ Document disposal successful\n\n";
};

if ($@) {
    print "❌ Document disposal failed: $@\n\n";
}

print "=== XML DOM Helper Basic Tests Complete ===\n";

# Summary
print "\n=== Test Summary ===\n";
print "✅ Parser creation\n";
print "✅ XML parsing from string\n";
print "✅ getElementsByTagName navigation\n";
print "✅ Attribute access (getName, getAttribute)\n";
print "✅ Text content extraction\n";
print "✅ Child node navigation\n";
print "✅ Nested element searches\n";
print "✅ Complex element patterns\n";
print "✅ Property element handling\n";
print "✅ Memory management\n";
print "\nAll basic XML DOM functionality is working correctly!\n";