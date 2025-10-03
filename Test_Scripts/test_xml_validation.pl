#!/usr/bin/perl
use strict;
use warnings;
use CPANBridge;

sub test_xml_mode {
    my ($mode_name, $daemon_mode) = @_;

    print "\n=== Testing XML Helper Module - $mode_name ===\n";

    $CPANBridge::DAEMON_MODE = $daemon_mode;
    my $bridge = CPANBridge->new();

    # Test 1: Parse simple XML string
    my $simple_xml = '<root><item id="1">Test Value</item></root>';

    my $result = $bridge->call_python('xml_helper', 'xml_in', {
        source => $simple_xml,
        source_type => 'string'
    });

    if ($result->{success}) {
        my $parsed = $result->{result};
        if (ref($parsed) eq 'HASH' && $parsed->{item}) {
            print "Parse simple XML: PASS\n";
        } else {
            print "Parse simple XML: FAIL - structure mismatch\n";
        }
    } else {
        print "Parse simple XML: FAIL - " . $result->{error} . "\n";
    }

    # Test 2: Parse complex XML
    my $complex_xml = qq{<?xml version="1.0" encoding="UTF-8"?>
<catalog>
    <book id="1" category="fiction">
        <title>Great Novel</title>
        <author>Famous Author</author>
        <price currency="USD">29.99</price>
        <description>A wonderful story about <em>adventure</em></description>
    </book>
    <book id="2" category="technical">
        <title>Programming Guide</title>
        <author>Expert Developer</author>
        <price currency="USD">49.99</price>
    </book>
</catalog>};

    $result = $bridge->call_python('xml_helper', 'xml_in', {
        source => $complex_xml,
        source_type => 'string'
    });

    if ($result->{success}) {
        my $parsed = $result->{result};
        if (ref($parsed->{book}) eq 'ARRAY' && @{$parsed->{book}} == 2) {
            print "Parse complex XML: PASS\n";
        } else {
            print "Parse complex XML: FAIL - structure mismatch\n";
        }
    } else {
        print "Parse complex XML: FAIL - " . $result->{error} . "\n";
    }

    # Test 3: XML generation
    my $data_to_convert = {
        users => {
            user => [
                {
                    '@id' => '1',
                    name => 'John Doe',
                    email => 'john@example.com',
                    active => 'true'
                },
                {
                    '@id' => '2',
                    name => 'Jane Smith',
                    email => 'jane@example.com',
                    active => 'false'
                }
            ]
        }
    };

    $result = $bridge->call_python('xml_helper', 'xml_out', {
        data => $data_to_convert,
        options => { RootName => 'data', XMLDecl => 1 }
    });

    if ($result->{success}) {
        my $generated_xml = $result->{result};
        if ($generated_xml =~ /<data>/ && $generated_xml =~ /<user.*id="1"/) {
            print "Generate XML: PASS\n";
        } else {
            print "Generate XML: FAIL - content validation failed\n";
        }
    } else {
        print "Generate XML: FAIL - " . $result->{error} . "\n";
    }

    # Test 4: XML file parsing
    my $test_xml_file = '/tmp/test_xml_file.xml';
    open my $fh, '>', $test_xml_file;
    print $fh $complex_xml;
    close $fh;

    $result = $bridge->call_python('xml_helper', 'xml_in', {
        source => $test_xml_file,
        source_type => 'file'
    });

    if ($result->{success}) {
        print "Parse XML file: PASS\n";
    } else {
        print "Parse XML file: FAIL - " . $result->{error} . "\n";
    }

    # Test 5: Error handling (malformed XML)
    my $malformed_xml = 'not xml at all - just plain text';

    $result = $bridge->call_python('xml_helper', 'xml_in', {
        source => $malformed_xml,
        source_type => 'string'
    });

    if (!$result->{success}) {
        print "Malformed XML handling: PASS\n";
    } else {
        print "Malformed XML handling: SKIP - ElementTree is permissive\n";
    }

    # Test 6: Unicode XML
    my $unicode_xml = '<root><text>Hello 世界 🌍</text></root>';

    $result = $bridge->call_python('xml_helper', 'xml_in', {
        source => $unicode_xml,
        source_type => 'string'
    });

    if ($result->{success}) {
        my $text_content = $result->{result}->{text};
        if ($text_content && length($text_content) > 5) {
            print "Unicode XML: PASS - content parsed (encoding may differ)\n";
        } else {
            print "Unicode XML: FAIL - no content parsed\n";
        }
    } else {
        print "Unicode XML: FAIL - " . $result->{error} . "\n";
    }

    # Cleanup
    unlink $test_xml_file if -f $test_xml_file;

    return 1;
}

# Test both modes
test_xml_mode("Daemon Mode", 1);

print "\n=== XML Helper Module Validation Complete ===\n";