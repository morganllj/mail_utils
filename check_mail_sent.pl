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
#
# */3 * * * * /etc/zabbix/custom/check_mail_sent.pl -p 60 -w 500 -c 2000 -f /var/mail_log/maillog -i domain.org -t > \
#    /etc/zabbix/custom/check_mail_sent.log 2>&1

use strict;
use Getopt::Std;
require "timelocal.pl";

sub print_usage();
sub get_concise_time($);
sub excluded($);


my %opts;
getopts('f:p:w:c:di:e:to:', \%opts);

my $filename = $opts{f} || print_usage();
my $time_period = $opts{p} || print_usage(); # start parsing $time_period 
    # minutes before the date of the last line line the log file.
my $warn_level = $opts{w} || print_usage();
my $critical_level = $opts{c} || print_usage();

my @exclude;
if (exists $opts{e}) {
    # print "-e not yet implemented.\n";
    # exit (1);

    @exclude = split /\s*,\s*/, $opts{e};
    print "-e used, excluding these domains/addresses: ", join " ", @exclude, "\n\n"
      if ($opts{d});
}

print "-d used, printing debugging...\n\n"
  if (exists $opts{d});

my @include_domains;
if (exists $opts{i}) {
    @include_domains = split /\s*,\s*/, $opts{i};
    print "only alerting for these domains: ", join " ", @include_domains, "\n\n"
      if ($opts{d});
}

my %mon2num = qw( Jan 0  Feb 1  Mar 2  Apr 3  May 4  Jun 5 Jul 6 Aug 7 Sep 8 
                  Oct 9 Nov 10 Dec 11 );

my $last_line;
my ($mon, $day, $hour, $min, $sec);
my $try_count = 0;

while ($try_count<15) {
    # get the last line of the log to know the time at the end of the log file
    $last_line = `tail -1 $filename`;
    chomp $last_line;

    print "last line: $last_line\n"
      if (exists $opts{d});

    # format we're parsing: Mar 16 23:59:59
    ($mon, $day, $hour, $min, $sec) = 
        ($last_line =~ /([a-z]{3})\s+(\d{1,2})\s(\d{2}):(\d{2}):(\d{2})/i);

    if (!defined $mon || !defined $day || !defined $hour || !defined $min || !defined $sec) {
        print "invalid last line, retrying...\n\n"
	  if (exists $opts{d});
	$try_count++;
	sleep 3;
    } else {
	last;
    }
}

if ($try_count > 9) {
    die "problem finding last line in $opts{i}";
}

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
	next
	  if (!defined $l_mon || !defined $l_day || !defined $l_hour || !defined $l_min || !defined $l_sec);
	my $line_time =
	  timelocal($l_sec, $l_min, $l_hour, $l_day, $mon2num{$l_mon}, $year);
	next unless ($line_time > ($end_time - ($time_period * 60)));

	if (!$printed_first && exists $opts{d}) {
	    print "first line: $_\n\n";
	    $printed_first = 1;
	}

	my $addr_domain = (split (/\@/, $addr))[-1];

#	if (!exists $opts{i} || grep /\Q$addr_domain\E/i, @include_domains) {
	if (exists $opts{i} && grep /\Q$addr_domain\E/i, @include_domains) {

	    unless (excluded($addr)) {
		if (exists $addrs{lc $addr}) {
		    $addrs{lc $addr}++;
		} else {
		    $addrs{lc $addr} = 1;
		}
	    }
	}
    }
}


{
    my %excluded_addrs;

    sub excluded ($) {
	my $in_addr = shift;

	return 1 if (exists $excluded_addrs{$in_addr});
	
	for my $e (@exclude) {
	    if ($in_addr =~ /$e/) {
		$excluded_addrs{$in_addr} = 1;
		return 1;
	    }
	}
	
	return 0;
    }
}




my $rc=0;
my @status;

for my $addr (sort keys %addrs) {
    if ($addrs{$addr} >= $warn_level || $addrs{$addr} >= $critical_level) {
	push @status, $addr;
	push @status, $addrs{$addr};
    }

    $rc = 1
      if (($addrs{$addr} >= $warn_level) && ($rc < 1) );
    $rc = 2
      if (($addrs{$addr} >= $critical_level) && ($rc < 2) );
}

my %file_contents;
if (exists $opts{o}) {
    my $in;
    unless (!open $in, $opts{o}) {
	my $contents = <$in>;
	close ($in);
	my @contents = split (/\s+/, $contents);

	pop @contents
	  if ($contents =~ /\d+Z\s*$/);

	my $state = shift @contents;

	%file_contents = @contents;

	if (exists $opts{d}) {
	    print "file:\n";
	    print "\tstate $state\n";
	    for my $key (sort keys %file_contents) {
		print "\t/$key/ /$file_contents{$key}/\n";
	    }
	}
    }
}

my %status = @status;

# save the current rc
my $saved_rc = $rc;
# assume a rc of 3 (REPEAT) unless there are values in %file_contents
# (the file is not empty) and there is a mismatch between their
# contents
$rc = 3;
for my $key (sort keys %file_contents) {
    if (!exists $status{$key}) {
	  print "\n\t$key not in live_status\n"
	    if (exists $opts{d});
	  $rc = $saved_rc;
	  last;  # one difference is enough to cause a non-3 rc
      }
}

if (keys %file_contents > 0 && $rc == 3){
    for my $key (sort keys %status) {
	if (!exists $file_contents{$key}) {
	    print "\n$key not in file\n"
	      if (exists $opts{d});
	    $rc = $saved_rc;
	    last;	# one difference is enough to cause a non-3 rc
	}
    }
} else { 
    # if %file_contents is empty (the file is empty) then we never return 3 (REPEAT)
    $rc = $saved_rc
}

my $out;
if (exists $opts{o}) {
    open ($out, ">", $opts{o}) || die "unable to open for writing: $opts{o}";
}

my $live_state;
if ($rc == 0) {
    $live_state = "OK";
} elsif ($rc == 1) {
    $live_state = "WARNING";
} elsif ($rc == 2) {
    $live_state = "CRITICAL";
} elsif ($rc == 3) {
    $live_state = "REPEAT";
} else {
    $live_state = "UNKNOWN";
}


if (exists $opts{d}) {
    print "\n";
    print "live:\n";
    print "\tstate: $live_state\n";

    for my $key (sort keys %status) {
	print "\t/$key/ /$status{$key}/\n";
    }
    print "\n";
}



if (exists $opts{o}) {
    if (exists $opts{d}) {
	print $live_state;
	print " " if ($#status>-1);
	print join (' ', @status);
    }

    print $out $live_state;
    print $out " " if ($#status>-1);
    print $out join (' ', @status);
} else {
    print $live_state;
    print " " if ($#status>-1);
    print join (' ', @status);
}

if (exists $opts{t}) {
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime (time);

    $year += 1900;

    $sec = 0 . $sec if ($sec<10);
    $min = 0 . $min if ($min<10);
    $hour = 0 . $hour if ($hour<10);
    $mon++;
    $mon = 0 . $mon if ($mon<10);

    my $timestamp = join '', ($year,$mon,$mday,$hour,$min,$sec,"Z");



    if (exists $opts{o}) {
	if (exists $opts{d}) {
	    print  " ", $timestamp, "\n\n";
	}
	print $out " ", $timestamp, "\n";
    } else {
	print " ", $timestamp, "\n";
    }
}

exit $rc;


######
sub print_usage() {
    print "usage:\n";
    print "$0 [-d] -p <time period> -w <warn level> -c <critical level> -f <filename>\n";
    print "\t[-e domain1,domain2,... -i domain1,domain2,...]\n";
    print "\n";
    print "[-d] print debug output, optional\n";
    print "-p <time period> look back this many minutes in the log file\n";
    print "-f <filename> log filename to open\n";
    print "[-w <level>] warn level\n";
    print "[-c <level>] critical level\n";
    print "[-e <expression> -i domain1,domain2,...] exclude (-e) or include (-i)\n";
    print "\t<expression> can any part of an address: sender\@domain.com, domain.com, sender, ender, .com, etc\n";
    print "\tdomains from/for alarming.\n";
    print "\t-e is not implemented.\n";
    print "[-t] print timestamp.  Used when outputting to a file from cron to ensure it's unique.\n";
    print "\tWe then do a checksum in Zabbix and if it doesn't change we know cron isn't running\n";
    print "\tthe script.\n";
    print "[-o] output to a file.  This also prints repeat in place of warning/critical if list list\n";
    print "\toff addresses is the same as in the prior output file.\n";
    
    print "\n";

    exit;
}


