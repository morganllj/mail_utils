#!/usr/bin/perl -w
#

print "starting at ", `date`, "\n";

my $host = `zmhostname`;
chomp $host;

my $accts = `ldapsearch  -H ldap://ldap.domain.org -x -w pass -D cn=config -LLLb "" '(&(zimbramailhost=$host)(zimbraaccountstatus=active))' mail|grep mail:`;

my @accts = split /\n/, $accts;

my $i = 1;

for my $a (sort @accts) {
    $a =~ s/mail: //;

    my $cmd = "zmprov rim $a start 2>&1";
    print "${i}) ${cmd}\n";

    my $out = `$cmd`;
    chomp $out;

    print "$out\n";
    while ($out =~ /Unable to submit reindex request. Try again later/) {
    	sleep 5;
    	print "${i}) ${cmd}\n";
    	$out = `$cmd`;
    	chomp $out;
	print "$out\n";
    }
    $i++;
}
print "\nfinished at ", `date`, "\n";
