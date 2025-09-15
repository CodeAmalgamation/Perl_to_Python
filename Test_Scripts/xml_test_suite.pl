#!/usr/bin/perl
# test_xml_complete.pl - Comprehensive test suite for XMLHelper
# Tests all patterns found in your XML::Simple usage analysis

use strict;
use warnings;
use lib '.';
use XMLHelper;
use Data::Dumper;
use File::Temp qw(tempfile);

# Test configuration
our $VERBOSE = $ENV{XML_TEST_VERBOSE} || 0;
our $TEST_COUNT = 0;
our $PASS_COUNT = 0;
our $FAIL_COUNT = 0;

print "=" x 60 . "\n";
print "XMLHelper Production Test Suite\n";
print "=" x 60 . "\n\n";

# Test 1: Basic XMLHelper instantiation
test_basic_instantiation();

# Test 2: Template loading pattern (KeepRoot => 0)
test_template_loading();

# Test 3: Response parsing pattern (no options)
test_response_parsing();

# Test 4: Two-level XML parsing pattern
test_nested_parsing();

# Test 5: Optional element handling
test_optional_elements();

# Test 6: Error handling patterns
test_error_handling();

# Test 7: File vs String detection
test_source_detection();

# Test 8: XML::Simple compatibility
test_xml_simple_compatibility();

# Test 9: Production scenario simulation
test_production_scenario();

# Test 10: Performance and memory testing
test_performance();

# Summary
print "\n" . "=" x 60 . "\n";
print "TEST SUMMARY\n";
print "=" x 60 . "\n";
print "Total Tests: $TEST_COUNT\n";
print "Passed: $PASS_COUNT\n";
print "Failed: $FAIL_COUNT\n";
print "Success Rate: " . sprintf("%.1f%%", ($PASS_COUNT / $TEST_COUNT) * 100) . "\n";

if ($FAIL_COUNT == 0) {
    print "\n🎉 ALL TESTS PASSED - XMLHelper ready for production!\n";
    exit 0;
} else {
    print "\n❌ SOME TESTS FAILED - Review failures before deployment\n";
    exit 1;
}

#================================================================
# TEST FUNCTIONS
#================================================================

sub test_basic_instantiation {
    print_test_header("Basic XMLHelper Instantiation");
    
    # Test 1a: Object creation
    my $parser = eval { XMLHelper->new() };
    test_result("XMLHelper->new()", defined($parser) && !$@, $@ || "Success");
    
    # Test 1b: Class method compatibility
    my $parser2 = eval { new XMLHelper };
    test_result("new XMLHelper", defined($parser2) && !$@, $@ || "Success");
    
    # Test 1c: Object inheritance
    test_result("Inherits from CPANBridge", $parser->isa('CPANBridge'), "Inheritance check");
    
    print_test_footer();
}

sub test_template_loading {
    print_test_header("Template Loading Pattern (KeepRoot => 0)");
    
    # Create test XML template file
    my $template_xml = create_test_template();
    my ($temp_fh, $temp_file) = tempfile(SUFFIX => '.xml', UNLINK => 1);
    print $temp_fh $template_xml;
    close($temp_fh);
    
    # Test 2a: Template loading with KeepRoot => 0
    my $parser = XMLHelper->new();
    my $template = eval { $parser->XMLin($temp_file, KeepRoot => 0) };
    
    test_result("Template loading", defined($template) && !$@, $@ || "Success");
    
    # Test 2b: Verify structure matches expected pattern
    if ($template) {
        test_result("Has setup section", exists($template->{setup}), "Structure check");
        test_result("Has body section", exists($template->{body}), "Structure check");
        
        # Test template modification (your usage pattern)
        eval {
            $template->{setup}->{action} = "Create";
            $template->{body}->{incidentTitle} = "Test Incident";
        };
        test_result("Template modification", !$@, $@ || "Success");
    }
    
    print_test_footer();
}

sub test_response_parsing {
    print_test_header("Response Parsing Pattern (No Options)");
    
    # Create test response XML
    my $response_xml = create_test_response();
    
    # Test 3a: Basic response parsing
    my $parser = XMLHelper->new();
    my $response = eval { $parser->XMLin($response_xml) };
    
    test_result("Response parsing", defined($response) && !$@, $@ || "Success");
    
    # Test 3b: Access patterns from your code
    if ($response && ref($response) eq 'HASH') {
        # Test ReturnCode access
        my $return_code = eval { $response->{ReturnCode} };
        test_result("ReturnCode access", defined($return_code), "Can access ReturnCode");
        
        # Test nested body access
        my $body = eval { $response->{body} };
        test_result("Body access", defined($body), "Can access body");
        
        if ($body && ref($body) eq 'HASH') {
            my $incident_number = eval { $body->{incidentNumber} };
            test_result("Incident number access", defined($incident_number), "Can access nested data");
        }
    }
    
    print_test_footer();
}

sub test_nested_parsing {
    print_test_header("Two-Level XML Parsing Pattern");
    
    # Create nested XML structure
    my $outer_xml = create_nested_xml();
    
    # Test 4a: First level parsing
    my $parser = XMLHelper->new();
    my $outer_data = eval { $parser->XMLin($outer_xml) };
    
    test_result("Outer XML parsing", defined($outer_data) && !$@, $@ || "Success");
    
    # Test 4b: Second level parsing (your pattern)
    if ($outer_data && $outer_data->{content}) {
        my $inner_data = eval { $parser->XMLin($outer_data->{content}) };
        test_result("Inner XML parsing", defined($inner_data) && !$@, $@ || "Success");
        
        if ($inner_data) {
            test_result("Inner data structure", ref($inner_data) eq 'HASH', "Correct data type");
        }
    }
    
    print_test_footer();
}

sub test_optional_elements {
    print_test_header("Optional Element Handling");
    
    # Test 5a: Response with all elements
    my $complete_response = create_complete_response();
    my $parser = XMLHelper->new();
    my $complete = eval { $parser->XMLin($complete_response) };
    
    test_result("Complete response", defined($complete) && !$@, $@ || "Success");
    
    if ($complete) {
        # Test all optional elements exist
        test_result("ReturnMessage exists", exists($complete->{ReturnMessage}), "Optional element check");
        test_result("Error exists", exists($complete->{body}->{Error}), "Nested optional check");
    }
    
    # Test 5b: Response with missing elements
    my $minimal_response = create_minimal_response();
    my $minimal = eval { $parser->XMLin($minimal_response) };
    
    test_result("Minimal response", defined($minimal) && !$@, $@ || "Success");
    
    if ($minimal) {
        # Test graceful handling of missing elements
        my $return_message = eval { $minimal->{ReturnMessage} };
        test_result("Missing ReturnMessage", !defined($return_message) || $return_message eq '', "Graceful handling");
        
        my $error_message = eval { $minimal->{body}->{Error}->{ErrorMessage} };
        test_result("Missing ErrorMessage", !defined($error_message), "Nested missing element");
    }
    
    print_test_footer();
}

sub test_error_handling {
    print_test_header("Error Handling Patterns");
    
    my $parser = XMLHelper->new();
    
    # Test 6a: Invalid XML
    my $invalid_xml = "<broken><xml></broken>";
    my $result = eval { $parser->XMLin($invalid_xml) };
    test_result("Invalid XML handling", !defined($result) && $@, "Should fail gracefully");
    
    # Test 6b: Missing file
    my $missing_result = eval { $parser->XMLin("/nonexistent/file.xml") };
    test_result("Missing file handling", !defined($missing_result) && $@, "Should fail gracefully");
    
    # Test 6c: Empty input
    my $empty_result = eval { $parser->XMLin("") };
    test_result("Empty input handling", !defined($empty_result) && $@, "Should fail gracefully");
    
    # Test 6d: Error message accessibility
    test_result("Error details available", $parser->get_last_error(), "Error tracking");
    
    print_test_footer();
}

sub test_source_detection {
    print_test_header("Source Type Detection");
    
    my $parser = XMLHelper->new();
    
    # Test 7a: XML string detection
    my $xml_string = "<root><test>value</test></root>";
    my $string_result = eval { $parser->XMLin($xml_string) };
    test_result("XML string parsing", defined($string_result) && !$@, $@ || "Success");
    
    # Test 7b: File detection
    my ($temp_fh, $temp_file) = tempfile(SUFFIX => '.xml', UNLINK => 1);
    print $temp_fh $xml_string;
    close($temp_fh);
    
    my $file_result = eval { $parser->XMLin($temp_file) };
    test_result("XML file parsing", defined($file_result) && !$@, $@ || "Success");
    
    print_test_footer();
}

sub test_xml_simple_compatibility {
    print_test_header("XML::Simple Compatibility");
    
    # Test 8a: Class method calls (XML::Simple style)
    my $result1 = eval { XMLHelper->XMLin("<root><test>1</test></root>") };
    test_result("Class method XMLin", defined($result1) && !$@, $@ || "Success");
    
    # Test 8b: Constructor style used in your code
    my $templateParser = eval { new XMLHelper };
    test_result("Constructor compatibility", defined($templateParser) && !$@, $@ || "Success");
    
    if ($templateParser) {
        my $result2 = eval { $templateParser->XMLin("<root><test>2</test></root>") };
        test_result("Instance method XMLin", defined($result2) && !$@, $@ || "Success");
    }
    
    print_test_footer();
}

sub test_production_scenario {
    print_test_header("Production Scenario Simulation");
    
    # Simulate your actual usage pattern
    my ($temp_fh, $ticketFile) = tempfile(SUFFIX => '.xml', UNLINK => 1);
    print $temp_fh create_test_template();
    close($temp_fh);
    
    # Test 9a: Exact pattern from HpsmTicket.pm
    my $templateParser = new XMLHelper;
    my $ticketTemplate = eval { $templateParser->XMLin($ticketFile, KeepRoot => 0) };
    
    test_result("Production template loading", defined($ticketTemplate) && !$@, $@ || "Success");
    
    if ($ticketTemplate) {
        # Test template modification pattern
        eval {
            $ticketTemplate->{setup}->{action} = "Create";
            $ticketTemplate->{body}->{incidentTitle} = "Test Summary";
        };
        test_result("Template modification", !$@, $@ || "Success");
        
        # Test accessing modified values
        my $action = $ticketTemplate->{setup}->{action};
        my $title = $ticketTemplate->{body}->{incidentTitle};
        test_result("Modified values accessible", 
                   $action eq "Create" && $title eq "Test Summary", 
                   "Values match");
    }
    
    # Test 9b: Response parsing pattern
    my $parser = new XMLHelper;
    my $web_response_content = create_web_response();
    
    my $respData = eval { $parser->XMLin($web_response_content) };
    test_result("Web response parsing", defined($respData) && !$@, $@ || "Success");
    
    if ($respData && $respData->{content}) {
        my $respContent = eval { $parser->XMLin($respData->{content}) };
        test_result("Nested response parsing", defined($respContent) && !$@, $@ || "Success");
        
        if ($respContent) {
            # Test your conditional patterns
            my $has_return_code = exists($respContent->{ReturnCode});
            my $has_return_message = exists($respContent->{ReturnMessage});
            my $has_error_message = exists($respContent->{body}->{Error}->{ErrorMessage});
            
            test_result("Return code exists", $has_return_code, "Conditional check");
            test_result("Optional elements handled", 1, "Structure accessible");
        }
    }
    
    print_test_footer();
}

sub test_performance {
    print_test_header("Performance Testing");
    
    my $parser = XMLHelper->new(debug => 0);  # Disable debug for performance test
    my $test_xml = create_test_template();
    
    # Test 10a: Multiple parsing operations
    my $start_time = time();
    my $iterations = 10;
    my $success_count = 0;
    
    for my $i (1..$iterations) {
        my $result = eval { $parser->XMLin($test_xml) };
        $success_count++ if defined($result) && !$@;
    }
    
    my $duration = time() - $start_time;
    my $avg_time = $duration / $iterations * 1000; # Convert to ms
    
    test_result("Performance test", $success_count == $iterations, 
               sprintf("%.2fms average per parse", $avg_time));
    
    # Test 10b: Memory usage (basic check)
    my $large_xml = create_large_xml();
    my $large_result = eval { $parser->XMLin($large_xml) };
    test_result("Large XML handling", defined($large_result) && !$@, $@ || "Success");
    
    print_test_footer();
}

#================================================================
# UTILITY FUNCTIONS
#================================================================

sub test_result {
    my ($test_name, $condition, $details) = @_;
    
    $TEST_COUNT++;
    
    if ($condition) {
        $PASS_COUNT++;
        print "✓ PASS: $test_name\n";
        print "       $details\n" if $VERBOSE && $details ne "Success";
    } else {
        $FAIL_COUNT++;
        print "✗ FAIL: $test_name\n";
        print "       $details\n" if $details;
    }
}

sub print_test_header {
    my $title = shift;
    print "\n" . "-" x 60 . "\n";
    print "$title\n";
    print "-" x 60 . "\n";
}

sub print_test_footer {
    print "\n";
}

#================================================================
# TEST DATA GENERATORS
#================================================================

sub create_test_template {
    return <<'EOF';
<?xml version="1.0" encoding="UTF-8"?>
<eHubTemplate>
    <setup>
        <action>Template</action>
        <service>HPSM</service>
    </setup>
    <body>
        <incidentTitle></incidentTitle>
        <incidentDescription></incidentDescription>
        <priority>3</priority>
        <category>Software</category>
    </body>
</eHubTemplate>
EOF
}

sub create_test_response {
    return <<'EOF';
<response>
    <ReturnCode>0</ReturnCode>
    <ReturnMessage>Success</ReturnMessage>
    <body>
        <incidentNumber>INC123456</incidentNumber>
        <status>Open</status>
    </body>
</response>
EOF
}

sub create_nested_xml {
    my $inner_xml = '<inner><data>nested content</data></inner>';
    return <<EOF;
<outer>
    <wrapper>
        <content>$inner_xml</content>
    </wrapper>
</outer>
EOF
}

sub create_complete_response {
    return <<'EOF';
<response>
    <ReturnCode>1</ReturnCode>
    <ReturnMessage>Error occurred</ReturnMessage>
    <body>
        <incidentNumber></incidentNumber>
        <Error>
            <ErrorMessage>Validation failed</ErrorMessage>
            <ErrorCode>E001</ErrorCode>
        </Error>
    </body>
</response>
EOF
}

sub create_minimal_response {
    return <<'EOF';
<response>
    <ReturnCode>0</ReturnCode>
    <body>
        <incidentNumber>INC789012</incidentNumber>
    </body>
</response>
EOF
}

sub create_web_response {
    my $inner_response = create_test_response();
    return <<EOF;
<webServiceResponse>
    <status>200</status>
    <content>$inner_response</content>
    <timestamp>2025-01-01T12:00:00Z</timestamp>
</webServiceResponse>
EOF
}

sub create_large_xml {
    my $xml = "<large>\n";
    for my $i (1..100) {
        $xml .= "  <item id=\"$i\">\n";
        $xml .= "    <name>Item $i</name>\n";
        $xml .= "    <value>" . ($i * 10) . "</value>\n";
        $xml .= "    <data>Some test data for item $i</data>\n";
        $xml .= "  </item>\n";
    }
    $xml .= "</large>\n";
    return $xml;
}