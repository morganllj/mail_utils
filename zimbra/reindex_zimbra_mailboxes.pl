#!/usr/bin/perl -w
#

use Getopt::Std;
use strict;

my %opts;

sub print_usage;
sub reindex;

getopts('nau:', \%opts);

print_usage()
  unless (exists $opts{a} || exists $opts{u});

print "starting at ", `date`, "\n";

my @accts;

if (exists $opts{u}) {
    @accts = split /\s*,\s*/, $opts{u};
} else {
    @accts = `zmprov -l gaa`;
}

print "reindexing: ", join (' ', @accts), "\n";

reindex (@accts);


sub reindex {
    my @accts = @_;
      
    my $i = 1;
    for my $a (sort @accts) {
	print "\nreindexing $a at ", `date`;

	my $cmd = "zmprov rim $a start 2>&1";
	print "${i}) ${cmd}\n";

	if (!defined $opts{n}) {
	    my $out = `$cmd`;
	    chomp $out;

	    print "$out\n";
	    while ($out =~ /Unable to submit reindex request. Try again later/) {
		sleep 5;
		print "${i}) ${cmd}\n";
		$out = `$cmd`;
		chomp $out;
		print "$out\n";
	    }

	}
	$i++;
    }
    print "\nfinished at ", `date`, "\n";

}


sub print_usage {
    print "usage: $0 -n -a | -u user1,user2,...\n\n";
    exit;
}
