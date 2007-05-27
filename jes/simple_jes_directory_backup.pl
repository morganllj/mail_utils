#!/usr/bin/perl -w
#
# simple_jes_directory_backup.pl
# May 9, 2006
# Version: 0.02
# Morgan Jones (morgan@morganjones.org)

use strict;

use Getopt::Std;

my $opts;
getopts('hp:i:D:w:n', \%$opts);

my $default_ldap_port = 389;
my $default_bind_dn   = "cn=Directory Manager";

$opts->{h} && print_usage();
#  $instanceroot = "/iplanet/dir/52/slapd-iliad";
my $instanceroot = $opts->{i} || print_usage();
my $bind_dn =      $opts->{D} || $default_bind_dn;
my $ldap_port =    $opts->{p} || $default_ldap_port;
my $bind_pass =    $opts->{w} || print_usage();  #TODO: prompt for this?

my $db2ldif = $instanceroot . "/db2ldif";
my $backup_path = $instanceroot . "/ldif";

my $search_out =  `ldapsearch -p $ldap_port -Lb "" -s base objectclass=\*`;
# my $search_out =  `ldapsearch -p 1389 -Lb "" -s base objectclass=\*`;

die "$backup_path does not exist, exiting.."
    if (! -d $backup_path);

print "beginning directory backup.";
for (split /\n/, $search_out) {
    chomp;
    next unless
        (my ($context) = /namingContexts:\s+(.*)$/i);

    # print "context: /$context/\n";

    my $date = `date +%y%m%d.%H:%M.%S`;
    chomp $date;

    # normalize the context for the filename
    my $context_filename = $context;
    $context_filename =~ s/[^a-zA-Z0-9._]+/_/g;


#    my $dbname = `ldapsearch -D 'cn=Directory Manager' -w 'ru=2me??' -Lb 'cn=ldbm database,cn=plugins,cn=config' -s one nsslapd-suffix=$context cn|egrep '^cn:'|awk '{print \$2}'`;
    my $dbname = `ldapsearch -D "$bind_dn" -w '$bind_pass' -Lb 'cn=ldbm database,cn=plugins,cn=config' -s one nsslapd-suffix=$context cn|egrep '^cn:'|awk '{print \$2}'`;
    chomp $dbname;
     
    print "\n$db2ldif -n $dbname -s $context -a " . $instanceroot . "/ldif/" .
        $context_filename . "_" . $date . ".ldif\n";

    exists $opts->{n} ||
	system "$db2ldif -n $dbname -s $context -a " . $instanceroot . "/ldif/" .
	$context_filename . "_" . $date . ".ldif";

    if (exists $opts->{n} && $? >> 8 != 0) {
        print "failed to back up context $context: $!\n";;
        next;
    }
}

print "done.\n";



sub print_usage {

    print "\n\tusage: $0 [-h] [-n] -i <instance path> \n\t\t[-D <bind dn>] -w <password> [-p <port>]\n";
    print "\texample: $0  -i /var/mps/serverroot/slapd-host \n\t\t-D $default_bind_dn".
	"-p $default_ldap_port -w pass\n";
    print "\n\t-h print this message\n";
    print "\t-n show what I'm going to do, don't make changes\n";

    print "\n\titems in [] are optional.  Defaults are as they're listed in the example\n";

    print "\n";

    exit 0;
}
