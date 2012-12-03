#!/usr/bin/perl -w
#
# name: check_mail_sent.pl
#
# description: parse a postfix log file and report on an email
#     address(es) that send more than the selected quantity of mail.
# author: Morgan Jones (morgan@morganjones.org)
# date: 11/28/12
#
# Unless your log is very small and assuming you use nrpe you will
# need to increase your nrpe timeout.  On a 750mb log file with a 60
# min period the plugin takes around 20 secs:
# vi commands.cfg
#    $USER1$/check_nrpe -H $HOSTADDRESS$ -c $ARG1$ -t 60

use strict;
use Getopt::Std;
require "timelocal.pl";

sub print_usage();
sub get_concise_time($);

my %opts;
getopts('f:p:w:c:d', \%opts);

my $filename = $opts{f} || print_usage();
my $time_period = $opts{p} || print_usage(); # start parsing $time_period 
    # minutes before the date of the last line line the log file.
my $warn_level = $opts{w} || print_usage();
my $critical_level = $opts{c} || print_usage();

print "-d used, printing debugging..\n\n"
  if (exists $opts{d});

my %mon2num = qw( Jan 0  Feb 1  Mar 2  Apr 3  May 4  Jun 5 Jul 6 Aug 7 Sep 8 
                  Oct 9 Nov 10 Dec 11 );

# get the last line of the log to know the time at the end of the log file
my $last_line = `tail -1 $filename`;

# format we're parsing: Mar 16 23:59:59
my ($mon, $day, $hour, $min, $sec) = 
    ($last_line =~ /([a-z]{3})\s+(\d{1,2})\s(\d{2}):(\d{2}):(\d{2})/i);
my $year = (localtime(time()))[5] + 1900;
my $end_time = timelocal($sec, $min, $hour, $day, $mon2num{$mon}, $year);

my $start_time;  # time we start parsing log entries: $end_time - ($time_period * 60)

open IN, $filename || die "can't open $filename";

my %addrs;
my $printed_first = 0;

while (<IN>) {
	if (/postfix\// && /from=<([^>]+)>,/) {
	    my $addr = $1;
	    chomp;

	    my ($l_mon, $l_day, $l_hour, $l_min, $l_sec) = 
	      /([a-z]{3})\s+(\d{1,2})\s(\d{2}):(\d{2}):(\d{2})/i;
	    my $line_time =
	      timelocal($l_sec, $l_min, $l_hour, $l_day, $mon2num{$l_mon}, $year);
	    next unless ($line_time > ($end_time - ($time_period * 60)));

	    if (!$printed_first && exists $opts{d}) {
		print "first line: $_\n";
		print "last line: $last_line\n";
		$printed_first = 1;
	    }

	    if (exists $addrs{lc $addr}) {
		$addrs{lc $addr}++;
	    } else {
		$addrs{lc $addr} = 1;
	    }
	}
}


my $rc=0;
my @status;

for my $addr (sort keys %addrs) {

    push @status, $addr . " " . $addrs{$addr}
      if ($addrs{$addr} >= $warn_level || $addrs{$addr} >= $critical_level);

    $rc = 1
      if (($addrs{$addr} >= $warn_level) && ($rc < 1) );
    $rc = 2
      if (($addrs{$addr} >= $critical_level) && ($rc < 2) );
}

if ($rc == 0) {
    print "OK\n";
} elsif ($rc == 1) {
    print "WARNING ";
} elsif ($rc == 2) {
    print "CRITICAL ";
} else {
    print "UNKNOWN ";
}

print join (' ', @status), "\n";
exit $rc;



######
sub print_usage() {
    print "\n";
    print "usage:\n";
    print "$0 [-d] -p <time period> -w <warn level> -c <critical level> -f <filename>\n";
    print "\t[-d] print debug output, optional\n";
    print "\t-p <time period> look back this many minutes in the log file\n";
    print "\t-f <filename> log filename to open\n";
    print "\t[-w <level>] warn level\n";
    print "\t[-c <level>] critial level\n";
    print "\n";

    exit;
}
