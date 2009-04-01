#!/usr/bin/perl -w
#
# Author: Morgan Jones (morgan@morganjones.org)
# Id:     $Id$
#


use strict;
use Getopt::Std;
use Data::Dumper;
use ZimbraUtil;  # site-specific defaults are here
$|=1;

sub print_usage();

my %opts;
getopts('hl:D:w:b:em:ndz:s:p', \%opts);

my %arg_h;

# TODO handle unimplemented args:
for my $k (keys %opts) {
    if    ($k eq "h")   { print_usage() }
    elsif ($k eq "l")   { $arg_h{l_host}      = $opts{l}; }
    elsif ($k eq "D")   { $arg_h{l_binddn}    = $opts{D}; } 
    elsif ($k eq "w")   { $arg_h{l_bindpass}  = $opts{w}; }
    elsif ($k eq "b")   { $arg_h{l_base}      = $opts{b}; }
    elsif ($k eq "z")   { $arg_h{z_server}    = $opts{z}; }
    elsif ($k eq "m")   { $arg_h{z_domain}    = $opts{m}; }
    elsif ($k eq "p")   { $arg_h{z_pass}      = $opts{p}; }
    elsif ($k eq "e")   { print "extensive (-e) option not yet implemented\n"; }
    elsif ($k eq "n")   { $arg_h{g_printonly} = 1; }
    elsif ($k eq "d")   { $arg_h{g_debug}     = 1; }
    elsif ($k eq "s")   { # $arg_h{l_subset)..
                          print "subset (-s) option not yet implemented\n"; }
    elsif ($k eq "h")   { print_usage(); }
    else                { print "unimplemented option: -${k}:"; 
                          print_usage(); }
}

print "\nstarting at ", `date`;

my $zu = new ZimbraUtil(%arg_h);
#my @aa = $zu->rename_all_archives(attr_frm_ldap=>"orgghrsintemplidno", filter=>"(uid=a*)");
my @aa = $zu->rename_all_archives(attr_frm_ldap=>"orgghrsintemplidno");

print "\nfinished at ", `date`;


# print "accounts returned:\n";
# for (@aa) {
#     print "$_\n";
# }


######
sub print_usage() {
    print "\n";
    print "usage: $0 [-n] [-d] [-e] [-h] -l [<ldap host>] -b [<basedn>]\n".
	"\t-D [<binddn>] -w [<bindpass>] -m [<zimbra domain>] -z [<zimbra host>]\n".
	"\t[-s \"user1,user2, .. usern\"] -p <zimbra admin user pass>\n";
    print "\n";
    print "\toptions in [] are optional, but all can have defaults\n".
	"\t(see script to set defaults)\n";
    print "\t-n print, don't make changes\n";
    print "\t-d debug\n";
    print "\t-e exhaustive search.  Search out all Zimbra users and delete\n".
	"\t\tany that are not in your enterprise ldap.  Steps have been \n".
	"\t\tto make this scale arbitrarily high.  It's been tested on \n".
	"\t\ttens of thousands successfully.\n";
    print "\t-h this usage\n";
    print "\t-D <binddn> Must have unlimited sizelimit, lookthroughlimit\n".
	"\t\tnearly Directory Manager privilege to view users.\n";
    print "\t-s \"user1, user2, .. usern\" provision a subset, useful for\n".
	"\t\tbuilding dev environments out of your production ldap or\n".
	"\t\tfixing a few users without going through all users\n".
	"\t\tIf you specify -e as well all other users will be deleted\n";
    print "\n";
    print "example: ".
	"$0 -l ldap.morganjones.org -b dc=morganjones,dc=org \\\n".
	"\t\t-D cn=directory\ manager -w pass -z zimbra.morganjones.org \\\n".
        "\t\t-m morganjones.org\n";
    print "\n";

    exit 0;
}

__END__

