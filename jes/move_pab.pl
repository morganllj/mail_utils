#!/usr/bin/perl -w
#

use strict;
use Getopt::Std;

sub print_usage();

my $base = "dc=domain,dc=org,o=pab";
my $binddn = "cn=directory manager"
my $bindpw = "pass"
my $ldaphost = "mcsd-dir.domain.org";


my $opts;
getopts('u:o:n:',\%$opts);

my $user =    $opts->{u} || print_usage();
my $newuser = $opts->{n} || print_usage();
my $outfile = $opts->{o} || print_usage();

my $search_base = "ou=" . $user . ",ou=people," . $base;

print "searching with base: ", $search_base, "\n";

my $search_out = `ldapsearch -D "$binddn" -h $ldaphost -w $bindpw -Lb "$search_base" objectclass=\*`;

my $top_dn;

print "opening $outfile..\n";
open (OUT, ">$outfile");

print "parsing output of ldapsearch..\n";
my @entries = split /\n\n/, $search_out;
for (@entries) {
    
    s/\n\s+//g;
    s/^version[^\n]+\n//g;

    my ($dn) = /(dn:\s*[^\n]+\n)/;
    chomp $dn;

    $top_dn = $dn
	if (!defined $top_dn);

    print OUT "$dn\nchangetype: delete\n\n"
	unless ($dn eq $top_dn);

    $dn =~ s/ou=$user/ou=$newuser/g;
    my $entry = $_;
    $entry =~ s/dn:[^\n]+\n//;

    chomp $entry;

    print OUT "$dn\nchangetype: add\n$entry\n\n";
}
print OUT "$top_dn\nchangetype: delete\n";

close (OUT);
print "done.\n";
print "\nto make the updates to ldap:\n";
print "ldapmodify -D $binddn -h $ldaphost -f $outfile\n";



sub print_usage() {
    print "$0 -u <user name> -n <new user name> -o <outfile> \n";

    exit 0;
}



