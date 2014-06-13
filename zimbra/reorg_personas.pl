#!/usr/bin/perl -w
#

$/ = "";

my $l;

open $l,  "ldapsearch -w pass -x -h mldap01.domain.org -D uid=zimbra,cn=admins,cn=zimbra -LLLb \"\" objectClass=zimbraIdentity |";

my %personas;

while (<$l>) {
    s/\n //g;
    s/\n\n//;
#    print "/$_/\n\n";
    /dn: [^,]+,([^\n]+)/;
    my $parent = $1;
    push @{$personas{$1}}, $_;
}




for my $k (keys %personas) {
    print "\n";

    open $o, "|ldapdelete -x -v -D uid=zimbra,cn=admins,cn=zimbra -w pass -h mldap01.domain.org" || die "error opening ldapdelete: $!";
    for my $v (@{$personas{$k}}) {
	print "$v\n\n";

	$dn = $v;
	$dn =~ /dn: ([^\n]+)\n/;
	$dn = $1;
	print $o "$dn\n\n";
    }
    close $o;

    my $m = `ldapsearch -h mldap01.domain.org -x -D uid=zimbra,cn=admins,cn=zimbra -w pass -LLLb "$k" objectclass=\* mail|grep mail:|awk '{print \$2}'`;
    chomp $m;

    system ("zmprov createIdentity $m please\\ don\\'t\\ delete zimbraPrefWhenSentToEnabled FALSE zimbraPrefWhenInFoldersEnabled FALSE zimbraPrefReplyToEnabled FALSE");

   open $i, "|ldapmodify -x -w pass -h mldap01.domain.org -D uid=zimbra,cn=admins,cn=zimbra -a " || die "error opening ldapmodify: $!";

    for my $v (@{$personas{$k}}) {
	$v =~ s/zimbraCreateTimestamp:[^\n]+\n//g;
   	print $i "$v\n\n";
    }
    close $i;

}
