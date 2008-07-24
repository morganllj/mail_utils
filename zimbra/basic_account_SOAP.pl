#!/usr/bin/perl -w
#

use lib "/home/morgan/zcs-5.0.0_RC1_1538-src/ZimbraServer/src/perl/soap";

use Time::HiRes qw ( time );
use strict;

use lib '.';

use LWP::UserAgent;

use XmlElement;
use XmlDoc;
use Soap;

my $ACCTNS = "urn:zimbraAdmin";
my $MAILNS = "urn:zimbraAdmin";

my $url = "https://dmail02.domain.org:7071/service/admin/soap/";

# username to look up
my $name = "gab";

my $SOAP = $Soap::Soap12;


# authenticate to the server
my $d = new XmlDoc;
$d->start('AuthRequest', $ACCTNS);
$d->add('name', undef, undef, "admin");
$d->add('password', undef, undef, "pass");
$d->end();

# get an authResponse, authToken, sessionId & context back.
my $authResponse = $SOAP->invoke($url, $d->root());
#print "AuthResponse = ".$authResponse->to_string("pretty")."\n";

my $authToken = $authResponse->find_child('authToken')->content;
# print "authToken($authToken)\n";

my $sessionId = $authResponse->find_child('sessionId')->content;
# print "sessionId = $sessionId\n";

my $context = $SOAP->zimbraContext($authToken, $sessionId);
# my $contextStr = $context->to_string("pretty");
# print("Context = $contextStr\n");



# create an xmlDoc
$d = new XmlDoc;
# type of request (GetAccountRequest, CreateAccountRequest)
$d->start('GetAccountRequest', $MAILNS); {
    $d->add('account', $MAILNS, { "by" => "name" }, $name);
} $d->end();

print "\nOUTGOING XML:\n-------------\n";
my $out =  $d->to_string("pretty");
$out =~ s/ns0\://g;
print $out."\n";



# send the response to the server
# my $start = time;
# my $firstStart = time;
my $response;

$response = $SOAP->invoke($url, $d->root(), $context);

my $acctInfo = $response->find_child('account');
my $acctId = $acctInfo->attr("id");



print "\nRESPONSE:\n--------------\n";
$out =  $response->to_string("pretty");
$out =~ s/ns0\://g;
print $out."\n";

# print "AccountID is $acctId\n";
