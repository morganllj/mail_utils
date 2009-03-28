#!/usr/bin/perl -w
#
# Author: Morgan Jones (morgan@morganjones.org)
# Id:     $Id$
#
# Convert a Java Messaging Server 6.2 PAB to a CSV per user.
#   This was used to migrate users into Exchange 2007
#
# cd working/dir/path
#  ~/Docs/utils/trunk/jes/pab2csv.pl -u dc_ou_dc_edu_070522.ldif -p pab_no_mime.ldif -o contacts -a '"" givenname "" sn "" "" "" "" street "" "" l st postalcode co "" "" "" "" "" "" "" "" "" "" "" "" "" "" "" facsimileTelephoneNumber telephoneNumber "" "" "" "" "" homephone "" "" mobile "" "" pager "" "" "" "" "" "" "" dateofbirth "" "" "" "" mail "" "" "" "" "" "" "" "" "" "" "" "" "" "" "" "" "" "" "" "" "" "" "" "" "" "" "" "" "" "" "" "" labeleduri'|more
#
# ~/Docs/utils/trunk/jes/pab2csv.pl -u dc_ou_dc_edu_070522.ldif  -p o_pab.ldif -o contacts -a 'givenname,sn,cn,mail,telephonenumber,homephone,mobile,pager,facsimiletelephonenumber,address,l,st,postalcode,co,labeleduri,dateofbirth,description' -n 'First Name,Last Name,E-Mail Display Name,E-Mail Address,Business Phone,Home Phone,Mobile Phone,Pager,Business Fax,Home Street,Home City,Home State,Home Postal Code,Home/Country Region,Web Page,Birthday,Notes'
use strict;
use Getopt::Std;

sub print_usage();
sub get_pab_uris($);
sub get_next_contact($);
sub not_empty(@);

$|=1;
$/="";

# Default pab attributes that will be collected, in order.
#    The values will be returned in this order
my $d_pab_attrs_to_collect = "givenName sn mail street l postalCode co telephoneNumber facsimileTelephoneNumber";

my $opts;
getopts('u:p:da:o:n:', \%$opts);

my $user_ldif = $opts->{u} || print_usage();
my $pab_ldif = $opts->{p} || print_usage();
my $user_attr_list = $opts->{a} || $d_pab_attrs_to_collect;
my $csv_out_dir = $opts->{o} || print_usage();

$opts->{d} && print "attr_list: /$user_attr_list/\n";

#my @pab_attrs_to_collect = split(/\s{1}/, $user_attr_list);
my @pab_attrs_to_collect = split(/\,/, $user_attr_list);

# populate hash mapping paburi to uid
print "*** building paburi to uid mapping table...\n";
my $pab2uid_h = get_pab_uris($user_ldif);

# loop through pab entries, generate csv
print "*** compiling csvs..\n";
open(PAB, $pab_ldif) || die "can't open $pab_ldif";
my $contacts;
while (my $a = get_next_contact($pab2uid_h)) {
    my ($uid, @contact) = @$a;
    #print "$uid," . join(',', @contact) . "\n";
    # this won't scale.
    
    push @{$contacts->{$uid}}, join(',', @contact);
} 
close(PAB);

print "\nwriting csv files..\n";

for my $u (sort keys %$contacts) {

    my $outfile = "$csv_out_dir/$u.csv";
    if (!open (OUT, ">$outfile")) { 
	print "can't open $outfile";
	next;
    }

    if (exists $opts->{n}) {
	my @col_names = split(/\,/, $opts->{n});
	print OUT join ',', @col_names,"\n";
    }
	
    
    for (@{$contacts->{$u}}) {
 	print OUT $_ . "\n";
    }
    
}

close(OUT);




######
# sub get_next_contact
#
#  returns the next good contact from pab
#  returns undef when it gets to EOF.
#
sub get_next_contact($) {
    my $p2u = shift;

    # take one entry at a time from the PAB, return when a valid entry
    # is found.
    while (my $e = <PAB>) {
        my @e = parse_pab_entry($e, $p2u); 
        return \@e if (not_empty(@e));
    }
    $opts->{d} && print "returning undef..\n";
    return undef;

}  # get_next_contact 



######
# sub not_empty(@)
#
#  returns positive value if the list has one or more items in it
#  returns undef otherwise
#
sub not_empty(@) {
    my @a = @_;

    return undef unless ($#a > -1);

    # skip the first entry, it will always have the uid in it.

    for (my $i=1; $i<$#a+1; $i++) { 
        return 1 unless $a[$i] =~ (/^\s*$/);
    }
    return undef;
}


######
# sub parse_pab_entry($$)
#
#   takes an ldif entry and our pab to uid hash
#   returns a list containing the user requested 
#         attributes in order
#
sub parse_pab_entry($$) {
    my ($e, $p2u) = @_;

    # un-wrap lines in the ldif
    $e =~ s/\n\s+//g;
    $e .= "\n";  # add a cr to keep the lines consistent

    my $dn;
    my @r;
    # ignore entries that don't contain a dn or mail attribute and
    # entries that include 'un=AddressBook' in the dn.

#    print "e: /$e/\n";

    if ($e =~ /\nmail:[^\@]*\@[^\n]*\n/ && 
	$e !~ /dn:\s*un=addressbook/i &&
	$e =~ /dn:\s*([^\n]+)\n/i) { 

        $dn = $1; 
	$opts->{d} && print "dn: /$dn/\n";
    }	else {
        return @r;    
    }

    # strip off the rdn:
    #  dn:  un=MorganJones4df9d55,ou=uniqueIdentifier=9120,
    #          ou=people,o=ou.edu,dc=ou,dc=edu,o=pab
    #  becomes ou=uniqueIdentifier=9120,ou=people,o=ou.edu,dc=ou,dc=edu,o=pab
    $e =~ /dn:\s*[^\,]+,\s*([^\n]+)\n/i;
    my $pt = $1;

    if (!defined $pt || (defined $pt && !exists $p2u->{lc $pt})) {
        $opts->{d} && print "orphaned pab tree or container: $dn\n";
    } else { 
        my $u = $p2u->{lc $pt};
	
        push @r, $u;

        # pull the requested attributes out of the entry:
        for my $a (@pab_attrs_to_collect) {
            if ($a !~ /^\s*$/ && $e =~ /\n$a:\s*([^\n:]+)\n/i) {  
                       #':' added to keep blank entries from collecting the 
		       #     next line.  ie:
		       #
                       # homePhone:
                       # modifiersName: cn=Directory Manager
		       #
		       #     would return 'modifiersName: cn=Directory Manager 
                       #     for phone.
                my $v = $1;


		if ($v =~ /\,/) {
		    push @r, "\"$v\"";

		} else {
		    push @r, $v;
		}
            } else {
                push @r, '';
            }
        }

    }
    return @r;
}


######
# sub get_pab_uris
sub get_pab_uris($) {
    my $file = shift;

    my $p2u_h;
    open (USR, "$file") || die "can't open $file\n";
    while (<USR>) {
	# un-wrap lines in the ldif
	s/\n\s+//g;
        my ($dn)     = /dn:\s*([^\n]+)/i;
        my ($uid)    = /uid:\s*([^\n]+)/i;
        my ($paburi) = /paburi:\s*([^\n]+)/i;

        # paburi attribute format: 
        # ldap://pabldap.domain.com:389/ou=uniqueIdentifier=12460,ou=people,
        #                               o=domain.com,dc=domain,dc=com,o=pab

        # Ignore the entry if it does not have uid & paburi attributes.
        if (defined $uid && defined $paburi) {

	    # strip off 'ldap://host.domain.com:port'
	    #
            # ldap://pabldap.ou.edu:389/ou=uniqueIdentifier=12436,ou=people,o=ou.edu,dc=ou,dc=edu,o=pab
            # becomes ou=uniqueIdentifier=12436,ou=people,o=ou.edu,dc=ou,dc=edu,o=pab
            $paburi =~ s/ldap\:\/\/[^\/]+\///i;

            if (exists $p2u_h->{lc $paburi} && 
                lc $uid eq lc $p2u_h->{lc $paburi}){
                warn("$paburi already in hash.  Was $p2u_h->{lc $paburi}, ".
                    "now $uid");
            } else {
		$opts->{d} && print "adding $uid: /$paburi/\n";
                $p2u_h->{lc $paburi} = $uid;
            }
        }
    }
    close (USR);

    return $p2u_h;
} # sub get_pab_uris 


######
# sub print_usage
sub print_usage() {
    print "\n";
    print "usage: $0 [-d] [-a attribute list] [-n column names] -u <user ldif file>\n".
          "\t-p <pab ldif file> -o <output directory>\n";
    print "\n";

    print "\t[-d] print debugging\n";
    print "\t[-a attribute list] comma separated list of ldif attributes\n".
          "\t\tfrom the pab.  Values will be returned in the order the attrs\n".
          "\t\tare entered.  Default: $d_pab_attrs_to_collect\n\n"; 
    print "\t[-n column names] comma separated list of column names.\n".
	"\t\tThese will be printed on the top line of the csv output";
    print "\texport ldif with db2ldif:\n";
    print "\t./db2ldif -U1Nu -s dc=domain,dc=com\n".
          "\t\t-a /tmp/dc_domain_dc_com.ldif\n";
    #print "\t./db2ldif -U1Nu -s o=pab -a /tmp/o_pab.ldif\n";
    print "\t./db2ldif -UNm1u -s o=pab -a /tmp/o_pab.ldif\n";
    print "\n";
    print "\tthen $0 -u /tmp/dc_domain_dc_com.ldif -p /tmp/o_pab.ldif\n".
          "\t\t-o contacts\n";
    print "\n";
    exit 0;
}
