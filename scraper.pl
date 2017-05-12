#!/usr/bin/env perl
use 5.020;
use common::sense;
use utf8::all;

# Use fast binary libraries
use Parallel::ForkManager;
use ScraperWorker;
use Data::Printer;

my $results_per_page = 100;
my %worker           = (
    8910 => 0,
    8911 => 0,
    8912 => 0,
    8913 => 0,
    8914 => 0,
);
my $filename = $ARGV[0];

my $pm = Parallel::ForkManager->new(scalar keys %worker);

$pm->run_on_finish(
    sub {
        my ($pid, $exit_code, $ident, $exit_signal, $core_dump, $data) = @_;
        say "$ident just got out of the pool "
            . "with PID $pid and exit code: $exit_code";

        if (defined $data) {
            my $port = ${$data};
            $worker{$port} = 0;
            say "port $port is free now";
        }
    });

$pm->run_on_start(
    sub {
        my ($pid, $ident) = @_;
        say "$ident started, pid: $pid";
        $worker{$ident} = $pid;
    });

# read in city list
my $city;
open(my $fh, '<:encoding(UTF-8)', $filename)
    or die "Could not open file '$filename' $!";
while ($city = <$fh>) {
    chomp $city;

    # wait for free worker port for phantomJS
    $pm->wait_for_available_procs;
    my $port;
    foreach my $p (keys %worker) {
        if (!$worker{$p}) {
            $worker{$p} = 1;
            $port = $p;
            last;
        }
    }

    $pm->start($port) and next;

    my $sw = ScraperWorker->new(
        city => $city,
        port => $port,
        rpp  => $results_per_page,
    );
    $sw->run;

    $pm->finish(0, \$port);
}
