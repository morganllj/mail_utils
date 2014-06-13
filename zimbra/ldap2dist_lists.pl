#!/usr/bin/perl -w
#

use strict;
use lib "/usr/local/zcs-6.0.7_GA_2483-src/ZimbraServer/src/perl/soap";
use XmlElement;
use XmlDoc;
use Soap;
use Net::LDAP;

my $zimbra_svr = "dmail01.domain.org";
my $zimbra_pass = "pass";
my $default_domain = "dev.domain.org";

my $url = "https://" . $zimbra_svr . ":7071/service/admin/soap/";
my $SOAP = $Soap::Soap12;

################
# Zimbra SOAP
my $ACCTNS = "urn:zimbraAdmin";
my $MAILNS = "urn:zimbraAdmin";

# authenticate to Zimbra admin url
my $d = new XmlDoc;
$d->start('AuthRequest', $ACCTNS);
$d->add('SessionId', undef, undef, undef);
$d->add('name', undef, undef, "admin");
$d->add('password', undef, undef, $zimbra_pass);
$d->end();

# get back an authResponse, authToken, sessionId & context.
my $authResponse = $SOAP->invoke($url, $d->root());
my $authToken = $authResponse->find_child('authToken')->content;
#my $sessionId = $authResponse->find_child('sessionId')->content;
my $context = $SOAP->zimbraContext($authToken, undef);

my $ldap = Net::LDAP->new("ldaps://testsgldap-mgmt.domain.net") or die "$@";
$ldap->bind(dn=>"cn=directory manager", password=>"pass");

my $sr = $ldap->search(base => "dc=domain,dc=org", filter => "(&(objectclass=orgStudent)(|(uid=0000001)(uid=0000002)(uid=0000003)(uid=0000004)(uid=0000005)(uid=0000006)(uid=0000007)))", 
		      attrs => "uid");

my $s = $sr->as_struct();

# for my $dn (keys %$s) {
# #    print "$dn\n";
#     print "$s->{$dn}->{uid}[0]\n";
# }




for my $dn (keys %$s) {
#    print "$dn\n";
    print "$s->{$dn}->{uid}[0]\n";

    my $uid = $s->{$dn}->{uid}[0];
    my $remote_addr = $s->{$dn}->{uid}[0] . "\@google.domain.org";


    my $d1 = new XmlDoc;

#    print "adding $t $n..\n";
	    
    $d1->start('CreateDistributionListRequest', $MAILNS);
    $d1->add('name', $MAILNS, undef, $uid . "\@" . $default_domain);
    $d1->add('a', $MAILNS, {"n" => "zimbraMailStatus"}, "enabled");
    $d1->add('a', $MAILNS, {"n" => "zimbraHideInGal"}, "TRUE");
    $d1->add('a', $MAILNS, {"n" => "description"}, "googledist");
    $d1->end;
	    
    my $r = $SOAP->invoke($url, $d1->root(), $context);
    # TODO: error checking!

    # print "add result: ", $r->name, "\n";
    if ($r->name eq "Fault") {
	print "Error adding $uid, skipping.\n";
	print Dumper ($r);
	return;
    }

    my $z_id;
    for my $child (@{$r->children()}) {
	for my $attr (@{$child->children}) {
	    $z_id = $attr->content()
	      if ((values %{$attr->attrs()})[0] eq "zimbraId");
	}
    }

    my $d2 = new XmlDoc;
	    
#    if ($#members > -1) {
	$d2->start ('AddDistributionListMemberRequest', $MAILNS);
	$d2->add ('id', $MAILNS, undef, $z_id);

	# for (@members) {
	#     $_ .= "\@" . $default_domain
	#       if ($_ !~ /\@/);
#	     $d2->add ('dlm', $MAILNS, undef, $_);
	     $d2->add ('dlm', $MAILNS, undef, $remote_addr);
	# }
	$d2->end;


	my $r2 = $SOAP->invoke($url, $d2->root(), $context);
	if ($r2->name eq "Fault") {
	    print "error adding $uid:\n";
	    print Dumper ($r2);
	}
#    }

}
