#!/usr/bin/perl -w
#
# Author: Morgan Jones (morgan@morganjones.org)
# Id:     $Id$
#


##################################################################
#### Site-specific settings
#
# The Zimbra SOAP libraries.  Download and uncompress the Zimbra
# source code to get them.
# use lib "/usr/local/zcs-5.0.2_GA_1975-src/ZimbraServer/src/perl/soap";
#use POSIX ":sys_wait_h";
# use IO::Handle;
# these accounts will never be added, removed or modified
#   It's a perl regex
my $exclude_group_rdn = "cn=orgexcludes";  # assumed to be in $ldap_base

# run case fixing algorithm (fix_case()) on these attrs.
#   Basically upcase after spaces and certain chars
# my @z_attrs_2_fix_case = qw/cn displayname sn givenname/;

# attributes that will not be looked up in ldap when building z2l hash
# (see sub get_z2l() for more detail)
# my @z2l_literals = qw/( )/;

# max delete recurse depth -- how deep should we go before giving up
# searching for users to delete:
# 5 == aaaaa*
# my $max_recurse = 5;

# Number of processes to run simultaneously.
# I've only tested parallelism <= 4. 
# I suggest you test larger numbers for $parallelism and
# $users_per_proc on a development system..
# my $parallelism = 2;
# number of users to process per fork.  If this number is too low the
# overhead of perl fork() can lock a Linux system solid.  I suggest
# keeping this > 50.
# my $users_per_proc = 500;

# hostname for zimbra store.  It can be any of your stores.
# it can be overridden on the command line.
my $default_zimbra_svr = "dmail01.domain.org";
# zimbra admin password
my $default_zimbra_pass  = 'pass';

# default domain, used every time a user is created and in some cases
# modified.  Can be overridden on the command line.
my $default_domain       = "dev.domain.org";

my $archive_mailhost = "dmail02.domain.org";

# TODO: look up cos by name instead of requiring the user enter the cos id.
# prod:
#my $archive_cos_id = "249ef618-29d0-465e-86ae-3eb407b65540";
# dev:
# my $archive_cos_id = "c0806006-9813-4ff2-b0a9-667035376ece";

# Global Calendar settings.  ldap2zimbra can create a calendar share
# in every user.
# my $cal_owner = "calendar-admin\@" . $default_domain;
# my $cal_name  = "Academic Calendar";
# my $cal_path  = "/" . $cal_name;

# my $child_status_path="/home/ldap2zimbra";
# die "can't write to child status directory: $child_status_path" if (! -w $child_status_path);





# default ldap settings, can be overridden on the command line
# my $default_ldap_host    = "ldap0.domain.org";
# my $default_ldap_host    = "ldap0.domain.org";
# my $default_ldap_base    = "dc=domain,dc=org";
# my $default_ldap_bind_dn = "cn=Directory Manager";
# my $default_ldap_pass    = "pass";
# good for testing/debugging:
#my $default_ldap_filter = 
#  "(|(orghomeorgcd=9500)(orghomeorgcd=8020)(orghomeorgcd=5020))";
#    "(orghomeorgcd=9500)";
# my $default_ldap_filter = "(orghomeorgcd=9500)";
#
# production:
#my $default_ldap_filter = "(objectclass=orgZimbraPerson)";

#### End Site-specific settings
#############################################################




use strict;
use Getopt::Std;
#use Net::LDAP;
use Data::Dumper;
# use XmlElement;
# use XmlDoc;
# use Soap;
use ZimbraUtil;
$|=1;

sub print_usage();
# sub add_user($);
# sub sync_user($$);
# sub get_z_user($);
# sub fix_case($);
# sub build_target_z_value($$$);
# sub delete_not_in_ldap();
# sub delete_in_range($$$);
# sub parse_and_del($);
# sub renew_context();
# sub in_exclude_list($);
# sub get_exclude_list();
# sub build_archive_account($);


my $opts;
# getopts('hl:D:w:b:em:ndz:s:p:a', \%$opts);
getopts('hs:', \%$opts);

$opts->{h}                     && print_usage();
# my $ldap_host = $opts->{l}     || $default_ldap_host;
# my $ldap_base = $opts->{b}     || $default_ldap_base;
# my $binddn =    $opts->{D}     || $default_ldap_bind_dn;
# my $bindpass =  $opts->{w}     || $default_ldap_pass;
my $zimbra_svr = $opts->{z}    || $default_zimbra_svr;
# my $zimbra_domain = $opts->{m} || $default_domain;
my $zimbra_pass = $opts->{p}   || $default_zimbra_pass;
my $subset_str = $opts->{s};

# my $multi_domain_mode = $opts->{u} || "0";  # the default is to treat
					    # all users as in the
					    # default domain --
					    # basically take the 'uid'
					    # atribute from ldap and
					    # concat the default
					    # domain.

# my $archive_domain = $zimbra_domain . ".archive";

# my $fil = $default_ldap_filter;

# url for zimbra store.  It can be any of your stores
# my $url = "https://dmail01.domain.org:7071/service/admin/soap/";
my $url = "https://" . $zimbra_svr . ":7071/service/admin/soap/";

# my $ACCTNS = "urn:zimbraAdmin";
# my $MAILNS = "urn:zimbraAdmin";
# my $SOAP = $Soap::Soap12;
# my $sessionId;  # set in get_zimbra_context()

# hash ref to store a list of users added/modified to extra users can
# be deleted from zimbra.
my $all_users;
my $subset;
# has ref to store archive accounts that need to be sync'ed.
my $archive_accts;

print "-n used, no changes will be made.\n"
    if (exists $opts->{n});


# print "-a used, archive accounts will be synced--".
#     "this will almost double run time.\n"
#     if (exists $opts->{a});

# if (defined $subset_str) {
#     for my $u (split /\s*,\s*/, $subset_str) {$subset->{lc $u} = 0;}
#     print "\nlimiting to subset of users:\n", join (', ', keys %$subset), "\n";
#     $fil = "(&" . $fil . "(|(uid=" . join (')(uid=', keys %$subset) . ")))";
# }

my $search_fil = "(zimbracosid=archive)";


print "\nstarting at ", `date`;
### keep track of accounts in ldap and added.
### search out every account in ldap.


my $zu = new ZimbraUtil($url, $zimbra_pass);

#my @aa = $zu->return_all_accounts();
my @aa = $zu->rename_all_archives();


# print "accounts returned:\n";
# for (@aa) {
#     print "$_\n";
# }

__END__

