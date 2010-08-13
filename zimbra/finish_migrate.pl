#!/usr/bin/perl -w
# 

use strict;
use Getopt::Std;

my $mailhost="mail01.domain.org";
my $zimbra_ldaphost="mldap01.domain.org";
my $zimbra_binddn = "uid=zimbra,cn=admins,cn=zimbra";
my $zimbra_searchbase = "dc=domain,dc=org";
my $zimbra_bindpass = "pass";
my $restore_pre="finish_migrate_";

sub print_usage();

my %opts;
getopts('u:l:n', \%opts);

exists $opts{l} || print_usage();
exists $opts{u} || print_usage();

exists $opts{n} && print "-n used, no changes will be made to active account(s).\n";

my $bkp_str;
for my $u (split /\s*,\s*/, $opts{u}) {
  $bkp_str .= $u . "\@domain.org ";
}
chop $bkp_str;

my $cmd = "sudo su - zimbra -c \"zmrestore -t /var/tmp/backup -c -ca -pre ".$restore_pre." --ignoreRedoErrors -lb $opts{l} -a $bkp_str\"";
print "$cmd\n";


my $result = `$cmd 2>&1`;
 print $result;
 die "restore failed.. " 
     if ($result =~ /have not been restored/ || $result =~ /Error/);

print "\n";

for my $u (split /\s*,\s*/, $opts{u}) {
    my $a = $u . "\@domain.org ";

    my $lists = `sudo su - zimbra -c \"ldapsearch -h $zimbra_ldaphost -D $zimbra_binddn -w $zimbra_bindpass -Lb $zimbra_searchbase zimbramailforwardingaddress=$a mail|egrep -i '^mail'\"`;
    my @dist_lists = split /mail:\s/, $lists;
    shift @dist_lists;
    for my $l (@dist_lists) { 
        chomp $l;
        $l =~ s/mail:\s+//
    }

    my $c = "sudo su - zimbra -c \"zmprov ra $a hld_${a}\""; 
    print "$c\n";
    if (!exists($opts{n})) { system ($c); }

    my $c0 = "sudo su - zimbra -c \"zmprov ra ".$restore_pre.$a." ".$a."\""; 
    print "$c0\n";
    if (!exists($opts{n})) { system ($c0); }

    my $c1 = "sudo su - zimbra -c \"zmprov ma $a zimbramailtransport lmtp:$mailhost:7025\"";
    print "$c1\n";
    if (!exists($opts{n})) { system ($c1); }
    my $c2 = "sudo su - zimbra -c \"zmprov ma $a zimbramailhost $mailhost zimbraaccountstatus active\"";
    print "$c2\n";

    if (!exists($opts{n})) { system ($c2); }
    print "\n";

    for my $l (@dist_lists) {
        my $c3 = "sudo su - zimbra -c \"zmprov adlm $l $a\"";
        print "$c3\n";
        if (!exists($opts{n})) { system($c3); }
    }

    print "\n";
    if (exists ($opts{n})) { print $restore_pre , $a, " left in place..\n"; }
}


sub print_usage() {
    print "\n";
    print "usage: $0 -u user1,user2,... -l <label> -n\n";
    print "\t-u user1,user2,... user(s) to migrate, comma separated\n";
    print "\t-l backup label, copy and paste from the output of begin_migrate.pl\n";
    print "\t-n backup but do not make any changes to the active account(s);\n";
    print "\n";
    exit;
}
