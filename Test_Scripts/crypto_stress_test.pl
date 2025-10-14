#!/usr/bin/perl
# crypto_stress_test.pl - Stress test focused on encryption/decryption
#
# Tests daemon resource usage under heavy crypto operations

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/..";
use CPANBridge;
use Time::HiRes qw(time sleep);
use threads;
use threads::shared;

my $success :shared = 0;
my $failed :shared = 0;

print "Crypto Stress Test - Encryption/Decryption Resource Usage\n";
print "=" x 70 . "\n\n";

print "Restarting daemon for clean test...\n";
system("pkill -f cpan_daemon.py");
sleep(2);
system("rm -f /tmp/cpan_bridge.sock");
sleep(1);

# Start fresh daemon in background
print "Starting fresh daemon...\n";
system("cd $FindBin::Bin/../python_helpers && python3 cpan_daemon.py > /tmp/cpan_daemon_crypto.log 2>&1 &");
sleep(5);

# Verify daemon is running
my $bridge = CPANBridge->new();
my $ping = $bridge->call_python('test', 'ping', {});
if (!$ping || !$ping->{message}) {
    die "ERROR: Daemon not responding!\n";
}
print "✓ Daemon started successfully\n\n";

# Get baseline
my $baseline = $bridge->call_python('system', 'metrics', {});
if ($baseline && $baseline->{resource_status}) {
    my $res = $baseline->{resource_status};
    printf "Baseline: %.1f MB memory, %.1f%% CPU\n\n",
        $res->{memory_mb}, $res->{cpu_percent};
}

# Test data of various sizes
my @test_data = (
    { size => 1024, label => "1KB", threads => 10, duration => 30 },
    { size => 10240, label => "10KB", threads => 20, duration => 30 },
    { size => 102400, label => "100KB", threads => 30, duration => 45 },
    { size => 524288, label => "500KB", threads => 50, duration => 60 },
    { size => 1048576, label => "1MB", threads => 75, duration => 60 },
    { size => 2097152, label => "2MB", threads => 100, duration => 90 },
);

my $test_num = 1;
for my $test (@test_data) {
    print "=" x 70 . "\n";
    printf "Test %d: %d threads × %s data (AES-256 encrypt/decrypt, %ds)\n",
        $test_num++, $test->{threads}, $test->{label}, $test->{duration};
    print "=" x 70 . "\n";

    run_crypto_test(
        $test->{threads},
        $test->{size},
        $test->{label},
        $test->{duration}
    );

    sleep(5);
    print_metrics("After $test->{label} test");
    print "\n";
}

print "=" x 70 . "\n";
print "Crypto stress test complete!\n\n";

my $total = $success + $failed;
printf "Total operations: %d\n", $total;
printf "Success: %d (%.1f%%)\n", $success, ($total > 0 ? $success/$total*100 : 0);
printf "Failed: %d (%.1f%%)\n\n", $failed, ($total > 0 ? $failed/$total*100 : 0);

print_metrics("Final state");

print "\nKilling daemon...\n";
system("pkill -f cpan_daemon.py");
print "Done.\n";

sub run_crypto_test {
    my ($num_threads, $data_size, $label, $duration) = @_;

    my $test_success :shared = 0;
    my $test_failed :shared = 0;

    my $start = time();
    my $end = $start + $duration;
    my @threads;

    # Create test data
    my $plaintext = 'X' x $data_size;
    my $key = 'MySecretKey12345' x 2;  # 32-byte key for AES-256

    # Spawn crypto worker threads
    for my $i (1..$num_threads) {
        push @threads, threads->create(sub {
            my $thread_id = $i;
            my $count = 0;

            while (time() < $end) {
                eval {
                    my $b = CPANBridge->new();

                    # Encrypt
                    my $enc_result = $b->call_python('crypto', 'encrypt_aes', {
                        data => $plaintext,
                        key => $key,
                        mode => 'CBC'
                    });

                    if (!$enc_result || !$enc_result->{encrypted}) {
                        { lock($failed); $failed++; }
                        { lock($test_failed); $test_failed++; }
                        return;
                    }

                    # Decrypt
                    my $dec_result = $b->call_python('crypto', 'decrypt_aes', {
                        encrypted => $enc_result->{encrypted},
                        key => $key,
                        iv => $enc_result->{iv},
                        mode => 'CBC'
                    });

                    if ($dec_result && $dec_result->{decrypted}) {
                        { lock($success); $success++; }
                        { lock($test_success); $test_success++; }
                    } else {
                        { lock($failed); $failed++; }
                        { lock($test_failed); $test_failed++; }
                    }
                };
                if ($@) {
                    { lock($failed); $failed++; }
                    { lock($test_failed); $test_failed++; }
                }

                $count++;
                sleep(0.1 + rand(0.2));  # 100-300ms between operations
            }

            return $count;
        });
    }

    # Monitor progress
    my $last_report = time();
    while (time() < $end) {
        if (time() - $last_report >= 5) {
            my $elapsed = time() - $start;
            my $rate = $test_success / ($elapsed || 1) * 60;
            printf "  [%.0fs] Success: %d (%.0f ops/min), Failed: %d\n",
                $elapsed, $test_success, $rate, $test_failed;
            $last_report = time();

            # Check daemon state
            eval {
                my $b = CPANBridge->new();
                my $m = $b->call_python('system', 'metrics', {});
                if ($m && $m->{resource_status}) {
                    my $r = $m->{resource_status};
                    printf "    Daemon: %.1f MB, %.1f%% CPU, %d concurrent\n",
                        $r->{memory_mb}, $r->{cpu_percent}, $r->{concurrent_requests};

                    if (@{$r->{warnings}}) {
                        print "    ⚠️  " . join(", ", @{$r->{warnings}}) . "\n";
                    }
                    if (@{$r->{violations}}) {
                        print "    🚨 " . join(", ", @{$r->{violations}}) . "\n";
                    }
                }
            };
        }
        sleep(1);
    }

    # Wait for all threads
    my $total_ops = 0;
    for my $t (@threads) {
        $total_ops += $t->join();
    }

    my $total_time = time() - $start;
    printf "  Completed: %d encrypt/decrypt cycles in %.1fs\n", $total_ops, $total_time;
    printf "  Success: %d, Failed: %d\n", $test_success, $test_failed;
}

sub print_metrics {
    my $label = shift;

    eval {
        my $b = CPANBridge->new();
        my $result = $b->call_python('system', 'metrics', {});
        if ($result && $result->{resource_status}) {
            my $res = $result->{resource_status};

            print "\n[$label]\n";
            printf "  Memory: %.1f MB (peak: %.1f MB) - %.1f%% of limit\n",
                $res->{memory_mb}, $res->{peak_memory},
                ($res->{peak_memory} / 1024 * 100);
            printf "  CPU: %.1f%% (peak: %.1f%%)\n",
                $res->{cpu_percent}, $res->{peak_cpu};
            printf "  Concurrent: %d, Rate: %d/min\n",
                $res->{concurrent_requests}, $res->{requests_per_minute};

            if (@{$res->{warnings}}) {
                print "  ⚠️  WARNINGS: " . join(", ", @{$res->{warnings}}) . "\n";
            }
            if (@{$res->{violations}}) {
                print "  🚨 VIOLATIONS: " . join(", ", @{$res->{violations}}) . "\n";
            }
        }
    };
}
