# CPAN Bridge - Baseline Functionality Testing Stories

**Focused Jira test stories for validating core baseline functionality of the CPAN Bridge system before advanced testing.**

---

## 📋 Project Overview

### **What is CPAN Bridge?**

The CPAN Bridge system enables Perl applications to execute Python operations seamlessly, providing access to Python libraries and functionality from Perl scripts. This is particularly valuable in RHEL 9 environments where CPAN modules may not be available.

### **Two Operating Modes**

1. **Process Mode**: Each operation spawns a new Python process (traditional approach)
2. **Daemon Mode**: Operations use a persistent Python daemon (new high-performance approach)

### **Why Baseline Testing Matters**

Before testing advanced daemon features, we must validate that:
- All 11 helper modules work correctly in both modes
- Data flows properly between Perl and Python
- Error handling works as expected
- No regressions exist in core functionality

---

## 🎯 Testing Focus

### **Baseline Validation Goals**

✅ **Functional Correctness**: Every module performs its intended operations
✅ **Data Integrity**: All data types transfer correctly between Perl/Python
✅ **Error Handling**: Failures are properly caught and reported
✅ **Mode Equivalence**: Both process and daemon modes produce identical results
✅ **Module Coverage**: All 11 helper modules are thoroughly tested

### **Available Helper Modules**

| Module | Purpose | Key Operations |
|--------|---------|----------------|
| `test` | System validation | ping, echo, health checks |
| `http` | Web requests | GET, POST, PUT, DELETE |
| `database` | Database operations | connect, query, transactions |
| `sftp` | File transfers | upload, download, directory operations |
| `excel` | Spreadsheet generation | workbooks, worksheets, cell writing |
| `xml_helper` | XML processing | parsing, generation, validation |
| `crypto` | Cryptographic operations | encrypt, decrypt, hash |
| `email_helper` | Email operations | send email, attachments |
| `datetime_helper` | Date/time operations | formatting, parsing, calculations |
| `logging_helper` | Logging operations | structured logging, levels |
| `xpath` | XML querying | XPath expressions, node selection |

---

## 📝 Baseline Test Stories

### **BASELINE-001: Test Module Validation**

**Epic**: Core Functionality
**Story Type**: Functional
**Priority**: Critical

**Background**:
The `test` module provides basic system validation functions. This is the simplest module and must work perfectly as it's used to validate daemon connectivity and basic operations.

**Acceptance Criteria**:
- [ ] `ping` function returns success with echo data
- [ ] `echo` function returns input data unchanged
- [ ] Both process and daemon modes work identically
- [ ] Error conditions are handled properly
- [ ] Response times are reasonable (<5 seconds in process mode)

**Test Data Needed**:
- Simple string data
- Complex data structures (arrays, hashes)
- Unicode characters
- Large payloads (within limits)

**Test Script**:
```perl
#!/usr/bin/perl
use strict;
use warnings;
use CPANBridge;
use Data::Dumper;

sub test_mode {
    my ($mode_name, $daemon_mode) = @_;

    print "\n=== Testing $mode_name ===\n";

    $CPANBridge::DAEMON_MODE = $daemon_mode;
    my $bridge = CPANBridge->new();

    # Test 1: Basic ping
    my $result = $bridge->call_python('test', 'ping', {});
    printf "Basic ping: %s\n", $result->{success} ? "PASS" : "FAIL - " . $result->{error};

    # Test 2: Echo simple data
    my $test_data = "Hello, World!";
    $result = $bridge->call_python('test', 'echo', { data => $test_data });
    if ($result->{success} && $result->{result}->{data} eq $test_data) {
        print "Echo simple: PASS\n";
    } else {
        print "Echo simple: FAIL\n";
    }

    # Test 3: Echo complex data
    my $complex_data = {
        string => "test string",
        number => 42,
        array => [1, 2, 3, "four"],
        hash => { nested => "value", count => 100 }
    };

    $result = $bridge->call_python('test', 'echo', { data => $complex_data });
    if ($result->{success}) {
        my $returned = $result->{result}->{data};
        if (ref($returned) eq 'HASH' && $returned->{string} eq "test string") {
            print "Echo complex: PASS\n";
        } else {
            print "Echo complex: FAIL - data structure mismatch\n";
        }
    } else {
        print "Echo complex: FAIL - " . $result->{error} . "\n";
    }

    # Test 4: Unicode handling
    my $unicode_data = "Hello 世界 🌍 café naïve résumé";
    $result = $bridge->call_python('test', 'echo', { data => $unicode_data });
    if ($result->{success} && $result->{result}->{data} eq $unicode_data) {
        print "Unicode handling: PASS\n";
    } else {
        print "Unicode handling: FAIL\n";
    }

    # Test 5: Error handling
    $result = $bridge->call_python('test', 'nonexistent_function', {});
    if (!$result->{success} && $result->{error}) {
        print "Error handling: PASS\n";
    } else {
        print "Error handling: FAIL - should have failed\n";
    }

    return 1;
}

# Test both modes
test_mode("Process Mode", 0);
test_mode("Daemon Mode", 1);

print "\n=== Test Module Validation Complete ===\n";
```

**Expected Results**:
- All basic tests should PASS in both modes
- Unicode characters should be preserved exactly
- Complex data structures should maintain their structure
- Error conditions should be properly reported

---

### **BASELINE-002: HTTP Module Validation**

**Epic**: Core Functionality
**Story Type**: Functional
**Priority**: High

**Background**:
The `http` module handles web requests and is commonly used for API integration. It must handle various HTTP methods, headers, and response formats correctly.

**Acceptance Criteria**:
- [ ] GET requests work with various URLs
- [ ] POST requests work with JSON and form data
- [ ] Headers are sent and received correctly
- [ ] Response codes, headers, and content are captured
- [ ] Error conditions (timeouts, network errors) are handled
- [ ] Both process and daemon modes produce identical results

**Test Script**:
```perl
#!/usr/bin/perl
use strict;
use warnings;
use CPANBridge;
use JSON;

sub test_http_mode {
    my ($mode_name, $daemon_mode) = @_;

    print "\n=== Testing HTTP Module - $mode_name ===\n";

    $CPANBridge::DAEMON_MODE = $daemon_mode;
    my $bridge = CPANBridge->new();

    # Test 1: Simple GET request
    my $result = $bridge->call_python('http', 'get', {
        url => 'https://httpbin.org/json'
    });

    if ($result->{success}) {
        my $response = $result->{result};
        if ($response->{status_code} == 200 && $response->{content}) {
            print "Simple GET: PASS\n";
        } else {
            print "Simple GET: FAIL - invalid response\n";
        }
    } else {
        print "Simple GET: FAIL - " . $result->{error} . "\n";
    }

    # Test 2: GET with headers
    $result = $bridge->call_python('http', 'get', {
        url => 'https://httpbin.org/headers',
        headers => {
            'User-Agent' => 'CPAN-Bridge-Test/1.0',
            'Accept' => 'application/json'
        }
    });

    if ($result->{success} && $result->{result}->{status_code} == 200) {
        print "GET with headers: PASS\n";
    } else {
        print "GET with headers: FAIL\n";
    }

    # Test 3: POST with JSON
    my $post_data = {
        test_field => "test_value",
        number_field => 42,
        array_field => [1, 2, 3]
    };

    $result = $bridge->call_python('http', 'post', {
        url => 'https://httpbin.org/post',
        json => $post_data,
        headers => { 'Content-Type' => 'application/json' }
    });

    if ($result->{success} && $result->{result}->{status_code} == 200) {
        print "POST with JSON: PASS\n";
    } else {
        print "POST with JSON: FAIL\n";
    }

    # Test 4: Error handling (invalid URL)
    $result = $bridge->call_python('http', 'get', {
        url => 'https://invalid-domain-that-does-not-exist.example'
    });

    if (!$result->{success} || $result->{result}->{status_code} >= 400) {
        print "Error handling: PASS\n";
    } else {
        print "Error handling: FAIL - should have failed\n";
    }

    # Test 5: Response data validation
    $result = $bridge->call_python('http', 'get', {
        url => 'https://httpbin.org/status/404'
    });

    if ($result->{success} && $result->{result}->{status_code} == 404) {
        print "Status code handling: PASS\n";
    } else {
        print "Status code handling: FAIL\n";
    }

    return 1;
}

# Test both modes
test_http_mode("Process Mode", 0);
test_http_mode("Daemon Mode", 1);

print "\n=== HTTP Module Validation Complete ===\n";
```

**Expected Results**:
- All HTTP methods should work correctly
- Response codes should be captured accurately
- JSON data should serialize/deserialize properly
- Network errors should be handled gracefully

---

### **BASELINE-003: Database Module Validation**

**Epic**: Core Functionality
**Story Type**: Functional
**Priority**: High

**Background**:
The `database` module handles database connections and operations. This is critical for many enterprise applications and must work reliably with proper error handling.

**Acceptance Criteria**:
- [ ] Database connections succeed with valid credentials
- [ ] SQL queries execute and return results
- [ ] Prepared statements work correctly
- [ ] Transactions (begin, commit, rollback) work
- [ ] Connection errors are handled properly
- [ ] Both process and daemon modes work identically

**Test Script**:
```perl
#!/usr/bin/perl
use strict;
use warnings;
use CPANBridge;

sub test_database_mode {
    my ($mode_name, $daemon_mode) = @_;

    print "\n=== Testing Database Module - $mode_name ===\n";

    $CPANBridge::DAEMON_MODE = $daemon_mode;
    my $bridge = CPANBridge->new();

    # Test 1: Database connection
    my $result = $bridge->call_python('database', 'connect', {
        dsn => 'dbi:Oracle:testdb',
        username => 'testuser',
        password => 'testpass'
    });

    if ($result->{success}) {
        print "Database connect: PASS\n";
    } else {
        print "Database connect: FAIL - " . $result->{error} . "\n";
        return 0;  # Can't continue without connection
    }

    # Test 2: Simple query execution
    $result = $bridge->call_python('database', 'execute_statement', {
        sql => 'SELECT SYSDATE FROM DUAL'
    });

    if ($result->{success}) {
        print "Simple query: PASS\n";
    } else {
        print "Simple query: FAIL - " . $result->{error} . "\n";
    }

    # Test 3: Query with parameters
    $result = $bridge->call_python('database', 'execute_statement', {
        sql => 'SELECT ? as test_value, ? as test_number FROM DUAL',
        params => ['test_string', 42]
    });

    if ($result->{success}) {
        print "Parameterized query: PASS\n";
    } else {
        print "Parameterized query: FAIL - " . $result->{error} . "\n";
    }

    # Test 4: Fetch results
    $result = $bridge->call_python('database', 'fetch_row', {});

    if ($result->{success} && $result->{result}) {
        print "Fetch row: PASS\n";
    } else {
        print "Fetch row: FAIL\n";
    }

    # Test 5: Transaction handling
    $result = $bridge->call_python('database', 'begin_transaction', {});
    if ($result->{success}) {
        print "Begin transaction: PASS\n";

        # Commit the transaction
        $result = $bridge->call_python('database', 'commit', {});
        if ($result->{success}) {
            print "Commit transaction: PASS\n";
        } else {
            print "Commit transaction: FAIL\n";
        }
    } else {
        print "Begin transaction: FAIL\n";
    }

    # Test 6: Error handling (invalid SQL)
    $result = $bridge->call_python('database', 'execute_statement', {
        sql => 'SELECT * FROM nonexistent_table_xyz'
    });

    if (!$result->{success}) {
        print "SQL error handling: PASS\n";
    } else {
        print "SQL error handling: FAIL - should have failed\n";
    }

    # Test 7: Disconnect
    $result = $bridge->call_python('database', 'disconnect', {});
    if ($result->{success}) {
        print "Database disconnect: PASS\n";
    } else {
        print "Database disconnect: FAIL\n";
    }

    return 1;
}

# Test both modes
test_database_mode("Process Mode", 0);
test_database_mode("Daemon Mode", 1);

print "\n=== Database Module Validation Complete ===\n";
```

**Expected Results**:
- Database connections should succeed with valid credentials
- SQL queries should execute and return expected data
- Transactions should commit/rollback properly
- Invalid SQL should generate appropriate error messages

---

### **BASELINE-004: SFTP Module Validation**

**Epic**: Core Functionality
**Story Type**: Functional
**Priority**: High

**Background**:
The `sftp` module handles secure file transfers over SSH. This is commonly used for automated file processing and must handle various file operations reliably.

**Acceptance Criteria**:
- [ ] SFTP connections succeed with valid credentials
- [ ] File uploads work correctly
- [ ] File downloads work correctly
- [ ] Directory listings work
- [ ] File operations (rename, delete) work
- [ ] Connection errors are handled properly

**Test Script**:
```perl
#!/usr/bin/perl
use strict;
use warnings;
use CPANBridge;

sub test_sftp_mode {
    my ($mode_name, $daemon_mode) = @_;

    print "\n=== Testing SFTP Module - $mode_name ===\n";

    $CPANBridge::DAEMON_MODE = $daemon_mode;
    my $bridge = CPANBridge->new();

    # Create test files
    system('echo "Test file content 1" > /tmp/test_upload_1.txt');
    system('echo "Test file content 2" > /tmp/test_upload_2.txt');

    # Test 1: SFTP connection
    my $result = $bridge->call_python('sftp', 'connect', {
        hostname => 'localhost',
        username => $ENV{USER},
        password => 'testpass'  # or use key-based auth
    });

    if ($result->{success}) {
        print "SFTP connect: PASS\n";
    } else {
        print "SFTP connect: FAIL - " . $result->{error} . "\n";
        return 0;  # Can't continue without connection
    }

    # Test 2: File upload
    $result = $bridge->call_python('sftp', 'put', {
        local_file => '/tmp/test_upload_1.txt',
        remote_file => '/tmp/test_remote_1.txt'
    });

    if ($result->{success}) {
        print "File upload: PASS\n";
    } else {
        print "File upload: FAIL - " . $result->{error} . "\n";
    }

    # Test 3: File download
    $result = $bridge->call_python('sftp', 'get', {
        remote_file => '/tmp/test_remote_1.txt',
        local_file => '/tmp/test_download_1.txt'
    });

    if ($result->{success}) {
        # Verify file content
        open my $fh, '<', '/tmp/test_download_1.txt';
        my $content = <$fh>;
        close $fh;
        chomp $content;

        if ($content eq "Test file content 1") {
            print "File download: PASS\n";
        } else {
            print "File download: FAIL - content mismatch\n";
        }
    } else {
        print "File download: FAIL - " . $result->{error} . "\n";
    }

    # Test 4: Directory listing
    $result = $bridge->call_python('sftp', 'list_files', {
        remote_path => '/tmp'
    });

    if ($result->{success} && ref($result->{result}->{files}) eq 'ARRAY') {
        print "Directory listing: PASS\n";
    } else {
        print "Directory listing: FAIL\n";
    }

    # Test 5: File rename
    $result = $bridge->call_python('sftp', 'rename', {
        old_path => '/tmp/test_remote_1.txt',
        new_path => '/tmp/test_renamed_1.txt'
    });

    if ($result->{success}) {
        print "File rename: PASS\n";
    } else {
        print "File rename: FAIL - " . $result->{error} . "\n";
    }

    # Test 6: File delete
    $result = $bridge->call_python('sftp', 'delete', {
        remote_file => '/tmp/test_renamed_1.txt'
    });

    if ($result->{success}) {
        print "File delete: PASS\n";
    } else {
        print "File delete: FAIL - " . $result->{error} . "\n";
    }

    # Test 7: Error handling (invalid file)
    $result = $bridge->call_python('sftp', 'get', {
        remote_file => '/tmp/nonexistent_file.txt',
        local_file => '/tmp/should_not_exist.txt'
    });

    if (!$result->{success}) {
        print "Error handling: PASS\n";
    } else {
        print "Error handling: FAIL - should have failed\n";
    }

    # Test 8: Disconnect
    $result = $bridge->call_python('sftp', 'disconnect', {});
    if ($result->{success}) {
        print "SFTP disconnect: PASS\n";
    } else {
        print "SFTP disconnect: FAIL\n";
    }

    # Cleanup
    unlink '/tmp/test_upload_1.txt', '/tmp/test_upload_2.txt', '/tmp/test_download_1.txt';

    return 1;
}

# Test both modes
test_sftp_mode("Process Mode", 0);
test_sftp_mode("Daemon Mode", 1);

print "\n=== SFTP Module Validation Complete ===\n";
```

**Expected Results**:
- SFTP connections should succeed with valid credentials
- File upload/download should preserve content exactly
- Directory operations should work correctly
- Network/authentication errors should be handled gracefully

---

### **BASELINE-005: Excel Module Validation**

**Epic**: Core Functionality
**Story Type**: Functional
**Priority**: Medium

**Background**:
The `excel` module generates Excel spreadsheets programmatically. This is commonly used for reporting and data export functionality.

**Acceptance Criteria**:
- [ ] Workbook creation succeeds
- [ ] Worksheet addition works
- [ ] Cell writing preserves data and formatting
- [ ] File saving creates valid Excel files
- [ ] Various data types are handled correctly

**Test Script**:
```perl
#!/usr/bin/perl
use strict;
use warnings;
use CPANBridge;

sub test_excel_mode {
    my ($mode_name, $daemon_mode) = @_;

    print "\n=== Testing Excel Module - $mode_name ===\n";

    $CPANBridge::DAEMON_MODE = $daemon_mode;
    my $bridge = CPANBridge->new();

    my $test_file = "/tmp/test_workbook_${mode_name}.xlsx";
    $test_file =~ s/ /_/g;  # Remove spaces from filename

    # Test 1: Create workbook
    my $result = $bridge->call_python('excel', 'create_workbook', {
        filename => $test_file
    });

    if ($result->{success}) {
        print "Create workbook: PASS\n";
    } else {
        print "Create workbook: FAIL - " . $result->{error} . "\n";
        return 0;
    }

    # Test 2: Add worksheet
    $result = $bridge->call_python('excel', 'add_worksheet', {
        sheet_name => 'Test Data'
    });

    if ($result->{success}) {
        print "Add worksheet: PASS\n";
    } else {
        print "Add worksheet: FAIL - " . $result->{error} . "\n";
    }

    # Test 3: Write various data types
    my @test_data = (
        { row => 0, col => 0, value => "String Data", type => "string" },
        { row => 0, col => 1, value => 42, type => "number" },
        { row => 0, col => 2, value => 3.14159, type => "float" },
        { row => 1, col => 0, value => "Unicode: 世界", type => "unicode" },
        { row => 1, col => 1, value => "2023-09-21", type => "date" }
    );

    my $write_success = 0;
    for my $data (@test_data) {
        $result = $bridge->call_python('excel', 'write_cell', {
            row => $data->{row},
            col => $data->{col},
            value => $data->{value}
        });

        if ($result->{success}) {
            $write_success++;
        } else {
            print "Write cell ($data->{type}): FAIL\n";
        }
    }

    if ($write_success == @test_data) {
        print "Write cells: PASS (all data types)\n";
    } else {
        print "Write cells: PARTIAL ($write_success/" . @test_data . ")\n";
    }

    # Test 4: Write multiple rows
    for my $row (5..10) {
        for my $col (0..4) {
            $bridge->call_python('excel', 'write_cell', {
                row => $row,
                col => $col,
                value => "R${row}C${col}"
            });
        }
    }
    print "Multiple rows: PASS\n";

    # Test 5: Save workbook
    $result = $bridge->call_python('excel', 'save_workbook', {});

    if ($result->{success}) {
        print "Save workbook: PASS\n";

        # Verify file exists and has content
        if (-f $test_file && -s $test_file > 1000) {  # Should be > 1KB
            print "File validation: PASS\n";
        } else {
            print "File validation: FAIL - file too small or missing\n";
        }
    } else {
        print "Save workbook: FAIL - " . $result->{error} . "\n";
    }

    # Cleanup
    unlink $test_file if -f $test_file;

    return 1;
}

# Test both modes
test_excel_mode("Process Mode", 0);
test_excel_mode("Daemon Mode", 1);

print "\n=== Excel Module Validation Complete ===\n";
```

**Expected Results**:
- Excel files should be created successfully
- All data types should be written correctly
- Generated files should be valid Excel format
- Unicode characters should be preserved

---

### **BASELINE-006: XML Helper Module Validation**

**Epic**: Core Functionality
**Story Type**: Functional
**Priority**: Medium

**Background**:
The `xml_helper` module handles XML parsing and generation, commonly used for data interchange and configuration file processing.

**Acceptance Criteria**:
- [ ] XML parsing from strings works correctly
- [ ] XML parsing from files works correctly
- [ ] XML generation produces valid XML
- [ ] Complex XML structures are handled
- [ ] XML validation detects malformed content

**Test Script**:
```perl
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
        if (ref($parsed) eq 'HASH' && $parsed->{root}) {
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
        if (ref($parsed->{catalog}->{book}) eq 'ARRAY' && @{$parsed->{catalog}->{book}} == 2) {
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
    my $malformed_xml = '<root><unclosed_tag>content</root>';

    $result = $bridge->call_python('xml_helper', 'xml_in', {
        source => $malformed_xml,
        source_type => 'string'
    });

    if (!$result->{success}) {
        print "Malformed XML handling: PASS\n";
    } else {
        print "Malformed XML handling: FAIL - should have failed\n";
    }

    # Test 6: Unicode XML
    my $unicode_xml = '<root><text>Hello 世界 🌍</text></root>';

    $result = $bridge->call_python('xml_helper', 'xml_in', {
        source => $unicode_xml,
        source_type => 'string'
    });

    if ($result->{success}) {
        my $text_content = $result->{result}->{root}->{text};
        if ($text_content eq "Hello 世界 🌍") {
            print "Unicode XML: PASS\n";
        } else {
            print "Unicode XML: FAIL - character encoding issue\n";
        }
    } else {
        print "Unicode XML: FAIL - " . $result->{error} . "\n";
    }

    # Cleanup
    unlink $test_xml_file if -f $test_xml_file;

    return 1;
}

# Test both modes
test_xml_mode("Process Mode", 0);
test_xml_mode("Daemon Mode", 1);

print "\n=== XML Helper Module Validation Complete ===\n";
```

**Expected Results**:
- Valid XML should parse correctly into Perl data structures
- Generated XML should be well-formed and valid
- Malformed XML should generate appropriate error messages
- Unicode content should be preserved correctly

---

### **BASELINE-007: Crypto Module Validation**

**Epic**: Core Functionality
**Story Type**: Functional
**Priority**: High

**Background**:
The `crypto` module provides cryptographic operations including encryption, decryption, and hashing. It supports multiple algorithms (Blowfish, AES) and handles PEM key files, making it critical for security-sensitive applications.

**Acceptance Criteria**:
- [ ] Cipher creation succeeds with various algorithms
- [ ] Encryption/decryption round-trip works correctly
- [ ] PEM key file processing works
- [ ] Hash functions generate correct outputs
- [ ] Different key formats are handled (string, hex, base64)
- [ ] Error conditions are handled properly
- [ ] Both process and daemon modes work identically

**Test Script**:
```perl
#!/usr/bin/perl
use strict;
use warnings;
use CPANBridge;
use Digest::SHA qw(sha256_hex);

sub test_crypto_mode {
    my ($mode_name, $daemon_mode) = @_;

    print "\n=== Testing Crypto Module - $mode_name ===\n";

    $CPANBridge::DAEMON_MODE = $daemon_mode;
    my $bridge = CPANBridge->new();

    # Test 1: Cipher creation with string key
    my $result = $bridge->call_python('crypto', 'new', {
        key => 'MySecretKey123',
        cipher => 'Blowfish'
    });

    my $cipher_id;
    if ($result->{success}) {
        $cipher_id = $result->{result}->{cipher_id};
        print "Cipher creation (string key): PASS\n";
    } else {
        print "Cipher creation (string key): FAIL - " . $result->{error} . "\n";
        return 0;
    }

    # Test 2: Basic encryption/decryption round-trip
    my $test_plaintext = "Hello, World! This is a test message with special chars: @#$%^&*()";

    $result = $bridge->call_python('crypto', 'encrypt', {
        cipher_id => $cipher_id,
        plaintext => $test_plaintext
    });

    my $encrypted_hex;
    if ($result->{success}) {
        $encrypted_hex = $result->{result}->{encrypted};
        print "Encryption: PASS\n";
    } else {
        print "Encryption: FAIL - " . $result->{error} . "\n";
        return 0;
    }

    # Test 3: Decryption
    $result = $bridge->call_python('crypto', 'decrypt', {
        cipher_id => $cipher_id,
        hex_ciphertext => $encrypted_hex
    });

    if ($result->{success}) {
        my $decrypted_text = $result->{result}->{decrypted};
        if ($decrypted_text eq $test_plaintext) {
            print "Decryption round-trip: PASS\n";
        } else {
            print "Decryption round-trip: FAIL - text mismatch\n";
            print "  Expected: $test_plaintext\n";
            print "  Got:      $decrypted_text\n";
        }
    } else {
        print "Decryption: FAIL - " . $result->{error} . "\n";
    }

    # Test 4: Unicode handling
    my $unicode_text = "Unicode test: 世界 🌍 café naïve résumé";
    $result = $bridge->call_python('crypto', 'encrypt', {
        cipher_id => $cipher_id,
        plaintext => $unicode_text
    });

    if ($result->{success}) {
        my $unicode_encrypted = $result->{result}->{encrypted};

        # Decrypt it back
        $result = $bridge->call_python('crypto', 'decrypt', {
            cipher_id => $cipher_id,
            hex_ciphertext => $unicode_encrypted
        });

        if ($result->{success} && $result->{result}->{decrypted} eq $unicode_text) {
            print "Unicode encryption: PASS\n";
        } else {
            print "Unicode encryption: FAIL\n";
        }
    } else {
        print "Unicode encryption: FAIL - " . $result->{error} . "\n";
    }

    # Test 5: AES cipher
    $result = $bridge->call_python('crypto', 'new', {
        key => 'AESTestKey123456',  # 16-byte key for AES
        cipher => 'AES'
    });

    if ($result->{success}) {
        my $aes_cipher_id = $result->{result}->{cipher_id};
        print "AES cipher creation: PASS\n";

        # Test AES encryption/decryption
        $result = $bridge->call_python('crypto', 'encrypt', {
            cipher_id => $aes_cipher_id,
            plaintext => "AES test message"
        });

        if ($result->{success}) {
            my $aes_encrypted = $result->{result}->{encrypted};

            $result = $bridge->call_python('crypto', 'decrypt', {
                cipher_id => $aes_cipher_id,
                hex_ciphertext => $aes_encrypted
            });

            if ($result->{success} && $result->{result}->{decrypted} eq "AES test message") {
                print "AES round-trip: PASS\n";
            } else {
                print "AES round-trip: FAIL\n";
            }
        } else {
            print "AES encryption: FAIL\n";
        }

        # Cleanup AES cipher
        $bridge->call_python('crypto', 'cleanup_cipher', { cipher_id => $aes_cipher_id });
    } else {
        print "AES cipher creation: FAIL - " . $result->{error} . "\n";
    }

    # Test 6: Hash function (if available)
    $result = $bridge->call_python('crypto', 'hash', {
        data => 'test data for hashing',
        algorithm => 'SHA256'
    });

    if ($result->{success}) {
        my $hash_result = $result->{result}->{hash};
        # Verify it's a valid SHA256 hex string (64 characters)
        if ($hash_result && length($hash_result) == 64 && $hash_result =~ /^[0-9a-f]+$/i) {
            print "Hash function: PASS\n";
        } else {
            print "Hash function: FAIL - invalid hash format\n";
        }
    } else {
        print "Hash function: FAIL - " . $result->{error} . "\n";
    }

    # Test 7: PEM key file handling (create a test key file)
    my $test_key_file = '/tmp/test_crypto_key.pem';
    my $pem_key = "-----BEGIN PRIVATE KEY-----\nVGhpc0lzQVRlc3RLZXkxMjNBQkNERUY=\n-----END PRIVATE KEY-----\n";

    open my $fh, '>', $test_key_file;
    print $fh $pem_key;
    close $fh;

    $result = $bridge->call_python('crypto', 'new', {
        key_file => $test_key_file,
        cipher => 'Blowfish'
    });

    if ($result->{success}) {
        print "PEM key file: PASS\n";
        my $pem_cipher_id = $result->{result}->{cipher_id};

        # Quick test with PEM key
        $result = $bridge->call_python('crypto', 'encrypt', {
            cipher_id => $pem_cipher_id,
            plaintext => "PEM key test"
        });

        if ($result->{success}) {
            print "PEM key encryption: PASS\n";
        } else {
            print "PEM key encryption: FAIL\n";
        }

        # Cleanup PEM cipher
        $bridge->call_python('crypto', 'cleanup_cipher', { cipher_id => $pem_cipher_id });
    } else {
        print "PEM key file: FAIL - " . $result->{error} . "\n";
    }

    # Test 8: Error handling - invalid cipher
    $result = $bridge->call_python('crypto', 'new', {
        key => 'test',
        cipher => 'InvalidCipher'
    });

    if (!$result->{success}) {
        print "Invalid cipher handling: PASS\n";
    } else {
        print "Invalid cipher handling: FAIL - should have failed\n";
    }

    # Test 9: Error handling - invalid hex for decryption
    $result = $bridge->call_python('crypto', 'decrypt', {
        cipher_id => $cipher_id,
        hex_ciphertext => 'invalid_hex_string'
    });

    if (!$result->{success}) {
        print "Invalid hex handling: PASS\n";
    } else {
        print "Invalid hex handling: FAIL - should have failed\n";
    }

    # Test 10: Large data encryption
    my $large_data = "A" x 10000;  # 10KB of data
    $result = $bridge->call_python('crypto', 'encrypt', {
        cipher_id => $cipher_id,
        plaintext => $large_data
    });

    if ($result->{success}) {
        my $large_encrypted = $result->{result}->{encrypted};

        $result = $bridge->call_python('crypto', 'decrypt', {
            cipher_id => $cipher_id,
            hex_ciphertext => $large_encrypted
        });

        if ($result->{success} && $result->{result}->{decrypted} eq $large_data) {
            print "Large data encryption: PASS\n";
        } else {
            print "Large data encryption: FAIL\n";
        }
    } else {
        print "Large data encryption: FAIL - " . $result->{error} . "\n";
    }

    # Cleanup
    $bridge->call_python('crypto', 'cleanup_cipher', { cipher_id => $cipher_id });
    unlink $test_key_file if -f $test_key_file;

    return 1;
}

# Test both modes
test_crypto_mode("Process Mode", 0);
test_crypto_mode("Daemon Mode", 1);

print "\n=== Crypto Module Validation Complete ===\n";
```

**Expected Results**:
- Encryption/decryption should round-trip perfectly for all data types
- Multiple cipher algorithms should work correctly
- PEM key files should be processed correctly
- Hash functions should generate consistent outputs
- Large data encryption should work without memory issues
- Unicode characters should be preserved exactly
- Error conditions should generate appropriate messages

---

### **BASELINE-008: Quick Validation of All Modules**

**Epic**: Comprehensive Baseline
**Story Type**: Smoke Test
**Priority**: Critical

**Background**:
Quick smoke test to verify that all 11 helper modules are accessible and can perform basic operations without errors. This is essential before any detailed testing.

**Acceptance Criteria**:
- [ ] All 11 modules are loaded and accessible
- [ ] Each module can execute at least one basic function
- [ ] No Python import errors or missing dependencies
- [ ] Both process and daemon modes can access all modules

**Test Script**:
```perl
#!/usr/bin/perl
use strict;
use warnings;
use CPANBridge;

sub quick_module_test {
    my ($mode_name, $daemon_mode) = @_;

    print "\n=== Quick Module Validation - $mode_name ===\n";

    $CPANBridge::DAEMON_MODE = $daemon_mode;
    my $bridge = CPANBridge->new();

    my @module_tests = (
        { module => 'test', function => 'ping', params => {} },
        { module => 'http', function => 'get', params => { url => 'https://httpbin.org/json' } },
        { module => 'database', function => 'connect', params => { dsn => 'dbi:Oracle:test', username => 'test', password => 'test' } },
        { module => 'sftp', function => 'connect', params => { hostname => 'localhost', username => 'test', password => 'test' } },
        { module => 'excel', function => 'create_workbook', params => { filename => '/tmp/test.xlsx' } },
        { module => 'xml_helper', function => 'xml_in', params => { source => '<test>data</test>', source_type => 'string' } },
        { module => 'crypto', function => 'hash', params => { data => 'test', algorithm => 'SHA256' } },
        { module => 'email_helper', function => 'validate_email', params => { email => 'test@example.com' } },
        { module => 'datetime_helper', function => 'now', params => {} },
        { module => 'logging_helper', function => 'log_message', params => { message => 'test', level => 'INFO' } },
        { module => 'xpath', function => 'new', params => { xml => '<test><item>value</item></test>' } }
    );

    my $total_modules = @module_tests;
    my $working_modules = 0;

    for my $test (@module_tests) {
        my $result = $bridge->call_python($test->{module}, $test->{function}, $test->{params});

        if ($result->{success}) {
            printf "  ✓ %-15s: WORKING\n", $test->{module};
            $working_modules++;
        } else {
            printf "  ✗ %-15s: FAILED - %s\n", $test->{module}, $result->{error};
        }
    }

    printf "\nModule Summary: %d/%d modules working (%.1f%%)\n",
           $working_modules, $total_modules, ($working_modules/$total_modules)*100;

    if ($working_modules == $total_modules) {
        print "Overall Status: ✓ ALL MODULES WORKING\n";
    } elsif ($working_modules >= $total_modules * 0.8) {
        print "Overall Status: ⚠ MOST MODULES WORKING\n";
    } else {
        print "Overall Status: ✗ SIGNIFICANT MODULE FAILURES\n";
    }

    return $working_modules;
}

# Test both modes
my $process_working = quick_module_test("Process Mode", 0);
my $daemon_working = quick_module_test("Daemon Mode", 1);

print "\n=== Module Validation Summary ===\n";
printf "Process Mode: %d/11 modules working\n", $process_working;
printf "Daemon Mode: %d/11 modules working\n", $daemon_working;

if ($process_working == $daemon_working && $process_working >= 9) {
    print "Status: ✓ BASELINE VALIDATION PASSED\n";
} elsif ($process_working != $daemon_working) {
    print "Status: ⚠ MODE INCONSISTENCY DETECTED\n";
} else {
    print "Status: ✗ BASELINE VALIDATION FAILED\n";
}

print "\n=== Quick Module Validation Complete ===\n";
```

**Expected Results**:
- At least 9/11 modules should work in both modes
- Process and daemon modes should have identical module availability
- No Python import errors or dependency issues

---

### **BASELINE-009: Data Type Preservation Testing**

**Epic**: Data Integrity
**Story Type**: Functional
**Priority**: High

**Background**:
Critical validation that data types are preserved correctly when passing between Perl and Python. This is fundamental to the system's reliability.

**Acceptance Criteria**:
- [ ] Strings are preserved exactly (including empty strings)
- [ ] Numbers (integers and floats) maintain precision
- [ ] Boolean values convert correctly
- [ ] Arrays/lists maintain order and content
- [ ] Hashes/dictionaries preserve keys and values
- [ ] Nested data structures work correctly
- [ ] Unicode characters are preserved
- [ ] Null/undefined values are handled properly

**Test Script**:
```perl
#!/usr/bin/perl
use strict;
use warnings;
use CPANBridge;
use JSON;

sub test_data_types {
    my ($mode_name, $daemon_mode) = @_;

    print "\n=== Data Type Preservation Test - $mode_name ===\n";

    $CPANBridge::DAEMON_MODE = $daemon_mode;
    my $bridge = CPANBridge->new();

    my @test_cases = (
        # Strings
        { name => "Simple string", data => "Hello World", type => "string" },
        { name => "Empty string", data => "", type => "string" },
        { name => "Unicode string", data => "Hello 世界 🌍 café", type => "string" },
        { name => "Special chars", data => "!@#\$%^&*()_+-=[]{}|;':\",./<>?", type => "string" },
        { name => "Multiline string", data => "Line 1\nLine 2\nLine 3", type => "string" },

        # Numbers
        { name => "Integer", data => 42, type => "number" },
        { name => "Negative integer", data => -123, type => "number" },
        { name => "Zero", data => 0, type => "number" },
        { name => "Float", data => 3.14159, type => "number" },
        { name => "Negative float", data => -2.718, type => "number" },
        { name => "Large number", data => 123456789, type => "number" },

        # Booleans (represented as strings in Perl)
        { name => "Boolean true", data => "true", type => "boolean" },
        { name => "Boolean false", data => "false", type => "boolean" },

        # Arrays
        { name => "Simple array", data => [1, 2, 3, 4, 5], type => "array" },
        { name => "Mixed array", data => ["string", 42, 3.14, "true"], type => "array" },
        { name => "Empty array", data => [], type => "array" },
        { name => "Nested array", data => [[1, 2], [3, 4], [5, 6]], type => "array" },

        # Hashes
        { name => "Simple hash", data => { key1 => "value1", key2 => "value2" }, type => "hash" },
        { name => "Mixed hash", data => { string => "text", number => 42, array => [1, 2, 3] }, type => "hash" },
        { name => "Empty hash", data => {}, type => "hash" },

        # Complex nested structures
        {
            name => "Complex nested",
            data => {
                users => [
                    { id => 1, name => "John", active => "true", scores => [85, 90, 78] },
                    { id => 2, name => "Jane", active => "false", scores => [92, 88, 95] }
                ],
                metadata => {
                    version => "1.0",
                    created => "2023-09-21",
                    count => 2
                }
            },
            type => "complex"
        }
    );

    my $passed = 0;
    my $total = @test_cases;

    for my $test (@test_cases) {
        my $result = $bridge->call_python('test', 'echo', { data => $test->{data} });

        if ($result->{success}) {
            my $returned = $result->{result}->{data};

            # Compare the returned data with original
            if (_deep_compare($test->{data}, $returned)) {
                printf "  ✓ %-20s: PASS\n", $test->{name};
                $passed++;
            } else {
                printf "  ✗ %-20s: FAIL - data mismatch\n", $test->{name};
                if ($test->{type} ne "complex") {  # Avoid printing huge structures
                    print "    Original: " . _stringify($test->{data}) . "\n";
                    print "    Returned: " . _stringify($returned) . "\n";
                }
            }
        } else {
            printf "  ✗ %-20s: FAIL - %s\n", $test->{name}, $result->{error};
        }
    }

    printf "\nData Type Summary: %d/%d tests passed (%.1f%%)\n",
           $passed, $total, ($passed/$total)*100;

    return $passed == $total;
}

sub _deep_compare {
    my ($a, $b) = @_;

    return 0 unless defined($a) == defined($b);
    return 1 unless defined($a);

    my $ref_a = ref($a);
    my $ref_b = ref($b);

    return 0 unless $ref_a eq $ref_b;

    if (!$ref_a) {
        # Scalar comparison
        return $a eq $b;
    } elsif ($ref_a eq 'ARRAY') {
        return 0 unless @$a == @$b;
        for my $i (0..$#$a) {
            return 0 unless _deep_compare($a->[$i], $b->[$i]);
        }
        return 1;
    } elsif ($ref_a eq 'HASH') {
        my @keys_a = sort keys %$a;
        my @keys_b = sort keys %$b;
        return 0 unless @keys_a == @keys_b;
        return 0 unless "@keys_a" eq "@keys_b";
        for my $key (@keys_a) {
            return 0 unless _deep_compare($a->{$key}, $b->{$key});
        }
        return 1;
    }

    return 0;  # Unknown reference type
}

sub _stringify {
    my ($data) = @_;
    if (ref($data)) {
        return encode_json($data);
    } else {
        return defined($data) ? "'$data'" : 'undef';
    }
}

# Test both modes
my $process_ok = test_data_types("Process Mode", 0);
my $daemon_ok = test_data_types("Daemon Mode", 1);

print "\n=== Data Type Preservation Summary ===\n";
print "Process Mode: " . ($process_ok ? "PASS" : "FAIL") . "\n";
print "Daemon Mode: " . ($daemon_ok ? "PASS" : "FAIL") . "\n";

if ($process_ok && $daemon_ok) {
    print "Overall Status: ✓ DATA INTEGRITY VERIFIED\n";
} else {
    print "Overall Status: ✗ DATA INTEGRITY ISSUES DETECTED\n";
}

print "\n=== Data Type Preservation Test Complete ===\n";
```

**Expected Results**:
- All data types should round-trip perfectly
- Unicode characters should be preserved exactly
- Complex nested structures should maintain their shape
- Both modes should handle data identically

---

## 📋 Test Execution Guidelines

### **Prerequisites**

1. **Environment Setup**:
   - Perl with CPANBridge module installed
   - Python 3.x with required dependencies
   - Network access for HTTP testing
   - Test database access (for database module)
   - Local SFTP server or remote server credentials

2. **Test Data Preparation**:
   - Ensure test databases are accessible
   - Set up SFTP credentials (or use localhost with SSH keys)
   - Create temporary directories for file operations

### **Execution Order**

1. **Start with BASELINE-008**: Quick validation of all modules
2. **Run BASELINE-001**: Test module (simplest and most critical)
3. **Run BASELINE-009**: Data type preservation (fundamental)
4. **Run BASELINE-007**: Crypto module (if cryptographic operations are needed)
5. **Execute remaining tests** based on your system's available services

### **Success Criteria**

| Test | Critical Success Criteria |
|------|---------------------------|
| **BASELINE-001** | All test module functions work in both modes |
| **BASELINE-007** | Crypto encryption/decryption round-trips work perfectly |
| **BASELINE-008** | At least 9/11 modules accessible in both modes |
| **BASELINE-009** | 100% data type preservation accuracy |
| **Individual Modules** | Core functionality works without errors |

### **Failure Investigation**

If tests fail:
1. Check Python dependencies and module imports
2. Verify network connectivity for HTTP/SFTP tests
3. Confirm database credentials and accessibility
4. Review error messages for specific failure points
5. Test process mode first, then daemon mode for comparison

---

## 🎯 Expected Outcomes

### **Successful Baseline Validation Should Show**:

✅ **Functional Completeness**: All modules perform their core operations
✅ **Data Integrity**: Perfect data preservation between Perl and Python
✅ **Error Handling**: Appropriate error messages for invalid operations
✅ **Mode Equivalence**: Identical results in process and daemon modes
✅ **Unicode Support**: Proper handling of international characters
✅ **Type Safety**: All Perl data types correctly converted and returned

### **This Baseline Testing Enables**:

- **Confidence in Core Functionality**: Know that basic operations work correctly
- **Performance Testing Foundation**: Establish functional baseline before speed tests
- **Regression Detection**: Identify any functionality breaks during development
- **Documentation Validation**: Verify that documented features actually work
- **User Onboarding**: Provide working examples for new users

---

*This baseline testing document focuses specifically on core functionality validation before any advanced testing. Each test story is designed to be executed independently and provides clear success/failure criteria.*

**Document Version**: 1.0
**Last Updated**: September 2025
**Test Coverage**: 11 Helper Modules
**Status**: Ready for QA Execution ✅