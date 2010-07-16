#!/usr/bin/perl -w
#
# zmprov ca morgantest@domain.org pass zimbramailtransport smtp:smtp.dev.domain.org:25
# zmprov ca morgan@domain.org pass zimbramailtransport smtp:smtp.domain.org:25

use strict;
use Getopt::Std;

$| = 1;

my %opts;

getopts('n', \%opts);

my %primary =   (host=>"mldap01.domain.org",
                 pass=>"pass");
my %secondary = (host=>"dmldap01.domain.org",
                 pass=>"pass");

my (%p_users, %s_users);

my $srch = "ldapsearch -x -w 00pass00 -h 00host00 -D uid=zimbra,cn=admins,cn=zimbra -Lb ou=people,dc=domain,dc=org objectclass=* uid";

my $p = $srch;
$p =~ s/00host00/$primary{host}/;
$p =~ s/00pass00/$primary{pass}/;
print "$p\n";

$/="";

for (sort `$p`) {
    next unless (/uid:\s([^\n]+)\n/);
    $p_users{lc $1} = 1;
}

my $s = $srch;
$s =~ s/00host00/$secondary{host}/;
$s =~ s/00pass00/$secondary{pass}/;
print "$s\n";

for (sort `$s`) {
     next unless (/uid:\s([^\n]+)\n/);
     $s_users{lc $1} = 1;
}


#open ZM, "|su - zimbra -c \"zmprov\"" || die "problem opening pipe to zmprov..";
open ZM, "|zmprov" || die "problem opening pipe to zmprov..";

for my $a (sort keys %p_users) {
    next 
        if exists $s_users{$a};
    my $cmd = "ca $a\@domain.org \"\" zimbramailtransport smtp:smtp.domain.org:25";
    print $cmd . "\n";
    print ZM $cmd . "\n"
        unless (exists $opts{n});
}

for my $a (sort keys %s_users) {
    next 
        unless !exists $p_users{$a};
    my $cmd = "skipping.. da $a\@domain.org";
    print $cmd . "\n";
#    print ZM $cmd . "\n"
#        unless (exists $opts{n});
            
}
close (ZM);





