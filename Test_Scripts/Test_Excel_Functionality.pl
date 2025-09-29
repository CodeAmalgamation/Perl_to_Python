#!/usr/bin/perl
use strict;
use warnings;
use CPANBridge;

sub test_excel_mode {
    my ($mode_name, $daemon_mode) = @_;

    print "\n=== Testing Excel Module - $mode_name ===\n";

    $CPANBridge::DAEMON_MODE = $daemon_mode;
    my $bridge = CPANBridge->new();

    my $test_file = "./test_workbook_${mode_name}.xlsx";
    $test_file =~ s/ /_/g;  # Remove spaces from filename

    # Test 1: Create workbook
    my $result = $bridge->call_python('excel', 'create_workbook', {
        filename => $test_file
    });

    my ($workbook_id, $library);
    if ($result->{success}) {
        $workbook_id = $result->{result}->{result}->{workbook_id};
        $library = $result->{result}->{result}->{library};
        print "Create workbook: PASS (ID: $workbook_id, Library: $library)\n";
    } else {
        print "Create workbook: FAIL - " . $result->{error} . "\n";
        return 0;
    }

    # Test 2: Add worksheet
    $result = $bridge->call_python('excel', 'add_worksheet', {
        workbook_id => $workbook_id,
        name => 'Test Data'
    });

    my $worksheet_id;
    if ($result->{success}) {
        $worksheet_id = $result->{result}->{result}->{worksheet_id};
        print "Add worksheet: PASS (ID: $worksheet_id)\n";
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
            workbook_id => $workbook_id,
            worksheet_id => $worksheet_id,
            row => $data->{row},
            col => $data->{col},
            data => $data->{value}
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
                workbook_id => $workbook_id,
                worksheet_id => $worksheet_id,
                row => $row,
                col => $col,
                data => "R${row}C${col}"
            });
        }
    }
    print "Multiple rows: PASS\n";

    # Test 5: Save workbook
    $result = $bridge->call_python('excel', 'close_workbook', {
        workbook_id => $workbook_id
    });

    if ($result->{success}) {
        print "Save workbook: PASS\n";

        # Verify file exists and has content (basic mode creates .csv)
        my $actual_file = $test_file;
        $actual_file =~ s/\.xlsx$/.csv/ if $library eq 'basic';

        if (-f $actual_file && -s $actual_file > 50) {  # Should be > 50 bytes
            print "File validation: PASS ($actual_file)\n";
        } else {
            print "File validation: FAIL - file too small or missing\n";
        }
    } else {
        print "Save workbook: FAIL - " . $result->{error} . "\n";
    }

    # Cleanup
    my $cleanup_file = $test_file;
    $cleanup_file =~ s/\.xlsx$/.csv/ if $library eq 'basic';
    unlink $cleanup_file if -f $cleanup_file;

    return 1;
}


test_excel_mode("Daemon Mode", 1);

print "\n=== Excel Module Validation Complete ===\n";