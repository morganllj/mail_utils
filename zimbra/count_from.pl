#!/usr/bin/perl -w
#

use strict;
use Getopt::Std;
require "timelocal.pl";

sub print_usage;
sub get_concise_time($);

my %opts;
getopts('f:p:dt:', \%opts);

my $file = $opts{f} || print_usage();
my $time_period = $opts{p} || print_usage();
my $year = (localtime(time()))[5] + 1900;

my %mon2num = qw( Jan 0  Feb 1  Mar 2  Apr 3  May 4  Jun 5 Jul 6 Aug 7 Sep 8 
                  Oct 9 Nov 10 Dec 11 );
my $start_time;  # time we start parsing log entries: $end_time - ($time_period * 60)

open (IN, $file) || die "can't open $file";

# my $last_line = `tail -1 $file`;
# print "last line: $last_line\n"
#     if (exists $opts{d});

# # format we're parsing: Mar 16 23:59:59
# my ($mon, $day, $hour, $min, $sec) = 
#     ($last_line =~ /([a-z]{3})\s+(\d{1,2})\s(\d{2}):(\d{2}):(\d{2})/i);
# my $year = (localtime(time()))[5] + 1900;
# my $end_time = timelocal($sec, $min, $hour, $day, $mon2num{$mon}, $year);

my %addrs;
my $last_time;

while (<IN>) {
    chomp;

    if (/postfix/ && (($addr)=/from=<([^>]+)/)) {

    my ($l_mon, $l_day, $l_hour, $l_min, $l_sec) = 
        /([a-z]{3})\s+(\d{1,2})\s(\d{2}):(\d{2}):(\d{2})/i;
    my $line_time = 
        timelocal($l_sec, $l_min, $l_hour, $l_day, $mon2num{$l_mon}, $year);

#     # Skip log entries that aren't $time_period seconds from the
#     # bottom of the log.
#     next unless ($line_time > ($end_time - ($time_period * 60)));
#     $start_time = $line_time unless defined $start_time;

#     print "line_time: ", get_concise_time($line_time), "\n";
#     print "last_time: ", get_concise_time($last_time), "\n";

    my $time;
    if (!defined $last_time || ($line_time - $last_time) > ($time_period * 60)) {
        $time = $last_time = $line_time;
    } else {
        $time = $last_time;
    }


#    print "time: ", get_concise_time($time), "\n";

    my $addr;
###    if (/postfix/ && (($addr)=/to=<([^>]+)/) || (($addr)=/from=<([^>]+)/)) {


    if (/postfix/ && (($addr)=/from=<([^>]+)/)) {
        #print "\taddr: $addr\n";
        $addr = lc $addr;
#        $addrs{$addr}++;
#        print "$addr: /$_/\n"
#            if (exists $opts{d});
        print get_concise_time($time) . " " . $addr . "\n"
            if (exists $opts{d});
        $addrs{$time}{$addr}++;
    }
}

for my $t (sort keys %addrs) {
    my $already_printed_time = 0;
    for my $a (sort keys %{$addrs{$t}}) {
        next 
            if (exists $opts{t} && ($addrs{$t}{$a} < $opts{t}));
        
        unless ($already_printed_time) {
            print get_concise_time($t) . ":\n";
            $already_printed_time = 1;
        }
        print "\t$a: $addrs{$t}{$a}\n"        
        

#         unless ($already_printed_time) {
#             if (exists $opts{t}) {
#                 if ($addrs{$t}{$a} > $opts{t}) {
#                     print get_concise_time($t) . ":$a\n";
#                     $already_printed_time = 1;
#                 }
#             } else {
#                 print get_concise_time($t) . ":$a\n";
#                 $already_printed_time = 1;
#             }
#         }

#         if (exists $opts{t}) {
#             print "\t$a: $addrs{$t}{$a}\n"
#                 if ($addrs{$t}{$a} > $opts{t});
#         } else {
#             print "\t$a: $addrs{$t}{$a}\n"
#         }
    }
}


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
    print "$0 -f <mail log> -p <timeperiod> [-t<threshold]\n";
    print "example: $0 -f /var/log/maillog -p 720 -t 500\n";
    print "\n";

    exit;
}

