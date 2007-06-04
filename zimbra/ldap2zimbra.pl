#!/usr/bin/perl -w
#

# Author: Morgan Jones (morgan@morganjones.org)
# Id:     $Id$
#
# Search an enterprise ldap and add/sync/delete users to a Zimbra
# infrastructure
#
# run as 'zimbra' user.
#
# One way sync: define attributes mastered by LDAP, sync them to
# Zimbra.  attributes mastered by Zimbra do not go to LDAP.

use strict;
use Getopt::Std;
use Net::LDAP;

sub print_usage();

my $opts;
getopts('h:D:w:b:', \%$opts);




my $ldap_host = $opts->{h} || print_usage();
my $ldap_base = $opts->{b} || print_usage();
my $binddn =    $opts->{D} || "cn=Directory Manager";
my $bindpass =  $opts->{w} || "pass";


### keep track of accounts in ldap and added.
### search out every account in ldap.
my $ldap = Net::LDAP->new($ldap_host);
my $rslt = $ldap->bind($binddn, password => $bindpass);
$rslt->code && die "unable to bind as $binddn: $rslt->error";

my $fil = "(&(objectclass=posixAccount)(objectclass=orgPerson)(uid=gab))";
$rslt = $ldap->search(base => "$ldap_base",
	      filter => $fil);
$rslt->code && die "problem with search $fil: ".$rslt->error;
for my $ent ($rslt->entries) {
    print "dn: ",$ent->dn(),"\n";
    my $usr = $ent->get_value("uid");
    print "uid: ",$ent->get_value("uid"),"\n";
    ### check for a corresponding zimbra account
    my $zusr = `zmprov ga $usr`;
    if ($zusr =~ /ERROR: account.NO_SUCH_ACCOUNT/) {
	### if not, add	
	print "add $usr\n";
    } elsif ($zusr =~ /^ERROR/) {
	print "Unexpected error on $usr, skipping: $zusr\n";
    }else {
	### if so, sync
	print "syncing $usr\n";
    }
}




$rslt = $ldap->unbind;


### get a list of zimbra accounts, compare to ldap accounts, delete### zimbra accounts no longer in in LDAP.




######
sub print_usage() {
    print "\n";
    print "usage: $0 -h <ldap host> -b <basedn> [-D <binddn>] ".
	"[-w <bindpass>]\n";
    print "\n";
    print "\toptions in [] are optional\n";
    print "\t-D <binddn> Must have unlimited sizelimit, \n".
	"\t\tlookthrough limit and ability to modify users.\n";
    print "\n";

    exit 0;
}











