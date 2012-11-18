#!/usr/bin/perl -w
#

use FileHandle;
use IPC::Open2;
use strict;
use Getopt::Std;

sub print_usage();

my %opts;
getopt('m:', \%opts);

exists $opts{m} || print_usage();

# zmmailbox -z -m 90000000015@domain.org.archive 
# search -l 1000 -t mess before:2/22/12

my $acct = $opts{m};

my $who = `whoami`;
chomp $who;

if ($who ne "zimbra") {
     print "run as zimbra!\n";
     exit;
}

# open (CMD, "|echo|");

# print CMD "hello\n";

# $out = <CMD>;
# print "out: /$out/\n";



#$pid = open2(*R, *W, "zmmailbox -z -m $acct");
my $pid = open2(*R, *W, "zmmailbox -z -m $acct");

my $last_date;
my $done = 0;
my $count=1000;

while (!$done) {
    if (!defined $last_date) {
	print W "search -l 1000 -t mess in:/Inbox\n";
    } else {
	print W "search -l 1000 -t mess \"in:/Inbox and before:$last_date\"\n";
    }

    my $d;
    while (<R>) {
	if (/^\s*\d+\./ && /(\d+\/\d+\/\d+)\s+\d+:\d+/) {
#	    ($d)=/(\d+\/\d+\/\d+)/;

	    ($d) = /(\d+\/\d+\/\d+)\s+\d+:\d+/
	} else {
	    last 
	      if (defined $d);
	}

	if (/more:\s*false/) {
	    $done = 1;
	    last
	}
    }
    
    $last_date = $d if (defined $d);
#    print $last_date . "\n";
}

close(R);
close(W);
waitpid($pid, 0);
print $last_date . "\n";



sub print_usage() {
    print "usage: $0 -m user\n";
    print "\n";
    exit;
}
