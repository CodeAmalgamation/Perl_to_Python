#!/usr/bin/perl
# test_xpath.pl - Comprehensive test suite for XPathHelper
# Tests all XPath patterns found in your codebase analysis

use strict;
use warnings;
use lib '.';
use XPathHelper;
use File::Temp qw(tempfile);

# Test configuration
our $TEST_COUNT = 0;
our $PASS_COUNT = 0;
our $FAIL_COUNT = 0;
our $VERBOSE = $ENV{XPATH_TEST_VERBOSE} || 0;

print "=" x 60 . "\n";
print "XPathHelper Production Test Suite\n";
print "=" x 60 . "\n\n";

# Test 1: Document loading (your primary pattern)
test_document_loading();

# Test 2: Your actual XPath expressions
test_xpath_expressions();

# Test 3: Node processing patterns
test_node_processing();

# Test 4: Error handling patterns
test_error_handling();

# Test 5: Production scenario simulation
test_production_scenarios();

# Test 6: Performance validation
test_performance();

# Summary
print "\n" . "=" x 60 . "\n";
print "TEST SUMMARY\n";
print "=" x 60 . "\n";
print "Total Tests: $TEST_COUNT\n";
print "Passed: $PASS_COUNT\n";
print "Failed: $FAIL_COUNT\n";

if ($FAIL_COUNT == 0) {
    print "\n✓ ALL TESTS PASSED - XPathHelper ready for production!\n";
    exit 0;
} else {
    print "\n✗ SOME TESTS FAILED - Review failures before deployment\n";
    exit 1;
}

#================================================================
# TEST FUNCTIONS
#================================================================

sub test_document_loading {
    print_test_header("Document Loading Patterns");
    
    # Create test XML file
    my $test_xml = create_test_xml();
    my ($temp_fh, $temp_file) = tempfile(SUFFIX => '.xml', UNLINK => 1);
    print $temp_fh $test_xml;
    close($temp_fh);
    
    # Test 1a: Basic document loading
    my $Xml = eval { XPathHelper->new(filename => $temp_file) };
    test_result("Document loading", defined($Xml) && !$@, $@ || "Success");
    
    # Test 1b: Error handling with missing file
    my $missing = eval { XPathHelper->new(filename => "/nonexistent/file.xml") };
    test_result("Missing file handling", !defined($missing) && $@, "Should die gracefully");
    
    # Test 1c: Error handling with malformed XML
    my ($bad_fh, $bad_file) = tempfile(SUFFIX => '.xml', UNLINK => 1);
    print $bad_fh "<broken><xml>";  # Malformed XML
    close($bad_fh);
    
    my $bad_xml = eval { XPathHelper->new(filename => $bad_file) };
    test_result("Malformed XML handling", !defined($bad_xml) && $@, "Should die gracefully");
    
    print_test_footer();
}

sub test_xpath_expressions {
    print_test_header("XPath Expression Testing");
    
    # Create comprehensive test XML
    my $test_xml = create_comprehensive_test_xml();
    my ($temp_fh, $temp_file) = tempfile(SUFFIX => '.xml', UNLINK => 1);
    print $temp_fh $test_xml;
    close($temp_fh);
    
    my $Xml = XPathHelper->new(filename => $temp_file);
    
    # Test your actual XPath expressions from the analysis
    my %xpath_tests = (
        '/DocumentMessage/Fax/*' => { min_nodes => 3, description => 'Fax children wildcard' },
        '//apps/app[@name="TestApp"]' => { min_nodes => 1, description => 'App with attribute predicate' },
        'version[@name="1.0"]' => { min_nodes => 0, description => 'Version with attribute (context dependent)' },
        '//dependency' => { min_nodes => 1, description => 'Simple element search' },
        '//reference' => { min_nodes => 1, description => 'Reference element' },
        '//vm' => { min_nodes => 1, description => 'VM element' },
        '//parm' => { min_nodes => 1, description => 'Parameter element' },
    );
    
    for my $xpath (sort keys %xpath_tests) {
        my $test_info = $xpath_tests{$xpath};
        my $nodes = eval { $Xml->find($xpath) };
        
        if (defined($nodes) && !$@) {
            my $size = $nodes->size();
            my $pass = $size >= $test_info->{min_nodes};
            test_result(
                "XPath: $xpath", 
                $pass, 
                "$test_info->{description} - Found $size nodes (expected >= $test_info->{min_nodes})"
            );
        } else {
            test_result("XPath: $xpath", 0, $@ || "Failed to execute");
        }
    }
    
    print_test_footer();
}

sub test_node_processing {
    print_test_header("Node Processing Patterns");
    
    my $test_xml = create_comprehensive_test_xml();
    my ($temp_fh, $temp_file) = tempfile(SUFFIX => '.xml', UNLINK => 1);
    print $temp_fh $test_xml;
    close($temp_fh);
    
    my $Xml = XPathHelper->new(filename => $temp_file);
    
    # Test 3a: Node iteration pattern (your primary usage)
    my $FaxNodes = eval { $Xml->find("/DocumentMessage/Fax/*") };
    test_result("Get Fax nodes", defined($FaxNodes) && !$@, $@ || "Success");
    
    if ($FaxNodes) {
        # Test node list iteration
        my @nodes = eval { $FaxNodes->get_nodelist() };
        test_result("Get node list", scalar(@nodes) > 0 && !$@, $@ || sprintf("Got %d nodes", scalar(@nodes)));
        
        # Test node methods (your usage patterns)
        if (@nodes) {
            my $node = $nodes[0];
            
            # Test getName method
            my $name = eval { $node->getName() };
            test_result("Node getName()", defined($name) && !$@, $@ || "Name: $name");
            
            # Test string_value method
            my $value = eval { $node->string_value() };
            test_result("Node string_value()", defined($value) && !$@, $@ || "Value: $value");
            
            # Test getAttribute method (if node has attributes)
            my $attr = eval { $node->getAttribute("name") };
            test_result("Node getAttribute()", !$@ , $@ || "Attribute access works");
        }
    }
    
    # Test 3b: Size checking (your conditional pattern)
    my $AppNodes = eval { $Xml->find('//apps/app[@name="TestApp"]') };
    if ($AppNodes) {
        my $size = eval { $AppNodes->size() };
        test_result("NodeSet size()", defined($size) && !$@, $@ || "Size: $size");
        
        # Test your conditional pattern: if ($AppNodes->size && $AppNodes->size < 1)
        my $size_check = $AppNodes->size && $AppNodes->size >= 1;
        test_result("Size conditional check", $size_check, "Size-based conditional logic");
    }
    
    print_test_footer();
}

sub test_error_handling {
    print_test_header("Error Handling Patterns");
    
    my $test_xml = create_test_xml();
    my ($temp_fh, $temp_file) = tempfile(SUFFIX => '.xml', UNLINK => 1);
    print $temp_fh $test_xml;
    close($temp_fh);
    
    my $Xml = XPathHelper->new(filename => $temp_file);
    
    # Test 4a: Invalid XPath expression
    my $bad_result = eval { $Xml->find("invalid[[[xpath") };
    test_result("Invalid XPath handling", !defined($bad_result) && $@, "Should croak on bad XPath");
    
    # Test 4b: Non-ex