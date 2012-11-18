#!/usr/bin/perl -w
#

use strict;
use Getopt::Std;
require "timelocal.pl";

sub print_usage;
sub get_concise_time($);

my %opts;
getopts('f:p:dw:c:o:r:', \%opts);

if (exists $opts{r}) {
    my $read_from = $opts{r};
    open IN2, $read_from || die "can't open $read_from for reading";
    my $rc = <IN2>;
    my $status = <IN2>;
    close (IN2);
    if (!defined $rc || !defined $status) {
        print "problem reading output format.. please check that the format is:\n";
        print "<rc>\n<OK|WARN|CRIT>\n";
        exit;
    }
    print $status;
    exit $rc;
}


open OUT, "> $opts{o}" || die "cant open $opts{o} for reading"
    if (exists $opts{o});

my $file = $opts{f} || print_usage();
my $time_period = $opts{p} || print_usage();
exists $opts{w} || print_usage();
exists $opts{c} || print_usage();
unless ($opts{c} > $opts{w}) {
    print "critical threshold must but larger than warn threshold\n";
    print_usage();
}

my %mon2num = qw( Jan 0  Feb 1  Mar 2  Apr 3  May 4  Jun 5 Jul 6 Aug 7 Sep 8 
                  Oct 9 Nov 10 Dec 11 );
my $start_time;  # time we start parsing log entries: $end_time - ($time_period * 60)

open (IN, $file) || die "can't open $file";

my $last_line = `tail -1 $file`;
print "last line: $last_line\n"
    if (exists $opts{d});

# format we're parsing: Mar 16 23:59:59
my ($mon, $day, $hour, $min, $sec) = 
    ($last_line =~ /([a-z]{3})\s+(\d{1,2})\s(\d{2}):(\d{2}):(\d{2})/i);
my $year = (localtime(time()))[5] + 1900;
my $end_time = timelocal($sec, $min, $hour, $day, $mon2num{$mon}, $year);


my %addrs;

while (<IN>) {
    chomp;

    my ($l_mon, $l_day, $l_hour, $l_min, $l_sec) = 
        /([a-z]{3})\s+(\d{1,2})\s(\d{2}):(\d{2}):(\d{2})/i;
    my $line_time = 
        timelocal($l_sec, $l_min, $l_hour, $l_day, $mon2num{$l_mon}, $year);

    # Skip log entries that aren't $time_period seconds from the
    # bottom of the log.
    next unless ($line_time > ($end_time - ($time_period * 60)));
    $start_time = $line_time unless defined $start_time;


    
    my $addr;
#    if (/postfix/ && (($addr)=/to=<([^>]+)/) || (($addr)=/from=<([^>]+)/)) {
    if (/postfix/ && (($addr)=/from=<([^>]+)/)) {
        #print "\taddr: $addr\n";
        $addr = lc $addr;
        $addrs{$addr}++;
        print "$addr: /$_/\n"
            if (exists $opts{d});
    }


}

my $rc = 0;
my $state = "OK";
my $above_threshold;

print "\n"
    if (exists $opts{d});

for my $k (sort keys %addrs) {
    $above_threshold .= $k . "=". $addrs{$k} . " "
        if ($addrs{$k} > $opts{w});

    if ($addrs{$k} > $opts{c} && $rc < 2) {
        $rc = 2;
        $state = "CRITICAL";
    }
    if ($addrs{$k} > $opts{w} && $rc < 1) {
        $rc = 1;
        $state = "WARN";
    }
}

chop $above_threshold
    if (defined $above_threshold);

my $nag_str = $state . " - " . get_concise_time($start_time) . " to " . 
        get_concise_time($end_time);
$nag_str .= " " . $above_threshold 
    if (defined $above_threshold);

if (exists $opts{o}) {
    print OUT $rc . "\n";
    print OUT $nag_str . "\n";
}

print $nag_str . "\n"
    if (!exists $opts{o} || exists $opts{d});

exit $rc
    if !exists $opts{o};

######
sub get_concise_time($) {
    my $t = shift;

    my @t = (localtime($t))[0..4];

    for my $v ((@t)[0..3]) {  # skip mon
        $v = "0".$v
            if ($v =~ /^\d{1}$/);
    }

    my ($sec, $min, $hour, $mday, $mon) = @t;
    $mon++;

    return $mon."/".$mday." ".$hour.":".$min.":".$sec;
}


sub print_usage {
    print "\n";
    print "usage:\n";
    print "$0 -f <mail log> -p <timeperiod> -w<level> -c<level> -o<output> -r<input>\n";
    print "\n";

    exit;
}

