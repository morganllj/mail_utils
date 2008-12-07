#!/usr/bin/perl -w
#
# simple_jes_directory_backup.pl
# Dec. 7. 2008
# $Id$
# Morgan Jones (morgan@morganjones.org)

use strict;

use Getopt::Std;

my $opts;
getopts('hp:i:D:w:nB:', \%$opts);
# Options that require an argument have a trailing colon in the example above.

my $default_ldap_port = 389;
my $default_bind_dn   = "cn=Directory Manager";

$opts->{h} && print_usage();
my $instanceroot = $opts->{i} || print_usage();
my $default_backup_path = $instanceroot . "/ldif";
my $backup_path =  $opts->{B} || $default_backup_path;
my $bind_dn =      $opts->{D} || $default_bind_dn;
my $ldap_port =    $opts->{p} || $default_ldap_port;
my $bind_pass =    $opts->{w} || print_usage();  #TODO: prompt for this?

my $db2ldif = $instanceroot . "/db2ldif";
my $dsconf   = "/opt/SUNWdsee/ds6/bin/dsconf"; 
# my $backup_path = $instanceroot . "/ldif";

my $search_out =  `ldapsearch -p $ldap_port -Lb "" -s base objectclass=\*`;

# get version of directory server
$search_out =~ /vendorVersion:[^\/]+\/(\d+\.*\d*)/;
my $vendor_version = $1;

die "$backup_path does not exist, exiting.."
    if (! -d $backup_path);

# TODO: check this
$backup_path =~ s/(.*)([^\/]$)/$1$2\//is;

print "beginning directory backup.";
for (split /\n/, $search_out) {
    chomp;
    next unless
        (my ($context) = /namingContexts:\s+(.*)$/i);

    my $date = `date +%y%m%d.%H:%M.%S`;
    chomp $date;

    # normalize the context for the filename
    my $context_filename = $context;
    $context_filename =~ s/[^a-zA-Z0-9._]+/_/g;

    my $dbname = `ldapsearch -D "$bind_dn" -w '$bind_pass' -Lb 'cn=ldbm database,cn=plugins,cn=config' -s one nsslapd-suffix=$context cn|egrep '^cn:'|awk '{print \$2}'`;
    chomp $dbname;


    my $bkp_cmd = 1;
    if ($vendor_version >= 6) {
        $bkp_cmd = $dsconf ." export -e -h localhost ". $context ." ". $backup_path.
            $context_filename."_".$date.".ldif<<EOF\n$bind_pass\nEOF\n"; 
    } else {
        # for now assume it's version 5 if it's not 6
        $bkp_cmd = "$db2ldif -n $dbname -s $context -a " . $backup_path .
	    $context_filename . "_" . $date . ".ldif";
    }

#    print "\n$db2ldif -n $dbname -s $context -a " . $backup_path .
#        $context_filename . "_" . $date . ".ldif\n";
#
#    exists $opts->{n} ||
#	system "$db2ldif -n $dbname -s $context -a " . $backup_path .
#	$context_filename . "_" . $date . ".ldif";


    my $bkp_cmd_nopass = $bkp_cmd;
    $bkp_cmd_nopass =~ s/$bind_pass/pass/g;
    print "\n", $bkp_cmd_nopass, "\n";

    exists $opts->{n} ||
        system $bkp_cmd;

    if (exists $opts->{n} && $? >> 8 != 0) {
        print "failed to back up context $context: $!\n";;
        next;
    }
}

print "done.\n";



sub print_usage {

    print "\n\tusage: $0 [-h] [-n] -i <instance path> [-B <backup_path>] \n\t\t[-D <bind dn>] -w <password> [-p <port>]\n";
    print "\texample: $0  -i /var/mps/serverroot/slapd-host -B /var/mps/serverroot/slapd-host/ldif \n\t\t-D $default_bind_dn".
	"-p $default_ldap_port -w pass\n";
    print "\n\t-h print this message\n";
    print "\t-n show what I'm going to do, don't make changes\n";

    print "\n\titems in [] are optional.  Defaults are as they're listed in the example\n";

    print "\n";

    exit 0;
}
