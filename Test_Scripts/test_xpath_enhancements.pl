#!/usr/bin/perl
# test_xpath_enhancements.pl - Test new XPathHelper features
# Tests for getNodeText() and XML string loading

use strict;
use warnings;
use lib '.';
use XPathHelper;
use File::Temp qw(tempfile);

# Test configuration
our $TEST_COUNT = 0;
our $PASS_COUNT = 0;
our $FAIL_COUNT = 0;

print "=" x 70 . "\n";
print "XPathHelper Enhancement Test Suite\n";
print "Testing: getNodeText() method + XML string loading\n";
print "=" x 70 . "\n\n";

# Test 1: getNodeText() method
test_getNodeText_method();

# Test 2: XML string loading (Informatica pattern)
test_xml_string_loading();

# Test 3: Production wrapper pattern (WebSphere/WebLogic style)
test_production_wrapper_pattern();

# Test 4: Error handling for new features
test_error_handling();

# Summary
print "\n" . "=" x 70 . "\n";
print "TEST SUMMARY\n";
print "=" x 70 . "\n";
print "Total Tests: $TEST_COUNT\n";
print "Passed: $PASS_COUNT\n";
print "Failed: $FAIL_COUNT\n";

if ($FAIL_COUNT == 0) {
    print "\n✓ ALL TESTS PASSED - Ready for production migration!\n";
    exit 0;
} else {
    print "\n✗ SOME TESTS FAILED - Review failures\n";
    exit 1;
}

#================================================================
# TEST FUNCTIONS
#================================================================

sub test_getNodeText_method {
    print_test_header("getNodeText() Method Tests");

    # Create test XML matching production patterns
    my $test_xml = create_websphere_style_xml();
    my ($temp_fh, $temp_file) = tempfile(SUFFIX => '.xml', UNLINK => 1);
    print $temp_fh $test_xml;
    close($temp_fh);

    my $xml = eval { XPathHelper->new(filename => $temp_file) };
    test_result("Load WebSphere-style XML", defined($xml) && !$@, $@ || "Success");

    if ($xml) {
        # Test 1a: getNodeText() with single node result
        my $version_nodes = eval { $xml->find('//domain[@name="PROD"]/server[@name="Server1"]/version') };
        if ($version_nodes && $version_nodes->size > 0) {
            my @nodes = $version_nodes->get_nodelist();
            my $text = eval { $xml->getNodeText($nodes[0]) };
            test_result(
                "getNodeText() extracts version",
                !$@ && defined($text) && $text eq '9.0.5.0',
                $@ || "Got: '$text'"
            );
        }

        # Test 1b: getNodeText() in loop (production pattern)
        my @hosts;
        my $host_nodes = eval { $xml->find('//server/host') };
        if ($host_nodes) {
            foreach my $node ($host_nodes->get_nodelist) {
                my $host = eval { $xml->getNodeText($node) };
                push @hosts, $host if defined($host);
            }
            test_result(
                "getNodeText() in loop extracts all hosts",
                scalar(@hosts) == 3 && $hosts[0] eq 'server1.company.com',
                "Got " . scalar(@hosts) . " hosts"
            );
        }

        # Test 1c: getNodeText() with attribute query (production pattern)
        my $server_name_nodes = eval { $xml->find('//server[@name="Server2"]/@name') };
        if ($server_name_nodes && $server_name_nodes->size > 0) {
            my @nodes = $server_name_nodes->get_nodelist();
            my $name = eval { $xml->getNodeText($nodes[0]) };
            test_result(
                "getNodeText() extracts attribute value",
                !$@ && defined($name),
                $@ || "Got attribute value"
            );
        }
    }

    print_test_footer();
}

sub test_xml_string_loading {
    print_test_header("XML String Loading Tests (Informatica Pattern)");

    # Test 2a: Load XML from string (Informatica workflow log pattern)
    my $informatica_xml = create_informatica_log_xml();

    my $xp = eval { XPathHelper->new(xml => $informatica_xml) };
    test_result(
        "Load XML from string (Informatica pattern)",
        defined($xp) && !$@,
        $@ || "Success"
    );

    if ($xp) {
        # Test 2b: Find log events
        my $nodeset = eval { $xp->find('//logEvent') };
        test_result(
            "Find all logEvent nodes",
            defined($nodeset) && $nodeset->size == 3,
            "Found " . ($nodeset ? $nodeset->size : 0) . " nodes"
        );

        # Test 2c: Filter by severity (Informatica production pattern)
        my $error_nodes = eval { $xp->find('//logEvent[@severity="1" or @severity="2"]') };
        test_result(
            "Find errors/warnings with OR predicate",
            defined($error_nodes) && $error_nodes->size == 2,
            "Found " . ($error_nodes ? $error_nodes->size : 0) . " error/warning nodes"
        );

        # Test 2d: Extract attributes (Informatica production pattern)
        if ($error_nodes && $error_nodes->size > 0) {
            for my $node ($error_nodes->get_nodelist) {
                my $timestamp = eval { sprintf("%s", $node->find('@timestamp')) };
                my $severity = eval { sprintf("%s", $node->find('@severity')) };
                my $message_code = eval { sprintf("%s", $node->find('@messageCode')) };

                test_result(
                    "Extract log attributes from node",
                    !$@ && defined($timestamp) && defined($severity) && defined($message_code),
                    $@ || "timestamp=$timestamp, severity=$severity, code=$message_code"
                );
            }
        }
    }

    # Test 2e: Empty string handling
    my $empty_xml = eval { XPathHelper->new(xml => "") };
    test_result(
        "Reject empty XML string",
        !defined($empty_xml) && $@,
        "Should die on empty string"
    );

    # Test 2f: Malformed XML string handling
    my $bad_xml = eval { XPathHelper->new(xml => "<broken><xml>") };
    test_result(
        "Reject malformed XML string",
        !defined($bad_xml) && $@,
        "Should die on malformed XML"
    );

    print_test_footer();
}

sub test_production_wrapper_pattern {
    print_test_header("Production Wrapper Pattern Tests (WebSphere/WebLogic)");

    # Create test XML
    my $test_xml = create_websphere_style_xml();
    my ($temp_fh, $temp_file) = tempfile(SUFFIX => '.xml', UNLINK => 1);
    print $temp_fh $test_xml;
    close($temp_fh);

    my $was_conf = XPathHelper->new(filename => $temp_file);

    # Test 3a: Wrapper function pattern (exactly as in 30165CbiWasCtl.pl)
    sub get_configuration {
        my ($conf_obj, $query) = @_;
        my @result;
        my $set = $conf_obj->find("$query");
        foreach ( $set->get_nodelist ) {
            push @result, $conf_obj->getNodeText($_);
        }
        return wantarray ? @result : $result[0];
    }

    # Test wrapper in scalar context
    my $version = get_configuration($was_conf, '//domain[@name="PROD"]/server[@name="Server1"]/version');
    test_result(
        "Wrapper function - scalar context",
        defined($version) && $version eq '9.0.5.0',
        "Got: '$version'"
    );

    # Test wrapper in array context
    my @hosts = get_configuration($was_conf, '//server/host');
    test_result(
        "Wrapper function - array context",
        scalar(@hosts) == 3 && $hosts[0] eq 'server1.company.com' && $hosts[1] eq 'server2.company.com' && $hosts[2] eq 'testserver.company.com',
        "Got " . scalar(@hosts) . " hosts: " . join(", ", @hosts)
    );

    # Test with complex predicate (production pattern)
    my $server_name = get_configuration(
        $was_conf,
        '//domain[@name="PROD"]/server[@name="Server1"]/@name'
    );
    test_result(
        "Wrapper with complex predicate",
        defined($server_name),
        "Got server name"
    );

    print_test_footer();
}

sub test_error_handling {
    print_test_header("Error Handling for New Features");

    # Test 4a: getNodeText() with undef
    my $test_xml = create_websphere_style_xml();
    my ($temp_fh, $temp_file) = tempfile(SUFFIX => '.xml', UNLINK => 1);
    print $temp_fh $test_xml;
    close($temp_fh);

    my $xml = XPathHelper->new(filename => $temp_file);
    my $result = eval { $xml->getNodeText(undef) };
    test_result(
        "getNodeText() rejects undef",
        !defined($result) && $@,
        "Should croak on undef"
    );

    # Test 4b: new() with neither filename nor xml
    my $no_param = eval { XPathHelper->new() };
    test_result(
        "new() requires filename or xml parameter",
        !defined($no_param) && $@,
        "Should croak when both missing"
    );

    # Test 4c: XML string with non-UTF8 characters (edge case)
    my $utf8_xml = '<?xml version="1.0" encoding="UTF-8"?><root><test>café</test></root>';
    my $utf8_obj = eval { XPathHelper->new(xml => $utf8_xml) };
    test_result(
        "Handle UTF-8 in XML string",
        defined($utf8_obj) && !$@,
        $@ || "UTF-8 handled correctly"
    );

    print_test_footer();
}

#================================================================
# HELPER FUNCTIONS
#================================================================

sub create_websphere_style_xml {
    return <<'XML';
<?xml version="1.0"?>
<configuration>
    <domain name="PROD">
        <server name="Server1">
            <version>9.0.5.0</version>
            <host>server1.company.com</host>
            <port type="https">9443</port>
            <location type="server">/opt/IBM/WebSphere</location>
            <location type="properties">/opt/IBM/WebSphere/properties</location>
            <startserver>/opt/IBM/WebSphere/bin/startServer.sh</startserver>
            <stopserver>/opt/IBM/WebSphere/bin/stopServer.sh</stopserver>
        </server>
        <server name="Server2">
            <version>9.0.5.0</version>
            <host>server2.company.com</host>
            <port type="https">9443</port>
        </server>
    </domain>
    <domain name="TEST">
        <server name="TestServer1">
            <version>9.0.0.0</version>
            <host>testserver.company.com</host>
        </server>
    </domain>
</configuration>
XML
}

sub create_informatica_log_xml {
    return <<'XML';
<?xml version="1.0"?>
<workflowLog>
    <logEvent timestamp="1704981000" severity="3" messageCode="INFO_001" clientNode="node1" message="Workflow started successfully"/>
    <logEvent timestamp="1704981060" severity="1" messageCode="ERROR_042" clientNode="node2" message="Connection timeout to database"/>
    <logEvent timestamp="1704981120" severity="2" messageCode="WARN_015" clientNode="node1" message="High memory usage detected"/>
</workflowLog>
XML
}

sub test_result {
    my ($test_name, $passed, $details) = @_;

    $TEST_COUNT++;

    if ($passed) {
        $PASS_COUNT++;
        print "  ✓ $test_name\n";
        print "    $details\n" if $details && $ENV{XPATH_TEST_VERBOSE};
    } else {
        $FAIL_COUNT++;
        print "  ✗ $test_name\n";
        print "    FAILED: $details\n";
    }
}

sub print_test_header {
    my $title = shift;
    print "\n" . "-" x 70 . "\n";
    print "$title\n";
    print "-" x 70 . "\n";
}

sub print_test_footer {
    print "-" x 70 . "\n";
}
