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

sub printUsage();

getopts('ndf:', \%opts);

print "f: $opts{f}\n";
exists $opts{f} || printUsage();

print "-n used, no changes will be made\n"
  if (exists $opts{n});
print "-d used, no dist lists will be deleted\n"
  if (exists $opts{d});

my $ldap_host = "ldaps://sgldap01.domain.net";
my $ldap_bind_dn = "cn=directory manager";
my $ldap_bind_pw = "pass";
my $domain = "domain.org";
my $ldap_base = "dc=domain,dc=org";
my $forwarding_domain = "gmail-zgate-domain.domain.org";

my $filter = $opts{f};

my $zu = new ZimbraUtil;

$| = 1;

# ################
# # Zimbra SOAP
my $MAILNS = "urn:zimbraAdmin";

my $context = $zu->get_zimbra_context();

print "\nstarting at ", `date`;

print "\ngetting dist lists from zimbra...\n";
my $d3 = new XmlDoc;

$d3->start('GetAllDomainsRequest', $MAILNS);
$d3->end;

my $r = $zu->check_context_invoke($d3, \$context);
# TODO: error checking!

if ($r->name eq "Fault") {
    my $rsn = $zu->get_fault_reason($r);
    print "Error searching domains.  Reason: ", Dumper $r, "\n";
    
    next;
}

my $domain_id;

    for my $child (@{$r->children()}) {
      my $domain = (values %{$child->attrs()})[0];

      $domain_id = (values %{$child->attrs()})[1]
	if ($domain =~ /^$domain$/i);
    }

my %in_zimbra;
my $d4 = new XmlDoc;

$d4->start('GetAllDistributionListsRequest', $MAILNS); {
   $d4->add('account', $MAILNS, { "by" => "id" }, $domain_id);
} $d4->end();

my $r4 = $zu->check_context_invoke($d4, \$context);

for my $child (@{$r4->children()}) {
    my $dist_list =  (values %{$child->attrs()})[0];

    $in_zimbra{$dist_list} = 1
      if ($dist_list =~ /^\d+\@$domain/i);
}


 print "\nsearching ldap...\n";
 my $ldap = Net::LDAP->new("$ldap_host") or die "$@";
 $ldap->bind(dn=>$ldap_bind_dn, password=>$ldap_bind_pw);

 # my $sr = $ldap->search(base => "dc=domain,dc=org", filter => "(&(objectclass=orgStudent)(mail=*))", 
 # 		      attrs => "uid");
# my $sr = $ldap->search(base => "dc=domain,dc=org", filter => "(&(objectclass=orgStudent)(orghomeorgcd=2540)(mail=*))", 
#		      attrs => "uid");
 my $sr = $ldap->search(base => $ldap_base, filter => $filter, 
		      attrs => "uid");

 my $s = $sr->as_struct();


print "\nchecking forwards in zimbra...\n";
my %in_ldap;
for my $dn (keys %$s) {
     my $mail = $s->{$dn}->{mail}[0];
     my $addr = $s->{$dn}->{mail}[0];
#     $addr =~ s/domain/dev.domain/;
     $in_ldap{$addr} = 1;
 }

for my $addr (sort keys %in_ldap) {
    if (!exists $in_zimbra{$addr}) {
	print "adding $addr\n";

	unless (exists $opts{n}) {
	    my $d1 = new XmlDoc;

	    my $uid = (split /\@/, $addr)[0];
#	    my $remote_addr = $uid . "\@gmail-zgate-domain.domain.org";
	    my $remote_addr = $uid . "\@" . $forwarding_domain;

	    $d1->start('CreateDistributionListRequest', $MAILNS);
	    $d1->add('name', $MAILNS, undef, $addr);
	    $d1->add('a', $MAILNS, {"n" => "zimbraMailStatus"}, "enabled");
	    $d1->add('a', $MAILNS, {"n" => "zimbraHideInGal"}, "TRUE");
	    $d1->add('a', $MAILNS, {"n" => "description"}, "googledist");
	    $d1->end;
	    
 	    my $r = $zu->check_context_invoke($d1, \$context);
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
    
	    my $r2 = $zu->check_context_invoke($d2, \$context);

	    if ($r2->name eq "Fault") {
		print "error adding $remote_addr:\n";
		print Dumper ($r2);
	    }
	}

    }
    
}

unless (exists ($opts{d})) {
    for my $addr (sort keys %in_zimbra) {
	if (!exists $in_ldap{$addr}) {
	    print "removing $addr\n";

	    unless (exists $opts{n}) {
		my $d1 = new XmlDoc;
	
		$d1->start('GetDistributionListRequest', $MAILNS);
		$d1->add('dl', $MAILNS, { "by" => "name"}, $addr );
		$d1->add('a', $MAILNS, {"n" => "zimbraMailStatus"}, "enabled");
		$d1->end;
	    
		my $r = $zu->check_context_invoke($d1, \$context);
		# TODO: error checking!

		if ($r->name eq "Fault") {

		    my $rsn = $zu->get_fault_reason($r);
		    print "Error getting dist list while removing $addr, skipping.  Reason: ", Dumper $r, "\n";
		    next;
		}

		my $z_id;
		for my $child (@{$r->children()}) {
		    $z_id = $child->attrs->{id};
		}
 
		my $d2 = new XmlDoc;
		$d2->start ('DeleteDistributionListRequest', $MAILNS);
		$d2->add ('id', $MAILNS, undef, $z_id);
		$d2->end;
    
		my $r2 = $zu->check_context_invoke($d2, \$context);
		if ($r2->name eq "Fault") {
		    print "error removing $addr:\n";
		    print Dumper ($r2);
		}
	    }
	}
    }
}

print "\nfinished at ", `date`;



sub printUsage() {
    print "\nusage: $0 [-n][-d] -f <ldap filter>\n";
    print "\t[-d] skip deletes\n";
    print "\n";
    exit;
}
