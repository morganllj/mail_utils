#!/usr/bin/perl -w
#

use strict;
use lib "/opt/zimbra/zimbramon/lib";
use Net::LDAP;

my $ldap;

unless ($ldap = Net::LDAP->new( "ldap03.domain.org", timeout =>30 )) {
    die ("Connect: Unable to connect to ldap master.\n");
}
my $result = $ldap->start_tls(
	   verify => 'require',
           capath => "/opt/zimbra/conf/ca",
#           clientcert => "/opt/zimbra/conf/ca/ca.pem",
			     
			     );
if ($result->code) {
    die("Unable to start TLS: ". $result->error . " when connecting to ldap master.\n");
}

unless ($result = $ldap->bind("cn=config", password => "pass")) {
    die ("Bind: Unable to bind to ldap master.\n");
}

my $ldap_master_host=$ldap->host();
$result = $ldap->search(base => "cn=servers,cn=zimbra",
                            filter => "cn=ldap.domain.org",
                            attrs => [
                                      'zimbraServerVersionMajor',
                                      'zimbraServerVersionMinor',
                                      'zimbraServerVersionMicro',
                                      'zimbraServerVersionType',
                                      'zimbraServerVersionBuild',
                                     ]);
if ($result->code) {
      die ("Search error: Unable to search master.\n");
  }
