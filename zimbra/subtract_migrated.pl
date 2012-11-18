#!/usr/bin/perl -w
#
# ./subtract_migrated.pl -m migrated_users.out -r 30_days_refusals.out  -o potential_honeypots.txt

use strict;

use Getopt::Std;

sub print_usage();

my $opts;
getopt('m:r:o:', \%$opts);

if (!exists $opts->{m} || !exists $opts->{r} || !exists $opts->{o}) {
    print_usage();
}

open IN_M, $opts->{m} || die "can't open $opts->{m}";
open IN_R, $opts->{r} || die "can't open $opts->{r}";
open OUT, ">$opts->{o}" || die "can't opent $opts->{o}\n";

my %migrated_users;
my %potential_honeypots;

print "loading list of migrated users..\n";
while (<IN_M>) {
    chomp;
    $migrated_users{lc $_} = 1;
}

print "aggregating potential honeypots..\n";
while (<IN_R>) {
    chomp;
    my ($e, $n) = split /:\s+/;
    $n = 1 if (!defined $n);
        
    $potential_honeypots{lc $e} += $n
        unless exists $migrated_users{lc $e};
}

print "writing $opts->{o}\n";
for my $k (sort keys %potential_honeypots) {
    print OUT "$k: $potential_honeypots{$k}\n";
}


sub print_usage() {
    print "\nusage: $0 -m <migrated users file> -r <refusals file>\n".
        "\t-o <output file>\n\n";
    print "\t-m <migrated users file> CR separated list of email addresses\n";
    print "\t-m <refusals file> CR separated list of email: <num bounces>\n";
    print "\t-o <output file> refusals file with migrated users removed\n";
    print "\n";
    exit;
}
