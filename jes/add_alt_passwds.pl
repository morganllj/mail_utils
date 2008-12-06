#!/usr/bin/perl -w
#
# add alternate password to all accounts in sun ldap
# Morgan Jones (morgan@morganjones.org)
#
# $Id$


## site-specific values
$host    = "localhost";
$dir_mgr = "cn=directory\\ manager";
$pass    = "pass";
$base    = "dc=morganjones,dc=org";

$new_pass = "newpass";

$backup_ldif = "add_alt_passwds." . $$ . ".ldif";
$new_pass_ldif = "add_alt_passwds_newpass.ldif";
# check below for openldap/linux vs. solaris
## end site-specific values



print "\nwriting existing passwords to $backup_ldif\n";

if ( -f $backup_ldif ) {
    print "$backup_ldif already exists.. exiting.\n";
    exit;
}

# openldap/linux:
my $srch_cmd = "ldapsearch -x -h $host -D $dir_mgr -Lb $base -w $pass ".
    "objectclass=inetmailuser userpassword > $backup_ldif";
# solaris:
#my $srch_cmd = "ldapsearch -h $host -D $dir_mgr -Lb $base -w $pass ".
#    "objectclass=inetmailuser userpassword > $backup_ldif";

my $cmd_no_pass = $srch_cmd;
$cmd_no_pass =~ s/$pass/pass/g;
print "\n" . $cmd_no_pass . "\n";

system ($srch_cmd);




open (IN, $backup_ldif) || die "can't open $backup_ldif for reading..!?";


open (OUT, ">$new_pass_ldif") || 
    die "can't open $new_pass_ldif for writing..!?";

print "\nwriting ldif to add new password: $new_pass_ldif\n";

$/ = "";
while (<IN>) {
    s/\n\s+//g;
    chomp;
    #print "/$_/\n";
    /(dn:[^\n]+)\n/;
    my $dn = $1;
    next unless defined ($dn);
    print OUT "$dn\n".
	"changetype: modify\n".
	"add: userpassword\n".
	"userpassword: $new_pass\n\n";
}

print "\nYou should now be read to import the passwords:\n";
# openldap/linux:
print "ldapmodify -xW -h $host -D $dir_mgr -f $new_pass_ldif\n";
# solaris: 
#print "ldapmodify -h $host -D $dir_mgr -f $new_pass_ldif\n";

print "\n";
