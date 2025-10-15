# HTTPHelper Testing Guide

## Overview

This guide documents the comprehensive test suite for HTTPHelper, which validates compatibility with all documented LWP::UserAgent and WWW::Mechanize usage patterns from the enterprise Perl codebase.

## Test Suite: test_http_comprehensive.pl

**Location**: `/Users/shubhamdixit/Perl_to_Python/Test_Scripts/test_http_comprehensive.pl`

**Purpose**: Validate HTTPHelper against all patterns documented in `LWP_UserAgent&WWW_Mechanize_UsageAnalysis.md`

### Test Coverage Summary

| Category | Tests | Description |
|----------|-------|-------------|
| LWP::UserAgent Object Creation | 4 | Basic instantiation, agent string, timeout, defaults |
| HTTP::Request Operations | 4 | POST/GET creation, content-type, content setting |
| HTTP Request Execution | 2 | Execute via request() method |
| Direct HTTP Methods | 3 | Direct get() and post() methods |
| Response Handling | 6 | is_success, content, status_line, code, message |
| Error Handling | 4 | HTTP 4xx/5xx, timeouts, error patterns |
| WWW::Mechanize | 5 | Object creation, get(), status(), autocheck |
| SSL/HTTPS Support | 3 | HTTPS GET/POST, SSL via HTTP::Request |
| Form-Encoded POST | 3 | Standard forms, special chars, complex data |
| Advanced Features | 5 | Headers, User-Agent, JSON, HTTP methods |
| Real-World Patterns | 5 | Job starter, HPSM, WebSphere, RESTful, dynamic methods |
| **TOTAL** | **44** | **Complete coverage of documented patterns** |

---

## Running the Tests

### Basic Execution

```bash
cd /Users/shubhamdixit/Perl_to_Python
perl Test_Scripts/test_http_comprehensive.pl
```

### With Verbose Output

```bash
export TEST_VERBOSE=1
perl Test_Scripts/test_http_comprehensive.pl
```

### With Custom Test Host

```bash
export HTTP_TEST_HOST=httpbin.org
perl Test_Scripts/test_http_comprehensive.pl
```

### Expected Output

```
================================================================================
HTTPHelper Comprehensive Test Suite
================================================================================
Test Host: httpbin.org
Test Start: Wed Oct 15 12:00:00 2025

────────────────────────────────────────────────────────────────────────────────
Test 1: LWP::UserAgent - Basic instantiation
────────────────────────────────────────────────────────────────────────────────
✓ PASS

[... 43 more tests ...]

================================================================================
Test Summary
================================================================================
Total Tests:  44
Passed:       44 (100.0%)
Failed:       0
Test End:     Wed Oct 15 12:05:00 2025

================================================================================
✓ ALL TESTS PASSED - HTTPHelper is production ready!
================================================================================
```

---

## Test Sections Detail

### SECTION 1: LWP::UserAgent Object Creation (Pattern 1)

**Documentation Reference**: 30166mi_job_starter.pl, mi_job_starter.pl

**Tests**:
1. **Basic instantiation** - `new LWP::UserAgent`
   - Validates object creation
   - Checks default timeout (180 seconds)

2. **Agent string customization** - `$ua->agent("Custom")`
   - Tests default agent string
   - Tests custom agent prefix pattern

3. **Timeout configuration** - `$ua->timeout(30)`
   - Validates timeout getter/setter
   - Tests job starter timeout (180s)

4. **Direct instantiation with defaults** - `LWP::UserAgent->new`
   - Tests constructor with no parameters
   - Validates default values

**Why Important**: These are the most common initialization patterns across all scripts.

---

### SECTION 2: HTTP::Request Object Creation

**Documentation Reference**: 30166mi_job_starter.pl, mi_job_starter.pl

**Tests**:
1. **POST object creation** - `new HTTP::Request POST => $URL`
2. **Content-Type setting** - `$req->content_type('application/x-www-form-urlencoded')`
3. **Content setting** - `$req->content($data)`
4. **GET object creation** - `new HTTP::Request GET => $URL`

**Why Important**: Primary pattern for Java Servlet communication.

---

### SECTION 3: HTTP Request Execution

**Documentation Reference**: All documented scripts

**Tests**:
1. **Execute POST via HTTP::Request** - Full request cycle
   - Creates POST request
   - Sets content-type and content
   - Executes via `$ua->request($req)`
   - Validates response

2. **Execute GET via HTTP::Request** - GET request cycle

**Why Important**: Main execution pattern in job starter scripts.

---

### SECTION 4: Direct HTTP Methods

**Documentation Reference**: HpsmTicket.pm, general usage

**Tests**:
1. **Direct GET** - `$ua->get($url)`
2. **Direct POST with hashref** - `$ua->post($url, \%data)` (HpsmTicket.pm pattern)
3. **Direct POST with parameters** - `$ua->post($url, Content => ...)`

**Why Important**: Simplified API used in HP Service Manager integration.

---

### SECTION 5: Response Handling

**Documentation Reference**: All scripts

**Tests**:
1. **is_success()** - Tests 200 (success) and 404 (failure)
2. **content()** - Extract response body
3. **decoded_content()** - Get decoded response
4. **status_line()** - Get full status line
5. **code()** - Get status code
6. **message()** - Get reason phrase

**Why Important**: Critical for error handling and response processing.

---

### SECTION 6: Error Handling

**Documentation Reference**: Section 8 of usage analysis

**Tests**:
1. **HTTP 4xx errors** - 404 Not Found
2. **HTTP 5xx errors** - 500 Internal Server Error
3. **Timeout configuration** - Validate timeout behavior
4. **Documentation error pattern** - `if (!$response->is_success)`

**Why Important**: Robust error handling required for production reliability.

---

### SECTION 7: WWW::Mechanize Compatibility

**Documentation Reference**: 30165CbiWasCtl.pl

**Tests**:
1. **Object creation** - `WWW::Mechanize->new(agent => "Mozilla/6.0", autocheck => 0)`
2. **get() method** - `$mech->get($url)`
3. **status() method** - `$mech->status()`
4. **autocheck = 0 behavior** - No exception on errors
5. **WebSphere monitoring pattern** - Complete health check workflow

**Why Important**: Used for WebSphere Application Server monitoring.

---

### SECTION 8: SSL/HTTPS Support

**Documentation Reference**: HpsmTicket.pm, general usage

**Tests**:
1. **HTTPS GET** - `$ua->get("https://...")`
2. **HTTPS POST** - `$ua->post("https://...", \%data)`
3. **HTTPS via HTTP::Request** - Full request cycle over HTTPS

**Why Important**: Required for HP Service Manager eHub integration.

---

### SECTION 9: Form-Encoded POST

**Documentation Reference**: Primary pattern across all scripts

**Tests**:
1. **Standard form-encoded POST** - `application/x-www-form-urlencoded`
2. **Special characters** - Spaces, ampersands, equals signs
3. **Complex form data** - Multi-parameter forms

**Why Important**: Main data transmission method to Java Servlets.

---

### SECTION 10: Advanced Features

**Tests**:
1. **Multiple headers** - Custom headers via `$req->header()`
2. **User-Agent propagation** - Verify custom agent in requests
3. **JSON response handling** - Parse JSON with JSON::PP
4. **HTTP method variations** - GET, POST, etc.
5. **Empty content POST** - Edge case handling

**Why Important**: Advanced use cases and edge cases.

---

### SECTION 11: Real-World Usage Patterns

**Critical Integration Tests**

#### Test 1: Job Starter Pattern (30166mi_job_starter.pl)
```perl
my $user_agent = new LWP::UserAgent;
$user_agent->agent("JobStarter/0.1 " . $user_agent->agent);
$user_agent->timeout(180);

my $web_request = new HTTP::Request POST => $URL;
$web_request->content_type('application/x-www-form-urlencoded');
$web_request->content($content_string);

my $response = $user_agent->request($web_request);
```
**Purpose**: Validates WebLogic Server Java Servlet integration

#### Test 2: HP Service Manager Pattern (HpsmTicket.pm)
```perl
my $user_agent = LWP::UserAgent->new;
my %postData = (ticket_id => 'INC12345', ...);
my $response = $user_agent->post($HTTPS_URL, \%postData);
```
**Purpose**: Validates HTTPS POST with form data for ticket creation

#### Test 3: WebSphere Monitoring Pattern (30165CbiWasCtl.pl)
```perl
my $mech = WWW::Mechanize->new(agent => "Mozilla/6.0", autocheck => 0);
$mech->get($wls_url);
my $status = $mech->status();
# Check if 404 (running) or 502 (down)
```
**Purpose**: Validates WebSphere Application Server health monitoring

#### Test 4: RESTful URL Handling
```perl
my $URL = "$base_url$resource/$restfiletype";
my $response = $user_agent->get($URL);
```
**Purpose**: Validates RESTful API patterns

#### Test 5: Dynamic HTTP Method Selection
```perl
my $http_method = 'POST';  # From command line
my $web_request = new HTTP::Request $http_method => $URL;
```
**Purpose**: Validates command-line driven HTTP method selection

**Why Important**: These tests validate exact production usage patterns.

---

## Test Dependencies

### Required Modules
- **HTTPHelper.pm** - Main module being tested
- **CPANBridge.pm** - Bridge infrastructure
- **JSON::PP** - JSON parsing (standard library)
- **Data::Dumper** - Debug output (standard library)

### Required Python Backend
- **python_helpers/cpan_daemon.py** - Python daemon
- **python_helpers/helpers/http_helper.py** - HTTP backend implementation

### External Services
- **httpbin.org** - HTTP testing service (default)
  - Provides endpoints: /get, /post, /status/:code, /delay/:n, /html, /json, /headers, /user-agent
  - Supports both HTTP and HTTPS
  - Free, no authentication required

### Alternative Test Hosts
You can use any HTTP testing service:
```bash
export HTTP_TEST_HOST=postman-echo.com
export HTTP_TEST_HOST=reqres.in
```

---

## Test Assertions

### Available Assertion Functions

#### assert($condition, $message)
Checks if condition is true
```perl
assert(defined $obj, "Object is defined");
```

#### assert_equals($actual, $expected, $message)
Checks if values are equal
```perl
assert_equals($response->code(), 200, "Status is 200");
```

#### assert_contains($haystack, $needle, $message)
Checks if string contains substring
```perl
assert_contains($content, "param1", "Response contains param1");
```

#### assert_status_code($response, $expected, $message)
Checks HTTP status code
```perl
assert_status_code($response, 200, "Request successful");
```

---

## Troubleshooting

### All Tests Failing

**Problem**: All tests fail immediately

**Possible Causes**:
1. Python daemon not running
2. HTTPHelper.pm not in library path
3. Python backend missing

**Solution**:
```bash
# Check if daemon is running
ps aux | grep cpan_daemon

# Verify library path
export PERL5LIB=/Users/shubhamdixit/Perl_to_Python:$PERL5LIB

# Test Python backend directly
python3 python_helpers/helpers/http_helper.py
```

---

### Network-Related Failures

**Problem**: Tests fail with connection errors

**Possible Causes**:
1. No internet connection
2. Firewall blocking httpbin.org
3. DNS resolution issues

**Solution**:
```bash
# Test connectivity
curl http://httpbin.org/get

# Use different test host
export HTTP_TEST_HOST=postman-echo.com
```

---

### SSL/HTTPS Test Failures

**Problem**: HTTPS tests fail with SSL errors

**Possible Causes**:
1. SSL certificate issues
2. Corporate proxy/firewall
3. Python SSL module issues

**Solution**:
```bash
# Disable SSL verification for testing (not recommended for production)
export PERL_LWP_SSL_VERIFY_HOSTNAME=0

# Test SSL directly
curl -v https://httpbin.org/get
```

---

### Timeout Test Failures

**Problem**: Timeout tests fail or hang

**Possible Causes**:
1. Network latency
2. Test host too slow
3. Timeout values too short

**Solution**:
Increase timeout in test if needed, or skip timeout tests if network is slow.

---

## Test Maintenance

### Adding New Tests

1. Add test to appropriate section
2. Use `run_test()` wrapper
3. Include documentation reference
4. Use assertion functions
5. Return 1 on success

Example:
```perl
run_test("New Feature - Description", sub {
    my $user_agent = new LWP::UserAgent;
    my $response = $user_agent->get("http://$TEST_HOST/get");

    assert($response->is_success, "Request successful");
    assert_status_code($response, 200, "Status is 200");

    return 1;
});
```

---

### Updating Tests for New Patterns

When new usage patterns are discovered:

1. Document pattern in usage analysis
2. Update compatibility report
3. Add test to comprehensive suite
4. Assign to appropriate section
5. Include real-world context

---

## Performance Testing

### Response Time Testing

Currently not included, but can be added:

```perl
use Time::HiRes qw(time);

run_test("Performance - Response time", sub {
    my $user_agent = new LWP::UserAgent;

    my $start = time();
    my $response = $user_agent->get("http://$TEST_HOST/get");
    my $elapsed = time() - $start;

    assert($response->is_success, "Request successful");
    assert($elapsed < 5.0, "Response time under 5 seconds");

    print "  Response time: " . sprintf("%.3f", $elapsed) . "s\n";

    return 1;
});
```

---

## Integration Testing

### Testing with Real Services

For production validation, test against actual services:

```bash
# Test with real WebLogic servlet
export HTTP_TEST_HOST=weblogic.example.com:7001
export TEST_SERVLET=/myapp/servlet

# Test with real HP Service Manager
export HTTP_TEST_HOST=hpsm.example.com
export TEST_HTTPS=1
```

**Note**: Be careful with production systems. Use test/UAT environments when available.

---

## Continuous Integration

### CI/CD Integration

Example GitHub Actions workflow:

```yaml
name: HTTPHelper Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2

      - name: Install Perl
        run: sudo apt-get install -y perl

      - name: Install Python
        uses: actions/setup-python@v2
        with:
          python-version: '3.9'

      - name: Run HTTP tests
        run: |
          cd /Users/shubhamdixit/Perl_to_Python
          perl Test_Scripts/test_http_comprehensive.pl
```

---

## Test Results Interpretation

### Success Criteria

**All Tests Pass (44/44)**: HTTPHelper is production ready ✅
- All documented patterns work correctly
- Error handling is robust
- SSL/HTTPS support is functional
- Real-world patterns validated

**Partial Pass (e.g., 40-43/44)**: Investigate failures
- Minor issues may need fixing
- Some edge cases may not be covered
- Review failed test details

**Many Failures (<40/44)**: Major issues
- Core functionality broken
- Backend not working correctly
- Requires immediate attention

---

## Documentation References

### Related Documents
- **Usage Analysis**: `Documentation/LWP_UserAgent&WWW_Mechanize_UsageAnalysis.md`
- **Compatibility Report**: `Documentation/HTTPHelper_Compatibility_Report.md`
- **HTTPHelper Source**: `HTTPHelper.pm`
- **Python Backend**: `python_helpers/helpers/http_helper.py`

### External References
- LWP::UserAgent documentation: https://metacpan.org/pod/LWP::UserAgent
- WWW::Mechanize documentation: https://metacpan.org/pod/WWW::Mechanize
- httpbin.org documentation: https://httpbin.org/

---

## Summary

This comprehensive test suite provides:

- ✅ **44 tests** covering all documented patterns
- ✅ **12 test sections** organized by feature area
- ✅ **5 real-world patterns** from production scripts
- ✅ **100% coverage** of usage analysis requirements
- ✅ **Production validation** for all three use cases:
  - Java Servlet communication (Job Starter)
  - HP Service Manager integration (HPSM Ticket)
  - WebSphere monitoring (WAS Control)

**Status**: Ready for production testing and validation.

---

**Last Updated**: 2025-10-15
**Test Suite Version**: 1.0
**Maintainer**: Enterprise Perl to Python Migration Team
