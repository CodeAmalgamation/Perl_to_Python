# Inline Module Usage Analysis Report



## Executive Summary



After searching through all Perl files (*.pl and *.pm) in the project, **only one file** uses Inline modules:

- **File**: `script/chargebackpde/mi_act_rpt_run.pl`

- **Module**: Inline::Java

- **Complexity**: Moderate to High



## Detailed Analysis



### 1. Files Using Inline Modules



| File | Module | Line Number | Purpose |

|------|--------|-------------|---------|

| `script/chargebackpde/mi_act_rpt_run.pl` | Inline::Java | 302 | Actuate Report Generation |



### 2. Usage Details: mi_act_rpt_run.pl



#### Import Pattern

```perl

use Inline Java => 'STUDY', STUDY => ['actrpt_requester'] , PORT => 7000, SHARED_JVM => 1, EXTRA_JAVA_ARGS => '-Xmx512m', DIRECTORY => "$ENV{DATADIR}/host_log/$ENV{HOSTNAME}/inline_java";

```



#### Configuration Analysis

- **Study Mode**: Uses 'STUDY' mode to analyze existing Java class

- **Java Class**: `actrpt_requester` (Actuate Report Requester)

- **JVM Configuration**:

 - Port: 7000

 - Shared JVM: Enabled

 - Memory: 512MB (-Xmx512m)

 - Working Directory: `$ENV{DATADIR}/host_log/$ENV{HOSTNAME}/inline_java`



#### Object Creation & Methods Used

```perl

# Object instantiation

my $h = actrpt_requester->new( $common_opts{act_primary_server} )

  or die "Unable to create an Actuate Report Requester Object";



# Methods called on the Java object:

$h->SetServer($server, $property_file)

$h->Login($volume, $user, $password, $log_file)

$h->InitializeReportGeneration($priority, $location, $rox_name, ...)

$h->SetParameter($key, $value)

$h->GenerateODReport($comment, $folder, $recipients, $date_folder)

$h->GenerateDFRReport()

$h->PrintReport($folder, $date_folder, $report_name, $pdf_file, $root_id, $print_type)

```



#### Input Parameters

- **Server Configuration**: Actuate server details, property files

- **Authentication**: Volume ID, username, password

- **Report Parameters**: Priority, location, report names, dates, folders

- **Runtime Parameters**: Dynamic report parameters from command line

- **Output Options**: PDF generation, recipient lists



#### Output/Return Values

- **Return Codes**: Integer values (0 = success, non-zero = error)

- **Generated Reports**: Actuate reports in specified formats

- **PDF Files**: Optional PDF output to filesystem

- **Log Files**: Error and process logs




#### Dependencies & Setup Requirements

1. **Java Environment**:

  - `actrpt_lib.jar` must be in CLASSPATH

  - Actuate Axis client libraries (`$AC_AXISCLIENT_DIR/lib/*.jar`)

  - Java runtime with sufficient memory



2. **Actuate Infrastructure**:

  - Actuate Report Server running

  - Valid Actuate user credentials

  - Access to report volumes and folders



3. **File System**:

  - Write access to log directories

  - Inline Java compilation directory

  - Temp space for report generation



#### Integration Context

- **Purpose**: Enterprise reporting system for financial/chargeback reports

- **Workflow**: Batch job execution via Control-M scheduler

- **Data Flow**: Database → Report Parameters → Actuate → PDF/Reports

- **Error Handling**: Die on failures with detailed error messages



## Complexity Analysis



### Moderate to High Complexity Factors:



1. **Enterprise Integration**: Tight coupling with Actuate reporting infrastructure

2. **State Management**: Complex object lifecycle with multiple method calls

3. **Parameter Handling**: Dynamic report parameters with validation

4. **Error Recovery**: Critical business process with comprehensive error handling

5. **Resource Management**: Shared JVM with memory management

6. **Security**: Authentication and access control integration



## Migration Strategy Recommendations



### Option 1: Python Actuate Integration (Recommended)

**Approach**: Replace Inline::Java with Python-based Actuate client

```python

# Potential implementation using actuate-python or REST API

from actuate_client import ActuateReportClient



client = ActuateReportClient(server=server, port=port)

client.authenticate(volume, username, password)

client.set_parameters(report_params)

report_id = client.generate_report(report_config)

```



**Pros**:

- Cleaner architecture without inline compilation

- Better error handling and logging

- Easier testing and maintenance



**Cons**:

- Requires Python Actuate client library or REST API access

- May need custom wrapper development


### Option 2: CPAN Bridge Approach

**Approach**: Use the CPAN Bridge to maintain Perl functionality

```python

# Using CPAN Bridge

from cpan_bridge import perl_call



result = perl_call('mi_act_rpt_run.pl', params)

```



**Pros**:

- Minimal code changes initially

- Preserves existing business logic

- Lower migration risk



**Cons**:

- Still dependent on Perl runtime

- Doesn't fully eliminate CPAN dependencies

- Performance overhead



### Option 3: Native Python Rewrite (Long-term)

**Approach**: Complete rewrite using Python reporting libraries

- Use libraries like ReportLab, JasperReports Python bindings, or direct REST APIs

- Implement report generation natively in Python



## Implementation Challenges & Gotchas



1. **Actuate API Compatibility**: Ensure Python client supports same API versions

2. **Report Templates**: Verify report definitions work with new client

3. **Authentication Integration**: Maintain SSO/LDAP integration

4. **Performance**: Shared JVM optimization may need equivalent in Python

5. **Error Codes**: Maintain same error handling semantics for downstream systems

6. **Concurrent Usage**: Multiple report generation sessions handling

7. **Memory Management**: Large report generation memory requirements



## Recommended Migration Approach



### Phase 1: Investigation (1-2 weeks)

1. Research Python Actuate client libraries

2. Test Actuate REST API compatibility

3. Verify report template compatibility

4. Performance benchmarking



### Phase 2: Development (3-4 weeks)

1. Develop Python Actuate client wrapper

2. Implement parameter handling and validation

3. Add comprehensive error handling

4. Create unit and integration tests



### Phase 3: Testing (2-3 weeks)

1. Parallel execution testing

2. Report quality validation

3. Performance comparison

4. Integration testing with Control-M



### Phase 4: Migration (1 week)

1. Deploy Python implementation

2. Update scheduler configurations

3. Monitor and validate production execution



## Risk Assessment: MEDIUM-HIGH



- **Technical Risk**: Medium (well-defined Java API to replace)

- **Business Risk**: High (critical reporting functionality)

- **Timeline Risk**: Medium (depends on Actuate Python client availability)



## Conclusion



The single Inline::Java usage in this project represents a critical but isolated integration point. While moderately complex due to enterprise reporting requirements, it's a good candidate for migration to Python using modern Actuate client libraries or REST APIs. The migration should be treated as a high-priority item due to its business criticality.

