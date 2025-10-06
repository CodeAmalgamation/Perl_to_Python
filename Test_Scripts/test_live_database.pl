#!/usr/bin/perl
use strict;
use warnings;
use lib '.';
use CPANBridge;
use Data::Dumper;

# ====================================================================
# LIVE DATABASE TEST WITH KERBEROS
# ====================================================================
# Comprehensive test of all DBI features against a real Oracle database
# Requires: Valid Kerberos ticket or database credentials
# ====================================================================

print "=== Live Database Test ===\n\n";

$CPANBridge::DAEMON_MODE = 1;

my $test_count = 0;
my $pass_count = 0;

sub run_test {
    my ($test_name, $result) = @_;
    $test_count++;

    if ($result) {
        $pass_count++;
        print "✅ Test $test_count: $test_name - PASSED\n";
        return 1;
    } else {
        print "❌ Test $test_count: $test_name - FAILED\n";
        return 0;
    }
}

# ====================================================================
# LOAD DATABASE CONFIGURATION
# ====================================================================

# Try to load db_config.pl if it exists
my $db_config_exists = 0;
my %db_params;

if (-f 'Test_Scripts/db_config.pl') {
    require 'Test_Scripts/db_config.pl';
    %db_params = DBConfig::get_connection_params();
    $db_config_exists = 1;
    print "✅ Loaded database configuration from db_config.pl\n";
    print "   DSN: $db_params{dsn}\n";
    print "   Auth Method: $db_params{auth_mode}\n\n";
} else {
    print "⚠️  No db_config.pl found - using default test configuration\n";
    print "   To test with live database:\n";
    print "   1. Copy Test_Scripts/db_config.pl.template to Test_Scripts/db_config.pl\n";
    print "   2. Edit db_config.pl with your database details\n";
    print "   3. Run this test again\n\n";

    # Use defaults (will fail to connect, but tests logic)
    %db_params = (
        dsn => 'dbi:Oracle:TESTDB',
        auth_mode => 'kerberos',
        username => '',
        password => ''
    );
}

my $bridge = CPANBridge->new();

# ====================================================================
# PRE-FLIGHT CHECK: Kerberos Ticket
# ====================================================================

if ($db_params{auth_mode} eq 'kerberos') {
    print "Checking Kerberos ticket status...\n";

    my $klist_output = `klist 2>&1`;
    my $klist_status = $?;

    if ($klist_status == 0 && $klist_output =~ /Valid starting|Ticket cache/) {
        print "✅ Kerberos ticket found and valid\n";
        print "   Ticket info:\n";
        # Show first few lines of klist output
        my @lines = split(/\n/, $klist_output);
        for my $i (0 .. min(3, $#lines)) {
            print "   $lines[$i]\n";
        }
        run_test("Kerberos ticket valid", 1);
    } else {
        print "❌ No valid Kerberos ticket found\n";
        print "   Please run: kinit your_username\@YOUR.DOMAIN\n";
        print "   Then run this test again\n";
        run_test("Kerberos ticket valid", 0);

        if (!$db_config_exists) {
            print "\n⚠️  Stopping test - need valid Kerberos ticket or db_config.pl\n";
            exit 1;
        }
    }
    print "\n";
}

sub min { return $_[0] < $_[1] ? $_[0] : $_[1]; }

# ====================================================================
# TEST 1: Database Connection
# ====================================================================
print "Test 1: Connecting to Oracle database...\n";

my $conn_result = $bridge->call_python('database', 'connect', {
    dsn => $db_params{dsn},
    username => $db_params{username},
    password => $db_params{password},
    auth_mode => $db_params{auth_mode},
    options => {
        AutoCommit => 1,
        RaiseError => 0,
        PrintError => 0
    }
});

print "Connection result:\n";
print Dumper($conn_result);

if ($conn_result->{success}) {
    print "✅ Successfully connected to Oracle database\n";
    print "   Connection ID: $conn_result->{connection_id}\n";
    run_test("Database connection successful", 1);
} else {
    print "❌ Failed to connect to database\n";
    print "   Error: $conn_result->{error}\n";
    run_test("Database connection successful", 0);

    print "\n⚠️  Cannot continue tests without database connection\n";
    print "\nTroubleshooting:\n";
    print "1. Verify DSN is correct: $db_params{dsn}\n";
    print "2. For Kerberos: Check 'kinit' and 'klist'\n";
    print "3. For password: Verify username/password in db_config.pl\n";
    print "4. Check Oracle client is installed: 'python3 -c \"import oracledb; print(oracledb.version)\"'\n";
    print "5. Check network connectivity to database server\n";

    exit 1;
}

my $connection_id = $conn_result->{connection_id};
print "\n";

# ====================================================================
# TEST 2: Simple Query (SELECT FROM DUAL)
# ====================================================================
print "Test 2: Executing simple query...\n";

my $query_result = $bridge->call_python('database', 'execute_immediate', {
    connection_id => $connection_id,
    sql => "SELECT 'Hello from Oracle' as message, SYSDATE as current_date, USER as db_user FROM DUAL"
});

if ($query_result->{success} && $query_result->{rows}) {
    print "✅ Query executed successfully\n";
    my $row = $query_result->{rows}->[0];
    print "   Message: $row->[0]\n";
    print "   Date: $row->[1]\n";
    print "   User: $row->[2]\n";
    run_test("Simple query execution", 1);
} else {
    print "❌ Query failed\n";
    print "   Error: " . ($query_result->{error} || 'Unknown error') . "\n";
    run_test("Simple query execution", 0);
}
print "\n";

# ====================================================================
# TEST 3: Column Metadata (Phase 2 Feature)
# ====================================================================
print "Test 3: Column metadata extraction...\n";

if ($query_result->{column_info}) {
    my $col_info = $query_result->{column_info};
    print "✅ Column metadata available\n";
    print "   Column count: $col_info->{count}\n";
    print "   Column names: " . join(", ", @{$col_info->{names}}) . "\n";
    print "   Column types: " . join(", ", @{$col_info->{types}}) . "\n";

    if ($col_info->{columns}) {
        print "   Enhanced metadata:\n";
        for my $col (@{$col_info->{columns}}) {
            print "     - $col->{name}: $col->{type}";
            print " (size: $col->{internal_size})" if defined $col->{internal_size};
            print " (nullable: " . ($col->{nullable} ? 'YES' : 'NO') . ")" if defined $col->{nullable};
            print "\n";
        }
        run_test("Enhanced column metadata", 1);
    } else {
        print "   ⚠️  Basic metadata only (enhanced metadata missing)\n";
        run_test("Enhanced column metadata", 0);
    }
} else {
    print "❌ No column metadata returned\n";
    run_test("Enhanced column metadata", 0);
}
print "\n";

# ====================================================================
# TEST 4: NULL Value Handling (Phase 2 Feature)
# ====================================================================
print "Test 4: NULL value handling...\n";

my $null_result = $bridge->call_python('database', 'execute_immediate', {
    connection_id => $connection_id,
    sql => "SELECT NULL as null_col, 'value' as text_col, NULL as null_col2, 123 as num_col FROM DUAL"
});

if ($null_result->{success} && $null_result->{rows}) {
    my $row = $null_result->{rows}->[0];
    my $nulls_correct = (!defined($row->[0]) && !defined($row->[2]) &&
                        defined($row->[1]) && defined($row->[3]));

    if ($nulls_correct) {
        print "✅ NULL values handled correctly\n";
        print "   NULL columns returned as undef: ✓\n";
        print "   Non-NULL values preserved: ✓\n";
        run_test("NULL value handling", 1);
    } else {
        print "❌ NULL values not handled correctly\n";
        print "   Row data: " . Dumper($row);
        run_test("NULL value handling", 0);
    }
} else {
    print "❌ NULL test query failed\n";
    run_test("NULL value handling", 0);
}
print "\n";

# ====================================================================
# TEST 5: Prepare and Execute (Standard DBI Pattern)
# ====================================================================
print "Test 5: Prepare and execute pattern...\n";

my $prep_result = $bridge->call_python('database', 'prepare', {
    connection_id => $connection_id,
    sql => "SELECT ? as input_val, ? * 2 as doubled FROM DUAL"
});

if ($prep_result->{success}) {
    print "✅ Statement prepared\n";
    my $statement_id = $prep_result->{statement_id};

    my $exec_result = $bridge->call_python('database', 'execute_statement', {
        connection_id => $connection_id,
        statement_id => $statement_id,
        bind_values => [42, 21]
    });

    if ($exec_result->{success}) {
        print "✅ Statement executed\n";

        my $fetch_result = $bridge->call_python('database', 'fetch_row', {
            connection_id => $connection_id,
            statement_id => $statement_id,
            format => 'array'
        });

        if ($fetch_result->{success} && $fetch_result->{row}) {
            my $row = $fetch_result->{row};
            if ($row->[0] == 42 && $row->[1] == 42) {
                print "✅ Bind parameters worked correctly\n";
                print "   Input: $row->[0], Doubled: $row->[1]\n";
                run_test("Prepare/execute/fetch pattern", 1);
            } else {
                print "❌ Bind parameters incorrect\n";
                print "   Expected: [42, 42], Got: [" . join(", ", @$row) . "]\n";
                run_test("Prepare/execute/fetch pattern", 0);
            }
        } else {
            print "❌ Fetch failed\n";
            run_test("Prepare/execute/fetch pattern", 0);
        }
    } else {
        print "❌ Execute failed\n";
        run_test("Prepare/execute/fetch pattern", 0);
    }
} else {
    print "❌ Prepare failed\n";
    run_test("Prepare/execute/fetch pattern", 0);
}
print "\n";

# ====================================================================
# TEST 6: Connection Caching (Phase 1 Feature)
# ====================================================================
print "Test 6: Connection caching...\n";

my $cached_result1 = $bridge->call_python('database', 'connect_cached', {
    dsn => $db_params{dsn},
    username => $db_params{username},
    password => $db_params{password},
    auth_mode => $db_params{auth_mode}
});

if ($cached_result1->{success}) {
    print "✅ First connect_cached successful\n";
    my $first_conn_id = $cached_result1->{connection_id};
    my $first_cached = $cached_result1->{cached} || 0;

    # Second call should return cached connection
    my $cached_result2 = $bridge->call_python('database', 'connect_cached', {
        dsn => $db_params{dsn},
        username => $db_params{username},
        password => $db_params{password},
        auth_mode => $db_params{auth_mode}
    });

    if ($cached_result2->{success}) {
        my $second_cached = $cached_result2->{cached} || 0;

        if ($second_cached == 1) {
            print "✅ Second call returned cached connection\n";
            print "   First call cached flag: $first_cached\n";
            print "   Second call cached flag: $second_cached\n";
            run_test("Connection caching works", 1);
        } else {
            print "⚠️  Second call should have been cached\n";
            print "   This might be OK if cache timeout elapsed\n";
            run_test("Connection caching works", 0);
        }
    } else {
        print "❌ Second connect_cached failed\n";
        run_test("Connection caching works", 0);
    }
} else {
    print "❌ connect_cached failed\n";
    run_test("Connection caching works", 0);
}
print "\n";

# ====================================================================
# TEST 7: Session Initialization (do_statement)
# ====================================================================
print "Test 7: Session initialization with do_statement...\n";

my $do_result = $bridge->call_python('database', 'do_statement', {
    connection_id => $connection_id,
    sql => "ALTER SESSION SET NLS_DATE_FORMAT='MM/DD/YYYY HH:MI:SS AM'"
});

if ($do_result->{success}) {
    print "✅ do_statement executed successfully\n";

    # Verify the format changed
    my $verify_result = $bridge->call_python('database', 'execute_immediate', {
        connection_id => $connection_id,
        sql => "SELECT TO_CHAR(SYSDATE) as formatted_date FROM DUAL"
    });

    if ($verify_result->{success} && $verify_result->{rows}) {
        my $date_str = $verify_result->{rows}->[0]->[0];
        print "   Date format: $date_str\n";

        if ($date_str =~ m{^\d{2}/\d{2}/\d{4} \d{2}:\d{2}:\d{2} (AM|PM)$}) {
            print "✅ Date format matches expected pattern\n";
            run_test("Session initialization", 1);
        } else {
            print "⚠️  Date format doesn't match expected pattern\n";
            print "   Expected: MM/DD/YYYY HH:MI:SS AM/PM\n";
            print "   Got: $date_str\n";
            run_test("Session initialization", 0);
        }
    } else {
        print "❌ Verification query failed\n";
        run_test("Session initialization", 0);
    }
} else {
    print "❌ do_statement failed\n";
    print "   Error: " . ($do_result->{error} || 'Unknown') . "\n";
    run_test("Session initialization", 0);
}
print "\n";

# ====================================================================
# TEST 8: Error Handling (errstr - Phase 1 Feature)
# ====================================================================
print "Test 8: Error handling (errstr)...\n";

# Execute an intentionally bad query
my $bad_result = $bridge->call_python('database', 'execute_immediate', {
    connection_id => $connection_id,
    sql => "SELECT * FROM NONEXISTENT_TABLE_12345"
});

if (!$bad_result->{success}) {
    print "✅ Bad query correctly failed\n";
    print "   Error message: $bad_result->{error}\n";

    # Now test get_connection_error
    my $errstr_result = $bridge->call_python('database', 'get_connection_error', {
        connection_id => $connection_id
    });

    if ($errstr_result->{success}) {
        my $errstr = $errstr_result->{errstr} || '';
        if (length($errstr) > 0) {
            print "✅ errstr contains error message\n";
            print "   errstr: $errstr\n";
            run_test("Error handling (errstr)", 1);
        } else {
            print "⚠️  errstr is empty (might have been cleared)\n";
            run_test("Error handling (errstr)", 0);
        }
    } else {
        print "❌ get_connection_error failed\n";
        run_test("Error handling (errstr)", 0);
    }
} else {
    print "❌ Bad query should have failed but didn't\n";
    run_test("Error handling (errstr)", 0);
}
print "\n";

# ====================================================================
# CLEANUP: Disconnect
# ====================================================================
print "Cleanup: Disconnecting...\n";

my $disconnect_result = $bridge->call_python('database', 'disconnect', {
    connection_id => $connection_id
});

if ($disconnect_result->{success}) {
    print "✅ Disconnected successfully\n\n";
} else {
    print "⚠️  Disconnect reported an issue (connection may have already closed)\n\n";
}

# ====================================================================
# TEST SUMMARY
# ====================================================================
print "=" x 60 . "\n";
print "LIVE DATABASE TEST SUMMARY\n";
print "=" x 60 . "\n";
print "Database: $db_params{dsn}\n";
print "Auth Method: $db_params{auth_mode}\n";
print "Total tests: $test_count\n";
print "Passed: $pass_count\n";
print "Failed: " . ($test_count - $pass_count) . "\n";
print "Success rate: " . sprintf("%.1f%%", ($pass_count / $test_count) * 100) . "\n\n";

if ($pass_count == $test_count) {
    print "🎉 ALL TESTS PASSED!\n\n";
    print "✅ Database connection working\n";
    print "✅ Phase 1 features verified on live database\n";
    print "✅ Phase 2 features verified on live database\n";
    print "✅ Ready for production use\n";
} else {
    print "❌ Some tests failed. Review output above.\n\n";

    if ($pass_count > 0) {
        print "Partial success: " . sprintf("%.0f%%", ($pass_count / $test_count) * 100) . " of features working\n";
    }
}

print "\n=== Live Database Test Complete ===\n";
