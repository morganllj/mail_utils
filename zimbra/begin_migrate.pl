#!/usr/bin/perl -w
#

use strict;
use Getopt::Std;

# You must have sudo su - zimbra ability, ideally with no password.
# You should be able to ssh -l zimbra $copy_to host without being prompted for a password.
# make sure /var/tmp/backup exists on $copy_to and is writeable by zimbra

sub print_usage();

my %opts;
getopts('u:ndc:', \%opts);

exists $opts{u} || print_usage();
my $copy_to=$opts{c} || print_usage();

exists $opts{n} && print "-n used, no changes will be made to active account(s).\n\n";

# split the -u option, set the accounts to maintenance if -n was not passed
my $bkp_str;
for my $u (split /\s*,\s*/, $opts{u}) {
    my $addr = $u . "\@domain.org";
    $bkp_str .= $addr . " ";
    my $cmd = "sudo su - zimbra -c \"zmprov ma $addr zimbraaccountstatus maintenance\"";
    print "$cmd\n";
    if (!exists $opts{n}) {
        system ($cmd);
    } else {
        print "\tuser left active..\n";
    }
}
chop $bkp_str;

# begin backup of the accounts
my $label=`sudo su - zimbra -c "zmbackup -f -z -a $bkp_str"`;
chomp $label;
# my $label = "full-20100520.145918.061";

print "\n";
print "label: $label\n";

# wait for the backup to finish
my $status;
while (1) {
    $status=`sudo su - zimbra -c "zmbackupquery -lb $label | grep Status"`;
    chomp $status;
    $status = (split /\s+/, $status)[1];
    if ($status eq "completed") {
        print "backup complete.\n";
        last;
    } else {
        print "\twaiting..\n";
        sleep 10;
    }
}

# transfer to copy_to host
print "transferring..\n";
system ("sudo su - zimbra -c \"tar cf - backup/sessions/$label\"| ssh zimbra\@$copy_to \"cd /var/tmp && tar xf -\"");
print "done.\n";



sub print_usage() {
    print "\n";
    print "usage: $0 -c <hostname> -u user1,user2,... -d [-n]\n";
    print "\t-c hostname host to which to copy backup.\n";
    print "\t-u user1,user2,... user(s) to migrate, comma separated\n";
    print "\t   for when you're migrating user back to a production environment\n";
    print "\t-n restore but do not make any changes to the active account(s)\n";
    print "\n";
    exit;
}
      
#   -u user to migrate
#   -m don't put user in maintenance mode first.
