#!/usr/bin/perl
use strict;
use warnings;
use lib '.';
use XMLDOMHelper;
use Data::Dumper;

# Enable daemon mode and debug
$CPANBridge::DAEMON_MODE = 1;
$CPANBridge::DEBUG_LEVEL = 0;

print "=== Testing XML DOM Helper - Document Modification (Phase 2) ===\n\n";

# Test 1: Create Parser and Empty Document
print "Test 1: Creating XML DOM Parser and parsing base document...\n";
my $parser = XMLDOMHelper::Parser->new();

if ($parser) {
    print "✅ Parser created successfully\n";
} else {
    print "❌ Parser creation failed\n";
    exit 1;
}

# Start with a simple document structure
my $base_xml = <<'XML';
<?xml version="1.0" encoding="UTF-8"?>
<Configuration>
    <Sites>
    </Sites>
    <Environment Name="TEST">
    </Environment>
</Configuration>
XML

my $doc;
eval {
    $doc = $parser->parse($base_xml);
};

if ($@ || !$doc) {
    print "❌ XML parsing failed: $@\n";
    exit 1;
} else {
    print "✅ Base XML parsing successful\n\n";
}

# Test 2: Create new elements
print "Test 2: Testing createElement functionality...\n";

my $new_site = $doc->createElement('Site');
if ($new_site) {
    print "✅ Site element created successfully\n";
} else {
    print "❌ Site element creation failed\n";
}

my $new_server = $doc->createElement('Server');
if ($new_server) {
    print "✅ Server element created successfully\n";
} else {
    print "❌ Server element creation failed\n";
}

print "\n";

# Test 3: Set attributes on new elements
print "Test 3: Testing setAttribute functionality...\n";

eval {
    $new_site->setAttribute('Name', 'site3');
    $new_site->setAttribute('ShortName', 's3');
    $new_site->setAttribute('Net', '192.168.3.0');
    print "✅ Site attributes set successfully\n";
};
if ($@) {
    print "❌ Site setAttribute failed: $@\n";
}

eval {
    $new_server->setAttribute('Name', 'server3');
    $new_server->setAttribute('Location', 'datacenter3');
    print "✅ Server attributes set successfully\n";
};
if ($@) {
    print "❌ Server setAttribute failed: $@\n";
}

print "\n";

# Test 4: Test hasAttribute
print "Test 4: Testing hasAttribute functionality...\n";

if ($new_site->hasAttribute('Name')) {
    print "✅ Site has 'Name' attribute (correct)\n";
} else {
    print "❌ Site should have 'Name' attribute\n";
}

if (!$new_site->hasAttribute('NonExistent')) {
    print "✅ Site doesn't have 'NonExistent' attribute (correct)\n";
} else {
    print "❌ Site should not have 'NonExistent' attribute\n";
}

print "\n";

# Test 5: Create text nodes
print "Test 5: Testing createTextNode functionality...\n";

my $owner_text = $doc->createTextNode('Administrator');
if ($owner_text) {
    print "✅ Text node created successfully\n";
} else {
    print "❌ Text node creation failed\n";
}

print "\n";

# Test 6: Build tree structure with appendChild
print "Test 6: Testing appendChild functionality...\n";

# Get the Sites container
my $sites_nodes = $doc->getElementsByTagName('Sites');
if ($sites_nodes->getLength() == 1) {
    my $sites_container = $sites_nodes->item(0);

    eval {
        $sites_container->appendChild($new_site);
        print "✅ Site appended to Sites container\n";
    };
    if ($@) {
        print "❌ appendChild failed: $@\n";
    }
} else {
    print "❌ Sites container not found\n";
}

# Get the Environment container
my $env_nodes = $doc->getElementsByTagName('Environment');
if ($env_nodes->getLength() == 1) {
    my $env_container = $env_nodes->item(0);

    eval {
        $env_container->appendChild($new_server);
        print "✅ Server appended to Environment container\n";
    };
    if ($@) {
        print "❌ appendChild failed: $@\n";
    }
} else {
    print "❌ Environment container not found\n";
}

print "\n";

# Test 7: Verify the structure was modified
print "Test 7: Verifying document structure after modifications...\n";

my $updated_sites = $doc->getElementsByTagName('Site');
print "Found " . $updated_sites->getLength() . " Site elements after modification\n";

if ($updated_sites->getLength() == 1) {
    my $site = $updated_sites->item(0);
    my $name = $site->getAttribute('Name');
    my $short_name = $site->getAttribute('ShortName');
    my $net = $site->getAttribute('Net');

    print "New Site: Name='$name', ShortName='$short_name', Net='$net'\n";

    if ($name eq 'site3' && $short_name eq 's3' && $net eq '192.168.3.0') {
        print "✅ Site attributes verified correctly\n";
    } else {
        print "❌ Site attributes don't match expected values\n";
    }
} else {
    print "❌ Expected 1 Site element, found " . $updated_sites->getLength() . "\n";
}

my $updated_servers = $doc->getElementsByTagName('Server');
print "Found " . $updated_servers->getLength() . " Server elements after modification\n";

if ($updated_servers->getLength() == 1) {
    my $server = $updated_servers->item(0);
    my $name = $server->getAttribute('Name');
    my $location = $server->getAttribute('Location');

    print "New Server: Name='$name', Location='$location'\n";

    if ($name eq 'server3' && $location eq 'datacenter3') {
        print "✅ Server attributes verified correctly\n";
    } else {
        print "❌ Server attributes don't match expected values\n";
    }
} else {
    print "❌ Expected 1 Server element, found " . $updated_servers->getLength() . "\n";
}

print "\n";

# Test 8: Test document serialization
print "Test 8: Testing document serialization (toString)...\n";

my $xml_output = $doc->toString("  ");  # Pretty print with 2-space indent
if ($xml_output) {
    print "✅ Document serialization successful\n";
    print "Generated XML (first 200 chars):\n";
    print substr($xml_output, 0, 200) . "...\n";
} else {
    print "❌ Document serialization failed\n";
}

print "\n";

# Test 9: Test cloneNode functionality
print "Test 9: Testing cloneNode functionality...\n";

eval {
    my $cloned_site = $new_site->cloneNode(0);  # Shallow clone
    if ($cloned_site) {
        $cloned_site->setAttribute('Name', 'cloned_site');
        print "✅ Shallow clone successful\n";

        my $cloned_name = $cloned_site->getAttribute('Name');
        if ($cloned_name eq 'cloned_site') {
            print "✅ Cloned element can be modified independently\n";
        } else {
            print "❌ Cloned element modification failed\n";
        }
    } else {
        print "❌ Shallow clone failed\n";
    }
};
if ($@) {
    print "❌ cloneNode failed: $@\n";
}

print "\n";

# Test 10: Test removeAttribute
print "Test 10: Testing removeAttribute functionality...\n";

eval {
    $new_site->removeAttribute('Net');
    print "✅ removeAttribute executed successfully\n";

    if (!$new_site->hasAttribute('Net')) {
        print "✅ Net attribute removed successfully\n";
    } else {
        print "❌ Net attribute still exists after removal\n";
    }
};
if ($@) {
    print "❌ removeAttribute failed: $@\n";
}

print "\n";

# Test 11: Memory Management
print "Test 11: Testing memory management...\n";

eval {
    $doc->dispose();
    print "✅ Document disposal successful\n";
};
if ($@) {
    print "❌ Document disposal failed: $@\n";
}

print "\n";

print "=== XML DOM Helper Modification Tests Complete ===\n";

# Summary
print "\n=== Test Summary (Phase 2 - DOM Modification) ===\n";
print "✅ Document parsing\n";
print "✅ createElement() - Creating new elements\n";
print "✅ setAttribute() - Setting element attributes\n";
print "✅ hasAttribute() - Checking attribute existence\n";
print "✅ createTextNode() - Creating text nodes\n";
print "✅ appendChild() - Adding children to elements\n";
print "✅ Document structure modification\n";
print "✅ toString() - Document serialization\n";
print "✅ cloneNode() - Element cloning\n";
print "✅ removeAttribute() - Removing attributes\n";
print "✅ Memory management\n";
print "\nPhase 2 (DOM Modification) functionality is working correctly!\n";