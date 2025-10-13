# LWP::UserAgent and WWW::Mechanize Usage Analysis Report



## Executive Summary



This report analyzes the usage of LWP::UserAgent and WWW::Mechanize modules across the Perl codebase for migration to Python backend implementations. The analysis covers 6 files that use these HTTP client modules.



## 1. Files Using These Modules



### LWP::UserAgent Usage:

- **30166mi_job_starter.pl** - HTTP POST/GET requests to Java Servlets

- **mi_job_starter.pl** - HTTP POST/GET requests to Java Servlets (duplicate/similar functionality)

- **HpsmTicket.pm** - HTTPS POST requests to HP Service Manager eHub service

- **https://lnkd.in/ehBXKS4D** - Contains import but minimal usage detected

- **https://lnkd.in/eGk3Wsje** - Contains import but minimal usage detected



### WWW::Mechanize Usage:

- **30165CbiWasCtl.pl** - Web scraping for WebSphere Application Server status checks



## 2. Import Patterns



### LWP::UserAgent Imports:

```perl

# Standard import pattern (all files)

use LWP::UserAgent;



# Associated modules typically imported together:

use HTTP::Request;   # For creating request objects

use Crypt::SSLeay;   # For HTTPS support (in HpsmTicket.pm)

```



### WWW::Mechanize Imports:

```perl

# Standard import pattern

use WWW::Mechanize;

```



## 3. Object Creation Patterns



### LWP::UserAgent Object Creation:



#### Pattern 1 - Basic instantiation (30166mi_job_starter.pl, mi_job_starter.pl):

```perl

$user_agent = new LWP::UserAgent;

$user_agent->agent("AgentName/0.1 " . $user_agent->agent);

$user_agent->timeout($timeout); # typically 180 seconds

```



#### Pattern 2 - Direct instantiation (HpsmTicket.pm):

```perl

my $user_agent = LWP::UserAgent->new;

# No custom configuration - uses defaults

```



### WWW::Mechanize Object Creation:



#### Pattern 1 - Custom user agent (30165CbiWasCtl.pl):

```perl

my $mech = WWW::Mechanize->new(agent => "Mozilla/6.0", autocheck => 0);

```


## 4. HTTP Methods Used



### LWP::UserAgent HTTP Operations:



#### POST Requests (Primary pattern):

```perl

# Create POST request

$web_request = new HTTP::Request POST => $URL;

$web_request->content_type('application/x-www-form-urlencoded');

$web_request->content($content_string);



# Execute request

my $response = $user_agent->request($web_request);

```



#### GET Requests (Alternative pattern):

```perl

# Create GET request

$web_request = new HTTP::Request GET => $URL;

my $response = $user_agent->request($web_request);

```



#### HTTPS POST (HpsmTicket.pm):

```perl

# HTTPS POST with form data

my $response = $user_agent->post($URL, \%postData);

```



### WWW::Mechanize HTTP Operations:



#### GET Requests for Status Checking:

```perl

$mech->get("$wls_url");

return $mech->status(); # Returns HTTP status code

```



## 5. Request Configuration



### Common Configuration Parameters:



#### Timeouts:

- **Default timeout**: 180 seconds (3 minutes)

- **Configurable**: Via command line parameter `-timeout`

- **Usage**: `$user_agent->timeout($timeout);`



#### User-Agent Strings:

- **Job Starter scripts**: "AgentName/0.1" + default LWP agent

- **WWW::Mechanize**: "Mozilla/6.0" (browser impersonation)



#### Content Types:

- **Primary**: `application/x-www-form-urlencoded`

- **HTTPS requests**: Default content type handling



#### SSL/TLS Configuration:

- **Module**: `Crypt::SSLeay` for HTTPS support

- **Implementation**: Automatic SSL handling, no custom configuration


### URL Construction Patterns:



#### RESTful URL Construction:

```perl

if ( uc($noparam) eq 'Y' ) {

  $URL = ("${url}${servlet}");

} else {

  $URL = ("${url}${servlet}?${content_string}");

}



# RESTful format conversion

if ( uc($restful) eq 'Y' ) {

  $URL =~ s/\?=//;

  if ( $restfiletype ) {

   $URL = $URL . "/" . $restfiletype;

  }

}

```



## 6. Response Handling



### Success/Error Checking Patterns:



#### HTTP Status Validation:

```perl

my $response = $user_agent->request($web_request);



# Check if request was successful

if ($response->is_success) {

  $response_content = $response->content;

  # Process successful response

} else {

  # Handle error

  $logger->error("HTTP request failed: " . $response->status_line);

}

```



#### Content Extraction:

```perl

# Standard content extraction

$response_content = $response->content;



# For WWW::Mechanize status checking

my $status_code = $mech->status();

```



#### JSON Response Handling:

```perl

# JSON response processing (when -JsonStatus parameter is used)

use JSON::PP;

my $json_response = decode_json($response_content);

```



## 7. Advanced Features



### RESTful API Support:

- **Feature**: RESTful URL construction and parameter handling

- **Implementation**: URL transformation from query parameters to path parameters

- **Usage**: `-RESTful Y` command line parameter



### File Type Handling:

- **Feature**: RESTful file type specification

- **Implementation**: Appends file type to URL path

- **Usage**: `-RESTFileType` parameter



### HTTP Method Selection:

- **Feature**: Dynamic HTTP method selection

- **Implementation**: GET vs POST based on `-HttpMethod` parameter

- **Default**: POST method



### Authentication:

- **Keytab Authentication**: `-Authenticate` parameter (implementation not detailed in analyzed sections)

- **No Basic Auth**: No evidence of HTTP Basic Authentication usage


## 8. Error Handling Patterns



### Timeout Handling:

```perl

# Configurable timeout with logging

my $timeout_mins = $timeout / 60;

$user_agent->timeout($timeout);

$logger->info("Timeout value passed: $timeout seconds ($timeout_mins minutes).");

```



### Response Error Handling:

```perl

# Standard error checking

if (!$response->is_success) {

  $logger->error("Request failed: " . $response->status_line);

  # Custom error handling based on context

}

```



### WWW::Mechanize Error Handling:

```perl

# Mechanize with autocheck disabled for custom error handling

my $mech = WWW::Mechanize->new(agent => "Mozilla/6.0", autocheck => 0);

# Manual status checking

return $mech->status();

```



## 9. Data Flow and Integration Context



### Primary Use Cases:



#### 1. Java Servlet Communication (Job Starter Scripts):

- **Purpose**: Submit HTTP requests to WebLogic Server Java Servlets

- **Data Flow**: Command line parameters → URL parameters → HTTP POST → Java backend

- **Integration**: Control-M job scheduler integration



#### 2. HP Service Manager Integration (HpsmTicket.pm):

- **Purpose**: Create support tickets via eHub service

- **Data Flow**: CSV case data → XML template → HTTPS POST → HP Service Manager

- **Authentication**: Environment-based URL selection (prod vs UAT)



#### 3. WebSphere Application Server Monitoring (30165CbiWasCtl.pl):

- **Purpose**: Check WAS server status via web interface

- **Data Flow**: HTTP GET → Status page → Status code extraction

- **Integration**: WebSphere administration console



### Common Data Sources:

- **Command line parameters**: Primary input source for job starter scripts

- **CSV files**: Case data for ticket creation

- **Configuration files**: Environment-specific URLs and settings

- **Database results**: External command execution for dynamic parameters



### Response Processing:

- **JSON responses**: Parsed for status and error messages

- **HTML responses**: Status code extraction for monitoring

- **XML responses**: Service manager ticket creation results




## 10. Migration Considerations for Python



### High Priority Items:



1. **Timeout Configuration**: All scripts use configurable timeouts (default 180s)

2. **SSL/HTTPS Support**: Critical for HP Service Manager integration

3. **Form Data Encoding**: `application/x-www-form-urlencoded` content type handling

4. **RESTful URL Construction**: Dynamic URL building with parameter transformation

5. **User-Agent String Customization**: Browser impersonation for WWW::Mechanize

6. **HTTP Method Selection**: Dynamic GET/POST selection

7. **Response Status Checking**: `is_success()` equivalent functionality

8. **Content Extraction**: Response body access patterns



### Python Equivalent Libraries:

- **LWP::UserAgent** → `requests` library

- **WWW::Mechanize** → `requests` + `BeautifulSoup` or `mechanize` library

- **HTTP::Request** → `requests.Request` objects

- **JSON::PP** → `json` standard library



### Special Attention Required:

1. **Environment-based URL selection** in HpsmTicket.pm

2. **RESTful parameter transformation** logic

3. **Custom User-Agent handling** for web scraping

4. **SSL certificate handling** for HTTPS endpoints

5. **Timeout configuration** preservation

6. **Error handling** pattern migration



## Summary Statistics



| Module | Files | Primary Use Cases | HTTP Methods | Special Features |

|--------|-------|------------------|--------------|------------------|

| LWP::UserAgent | 5 | API calls, HTTPS POST | GET, POST | SSL, Timeouts, JSON |

| WWW::Mechanize | 1 | Web scraping | GET | Browser simulation |



This analysis provides the foundation for migrating these HTTP client implementations from Perl CPAN modules to Python backend implementations while preserving all existing functionality and integration patterns.

