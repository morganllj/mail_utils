#!/usr/bin/perl -w
#
# Morgan Jones (morgan@morganjones.org)
# Description: ...

$/="";

# objectclass: iplanet-am-managed-group
# objectclass: iplanet-am-managed-static-group




@alt_people_domains=qw/
betty@cett.dc=domain,dc=org
connie@cett.dc=domain,dc=org
peter@cett.dc=domain,dc=org
sean@cett.dc=domain,dc=org
williams@dafvm.dc=domain,dc=org
vwatson@dafvm.dc=domain,dc=org
ray@dafvm.dc=domain,dc=org
mixon@dafvm.dc=domain,dc=org
vpdafvm-bus@dafvm.dc=domain,dc=org
lsinger@dafvm.dc=domain,dc=org
baker@dafvm.dc=domain,dc=org
jenkins@dafvm.dc=domain,dc=org
ljb@srdc.domain.org
rachelw@srdc.domain.org
alanb@srdc.domain.org
vickiv@srdc.domain.org
srdc-bus@srdc.domain.org
abbiem@srdc.domain.org
gburke@srdc.domain.org
robertog@srdc.domain.org
aliciab@srdc.domain.org
shannont@srdc.domain.org
/;


@alt_groups_domains=qw/
atoms@cett.dc=domain,dc=org
info@cett.dc=domain,dc=org
dha@dafvm.dc=domain,dc=org
fmgroup@dafvm.dc=domain,dc=org
fm2005@dafvm.dc=domain,dc=org
fm2006@dafvm.dc=domain,dc=org
fm2007@dafvm.dc=domain,dc=org
fm2008@dafvm.dc=domain,dc=org
fmdeptheads@dafvm.dc=domain,dc=org
fmbackupgroup@dafvm.dc=domain,dc=org
publications@srdc.domain.org
/;


#for my $d (@alt_user_domains) {
#    print "d: /$d/\n";
#}


while(<>) {
    s/\n\s+//g;

#    print "entry: /$_/\n";

    my ($dn) = /(dn:[^\n]+)\n/;
    my $d = "ext.domain.org";

    my $entry = $_;

    
    next if (!defined $dn || $dn =~ /dn:\s*ou=/);
    
#    if (defined $dn) {
#    my $d = "ext.domain.org";
    
    if (/o=piserverdb\n/i) {
#	print "$dn\n";
	if (my ($u,$b) = 
	    /pipstoreowner=([^\,]+)\,\s*o=([^\,]+)\,\s*o=piserverdb\s*/i) {
# 	    print "converting $dn..\n".
# 		"$u $b\n";
	    
	    for (@alt_people_domains) {
		my ($lhs,$rhs) = split /\@/;

#		print "comparing $u $lhs\n";
		if ($u eq $lhs) {
		    $d = $rhs;

#		    my $o_dn = $dn;

		    $dn =~ s/o=[^\,]+,/o=$d,/i;
		}
	    }

	}
    } else {

	s/mailhost:\s*[^\n]+\n/mailhost: atlas.ext.domain.org\n/;

	if (my ($u) = /dn:\s*uid=([^\,]+)\,/) {
	    # users
	    #?
	    # next if ($u eq "sean");

	    for (@alt_people_domains) {
		# print "$_\n";
		my ($lhs,$rhs) = split /\@/;
		# print "$lhs $rhs\n";
		
		if ($u eq $lhs) {
		    $d = $rhs;
		    print STDERR "changed domain, $lhs $d\n"
		}
	    }


	} elsif (my ($g) = /dn:\s*cn=([^\,]+)\,/) {
	    # groups (aliases)

	    for (@alt_groups_domains) {
		# print "$_\n";
		my ($lhs,$rhs) = split /\@/;
		# print "$lhs $rhs\n";
		
		if ($g eq $lhs) {
		    $d = $rhs;
		    print STDERR "changed domain, $lhs $d\n"
		}
	    }

	    s/memberurl:\s*ldap:\/\/\/o=ext.domain.org/memberurl: ldap:\/\/\/o=msu_ag/ig
		if (/memberurl:\s*ldap/i);

	} else {
	    print "WARNING: $dn has neither uid or cn, ignoring.\n";
	    print "entry:\n/$_/\n";
	    exit
	}

	
	#print "u: $u $d\n";
	
	$dn =~ s/o=ext.domain.org,\s*o=ext.domain.org/o=${d},o=msu_ag/;

	# print "dn: /$dn/\n";
	

#}
    }
	s/dn:[^\n]+\n//;
	s/#[^\n]+\n//;
	print "$dn\n$_\n\n";
}
