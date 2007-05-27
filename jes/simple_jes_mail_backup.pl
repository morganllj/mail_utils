#!/usr/bin/perl -w
#
# simple_jes_mail_backup.pl
# May 9, 2007
# Version 0.02
# Morgan Jones (morgan@morganjones.org)

use strict;
use Getopt::Std;

my $opts;
getopts('nhi:b:', \%$opts);

# 
# 

# added for ims5.2.  Untested in this form.
# my $ims_bin_relative_path = "/bin/msg/store/bin/";
my $ims_bin_relative_path = "";

my $default_instance_root = "/opt/SUNWmsgsr";
my $instanceroot = $opts->{i} || $default_instance_root;
my $imsbackup = $instanceroot . $ims_bin_relative_path . "/sbin/imsbackup";
my $mboxutil = $instanceroot .  $ims_bin_relative_path . "/sbin/mboxutil";
my $backup_path = $opts->{b} || print_usage();

$backup_path .= "/users";

die "can't find $mboxutil and/or $imsbackup"
    if (!-f $imsbackup || !-f $mboxutil);



print "gathering user list..\n";
my $search_out =  `cd $instanceroot && $mboxutil -l`;

if (-d $backup_path) {
     print ("rm -r $backup_path\n");
    $opts->{n} || system("rm -r $backup_path");
}
print("mkdir $backup_path\n");
$opts->{n} || system("mkdir $backup_path");

die "$backup_path does not exist, exiting.."
    if (! -d $backup_path);

print "beginning mail backup..";
for (split /\n/, $search_out) {
    chomp;
    next unless (my ($uid) = /user\/([^\/]+)\/INBOX/);

    print "$imsbackup -f - /primary/users/$uid > ${backup_path}/$uid\n";
    $opts->{n} || system ("cd $instanceroot && $imsbackup -f - ".
			  "/ext/users/$uid > ${backup_path}/$uid");
    if ($opts->{n} && $? >> 8 != 0) {
	print "failed to back up $uid: $!\n";;
	next;
    }
}

print "done.\n";

sub print_usage {

    print "\n\tusage: $0 [-h] [-n]\n\t\t-i <instance path> [-b <backup path>]\n";
    print "\texample: $0  -i $default_instance_root\n\t\t-b /usr/local/ims_backup\n";
    print "\n\t-h print this message\n";
    print "\t-b backup path, path to write imsbackup files\n";
    print "\t\t***NOTE: a 'users' directory will be removed in\n";
    print "\t\t***      this path and then created during the backup\n";
    print "\t-n show what I'm going to do, don't make changes\n";

    print "\n\titems in [] are optional.  Defaults for optional arguemnts \n\t\t";
    print "are as they're listed in the example\n";

    print "\n";

    exit 0;
}
