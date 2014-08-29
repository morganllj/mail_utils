#!/usr/bin/perl -w
#

use strict;
use lib "/usr/local/zcs-6.0.7_GA_2483-src/ZimbraServer/src/perl/soap";
use XmlElement;
use XmlDoc;
use Soap;
use Net::LDAP;
use Data::Dumper;
use lib '/home/admin/ldap2zimbra';
use ZimbraUtil;
use Getopt::Std;

my %opts;

getopts('n', \%opts);

print "-n used, no changes will be made\n"
  if (exists $opts{n});

my $zu = new ZimbraUtil;

my $zimbra_svr = "dmail01.domain.org";
my $zimbra_pass = "pass";
my $default_domain = "dev.domain.org";

my $url = "https://" . $zimbra_svr . ":7071/service/admin/soap/";
my $SOAP = $Soap::Soap12;

$| = 1;

################
# Zimbra SOAP
my $ACCTNS = "urn:zimbraAdmin";
my $MAILNS = "urn:zimbraAdmin";

# authenticate to Zimbra admin url
my $d = new XmlDoc;
$d->start('AuthRequest', $ACCTNS);
$d->add('SessionId', undef, undef, undef);
$d->add('name', undef, undef, "admin");
$d->add('password', undef, undef, "pass");
$d->end();

# get back an authResponse, authToken, sessionId & context.
my $authResponse = $SOAP->invoke($url, $d->root());
my $authToken = $authResponse->find_child('authToken')->content;
#my $sessionId = $authResponse->find_child('sessionId')->content;
my $context = $SOAP->zimbraContext($authToken, undef);




print "\ngetting dist lists from zimbra...\n";
my $d3 = new XmlDoc;

$d3->start('GetAllDomainsRequest', $MAILNS);
$d3->end;

my $r = $SOAP->invoke($url, $d3->root(), $context);
# TODO: error checking!

if ($r->name eq "Fault") {
    my $rsn = $zu->get_fault_reason($r);
    print "Error searching domains.  Reason: ", Dumper $r, "\n";
    
    next;
}

# my $z_id;
# for my $child (@{$r->children()}) {
#     for my $attr (@{$child->children}) {
# 	$z_id = $attr->content()
# 	  if ((values %{$attr->attrs()})[0] eq "zimbraId");
#     }
# }

my $domain_id;

    for my $child (@{$r->children()}) {
#      print ( (values %{$child->attrs()})[0] , "\n");
#      print ( (values %{$child->attrs()})[0] , "\n");
#      print ( (values %{$child->attrs()})[1] , "\n");
      my $domain = (values %{$child->attrs()})[0];
      #	for my $attr (@{$child->children}) {
#	    $z_id = $attr->content()
#	      print ( (values %{$attr->attrs()})[0] , "\n");
#	}
      
      $domain_id = (values %{$child->attrs()})[1]
	if ($domain eq "dev.domain.org");
    }


#print "domain_id: $domain_id\n";


my %in_zimbra;
my $d4 = new XmlDoc;

$d4->start('GetAllDistributionListsRequest', $MAILNS); {
   $d4->add('account', $MAILNS, { "by" => "id" }, $domain_id);
} $d4->end();

my $r4 = $SOAP->invoke($url, $d4->root(), $context);

#print Dumper $r4;

for my $child (@{$r4->children()}) {
    my $dist_list =  (values %{$child->attrs()})[0];

    if ($dist_list =~ /^\d+\@dev.domain.org/) {
#	print $dist_list, "\n";
	$in_zimbra{$dist_list} = 1;
    }
}





 print "\nsearching ldap...\n";
 my $ldap = Net::LDAP->new("ldaps://testsgldap-mgmt.domain.net") or die "$@";
 $ldap->bind(dn=>"cn=directory manager", password=>"pass");

 my $sr = $ldap->search(base => "dc=domain,dc=org", filter => "(&(objectclass=Student)(mail=*))", 
		      attrs => "uid");

 my $s = $sr->as_struct();


print "\nchecking forwards in zimbra...\n";
my %in_ldap;
for my $dn (keys %$s) {
#     print "$s->{$dn}->{mail}[0]\n";

     my $mail = $s->{$dn}->{mail}[0];
     my $addr = $s->{$dn}->{mail}[0];
#     $in_ldap{$s->{$dn}->{mail}[0]} = 1;
     $addr =~ s/domain/dev.domain/;
     $in_ldap{$addr} = 1;


 }

for my $addr (sort keys %in_ldap) {
    if (!exists $in_zimbra{$addr}) {
	print "adding $addr\n";

	unless (exists $opts{n}) {
	    my $d1 = new XmlDoc;

	    my $uid = (split /\@/, $addr)[0];
	    my $remote_addr = $uid . "\@gmail-zgate-domain.dev.domain.org";
	    #	print "remote_addr: $remote_addr\n";

	    $d1->start('CreateDistributionListRequest', $MAILNS);
	    $d1->add('name', $MAILNS, undef, $addr);
	    $d1->add('a', $MAILNS, {"n" => "zimbraMailStatus"}, "enabled");
	    $d1->add('a', $MAILNS, {"n" => "zimbraHideInGal"}, "TRUE");
	    $d1->add('a', $MAILNS, {"n" => "description"}, "googledist");
	    $d1->end;
	    
	    my $r = $SOAP->invoke($url, $d1->root(), $context);
	    # TODO: error checking!

	    if ($r->name eq "Fault") {

		my $rsn = $zu->get_fault_reason($r);
		print "Error adding $addr, skipping.  Reason: ", Dumper $r, "\n";
	  
		#print Dumper ($r);
		next;
	    }

	    my $z_id;
	    for my $child (@{$r->children()}) {
		for my $attr (@{$child->children}) {
		    $z_id = $attr->content()
		      if ((values %{$attr->attrs()})[0] eq "zimbraId");
		}
	    }

	    my $d2 = new XmlDoc;
	    

	    $d2->start ('AddDistributionListMemberRequest', $MAILNS);
	    $d2->add ('id', $MAILNS, undef, $z_id);

	    $d2->add ('dlm', $MAILNS, undef, $remote_addr);

	    $d2->end;
    

	    my $r2 = $SOAP->invoke($url, $d2->root(), $context);
	    if ($r2->name eq "Fault") {
		print "error adding $remote_addr:\n";
		print Dumper ($r2);
	    }
	}

    }
    
}

for my $addr (sort keys %in_zimbra) {
    if (!exists $in_ldap{$addr}) {
	print "removing $addr\n";

	unless (exists $opts{n}) {
	    my $d1 = new XmlDoc;
	
	    $d1->start('GetDistributionListRequest', $MAILNS);
	    $d1->add('dl', $MAILNS, { "by" => "name"}, $addr );
	    $d1->add('a', $MAILNS, {"n" => "zimbraMailStatus"}, "enabled");
	    $d1->end;
	    
	    my $r = $SOAP->invoke($url, $d1->root(), $context);
	    # TODO: error checking!

	    if ($r->name eq "Fault") {

		my $rsn = $zu->get_fault_reason($r);
		print "Error getting dist list while removing $addr, skipping.  Reason: ", Dumper $r, "\n";
	  
		#print Dumper ($r);
		next;
	    }

	    my $z_id;
	    #	print Dumper $r;
	    for my $child (@{$r->children()}) {
		#    	    for my $attr (@{$child->children}) {
		#    		$z_id = $child->content()

		#	    print "child: ", Dumper $child->attrs{id}, "\n";
		#	    print "id: ", $child->attrs->{id}, "\n";
		$z_id = $child->attrs->{id};
		# if ((values %{$child->attrs()})[1] eq "id") {
		# 	$z_id = (values %{$child->attrs()})[1]
		# }
		#    	    }
	    }

	    my $d2 = new XmlDoc;
	    
	    #	print "zimbraid: $z_id\n";

	    $d2->start ('DeleteDistributionListRequest', $MAILNS);
	    $d2->add ('id', $MAILNS, undef, $z_id);
	    $d2->end;
    

	    my $r2 = $SOAP->invoke($url, $d2->root(), $context);
	    if ($r2->name eq "Fault") {
		print "error removing $addr:\n";
		print Dumper ($r2);
	    }
	}
    }

}


#     my $d1 = new XmlDoc;

#     $d1->start('CreateDistributionListRequest', $MAILNS);
#     $d1->add('name', $MAILNS, undef, $uid . "\@" . $default_domain);
#     $d1->add('a', $MAILNS, {"n" => "zimbraMailStatus"}, "enabled");
#     $d1->add('a', $MAILNS, {"n" => "zimbraHideInGal"}, "TRUE");
#     $d1->add('a', $MAILNS, {"n" => "description"}, "googledist");
#     $d1->end;
	    
#     my $r = $SOAP->invoke($url, $d1->root(), $context);
#     # TODO: error checking!

#     if ($r->name eq "Fault") {

# 	my $rsn = $zu->get_fault_reason($r);
# 	print "Error adding $uid, skipping.  Reason: ", Dumper $r, "\n";
	  
# 	  #print Dumper ($r);
# 	next;
#     }

#     my $z_id;
#     for my $child (@{$r->children()}) {
# 	for my $attr (@{$child->children}) {
# 	    $z_id = $attr->content()
# 	      if ((values %{$attr->attrs()})[0] eq "zimbraId");
# 	}
#     }

#     my $d2 = new XmlDoc;
	    

#     $d2->start ('AddDistributionListMemberRequest', $MAILNS);
#     $d2->add ('id', $MAILNS, undef, $z_id);

#     $d2->add ('dlm', $MAILNS, undef, $remote_addr);

#     $d2->end;
    
#     my $r2 = $SOAP->invoke($url, $d2->root(), $context);
#     if ($r2->name eq "Fault") {
# 	print "error adding $uid:\n";
# 	print Dumper ($r2);
#     }
# }
