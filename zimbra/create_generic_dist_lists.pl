#!/usr/bin/perl -w
#

use strict;

my $base=140124;
my $i=0;
my $digits=4;

my %ids;

my $in;
my $out;
# cr separated list of employee ids
open ($in, "audit_ids_combined.txt") || die "can't open audit_ids_combined.txt";
# when finished: cat audit.out | zmprov
open ($out, ">audit.out") || die "can't open audit.out for writing";

while (<$in>) {
    chomp;

    print $_, " ";

    my $mail_search = `ldapsearch -H ldaps://ldap01.domain.net -LLLb dc=domain,dc=org -D binddn -x -w pass -LLL empid=$_ mail`;
#    print "/$mail_search/\n";

#    print "mail_search: /$mail_search/\n";

    my $mail = $mail_search;
    if ($mail =~ /mail:\s+([^\n]+)\n/) {
	$mail = $1;
    } else {
	$mail = undef;
    }
#    print "$mail\n";

    if (!defined $mail) {
	print "no_user\n";
    } elsif (exists $ids{$_}) {
	print "duplicate_eidn\n";
    } else {

	my $j = scalar (split (//, $i));
	my $count = 0 x ($digits - $j) . $i;
	my $alias = $base . $count;

	my $dist_list =  "emp-" . $alias . "\@domain.org";
	print "$dist_list\n";
#	print $out "aaa " . $mail . " emp-" . $alias . "\@domain.org" . "\n";
	print $out "cdl $dist_list zimbramailforwardingaddress $mail zimbrahideingal TRUE\n";
	
	$i++;
    }

    $ids{$_} = $1;
}
