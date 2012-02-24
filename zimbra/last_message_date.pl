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
open2(*R, *W, "zmmailbox -z -m $acct");




my $last_date;
my $done = 0;

while (!$done) {
    if (!defined $last_date) {
	print W "search -l 1000 -t mess in:/Inbox\n";
    } else {
	print W "search -l 1000 -t mess \"in:/Inbox and before:$last_date\"\n";
    }

    my $d;
    while (<R>) {
	if (/^\s*\d+\./ && /(\d+\/\d+\/\d+)/) {
	    ($d)=/(\d+\/\d+\/\d+)/;
	} else {
	    last 
	      if (defined $d);
	}

	$done = 1 if (/more:\s*false/);
    }
    
    $last_date = $d;
}
print $last_date;


sub print_usage() {
    print "usage: $0 -m user\n";
    print "\n";
    exit;
}
