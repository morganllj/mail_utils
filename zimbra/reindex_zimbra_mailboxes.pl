#!/usr/bin/perl -w
#

use Getopt::Std;
use strict;

my %opts;

sub print_usage;
sub reindex;

getopts('nau:s:', \%opts);

print_usage()
  unless (exists $opts{a} || exists $opts{u} || exists $opts{s});

print "starting at ", `date`, "\n";

my @accts;

if (exists $opts{s}) {
    #    @accts = `zmprov -l gaa`;
    print "only indexing accounts on host $opts{s}\n";
    @accts = `zmprov -l sa '(&(zimbramailhost=$opts{s})(objectclass=zimbraAccount))'`;
} elsif (exists $opts{u}) {
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
	chomp $a;
	
	print "\nreindexing $a at ", `date`;

	my $cmd = "zmprov rim $a start 2>&1";
	print "${a} ${i}) ${cmd}\n";

	if (!defined $opts{n}) {
	    my $out = `$cmd`;
	    chomp $out;
	    print "${a} ${i}) $out\n";

	    my $statuscmd = "zmprov rim $a status 2>&1";
	    $out = `$statuscmd`;

	    my $c=0;
	    while ($out =~ /progress:/) {
		sleep 5;
		
		$out = `$statuscmd`;
		$out =~ s/status: running\n//;
		chomp $out;

		# print roughly every minute.  Count of 7 compensates
		# for time time it takes to run zmprov rim status.
		if ($c++==7) {
		    print "${a} ${i}) $out\n";
		    $c=0;
		}
	    }
	    print "${a} ${i}) $out\n"
	      if ($i>1);

	}
	$i++;
    }
    print "\nfinished at ", `date`, "\n";

}


sub print_usage {
    print "usage: $0 [-n] -a | -u user1,user2,...\n\n";
    exit;
}
