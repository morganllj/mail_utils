#!/usr/bin/perl -w
#

#use lib "/home/morgan/zcs-5.0.0_RC1_1538-src/ZimbraServer/src/perl/soap";
use lib "/usr/local/zcs-5.0.2_GA_1975-src/ZimbraServer/src/perl/soap";

use Time::HiRes qw ( time );
use strict;

use lib '.';

use LWP::UserAgent;

use XmlElement;
use XmlDoc;
use Soap;

use Data::Dumper;

my $ACCTNS = "urn:zimbraAdmin";
my $MAILNS = "urn:zimbraAdmin";

my $url = "https://dmail01.domain.org:7071/service/admin/soap/";

# username to look up
my $name = "gab";

my $SOAP = $Soap::Soap12;


# authenticate to the server
my $d = new XmlDoc;
$d->start('AuthRequest', $MAILNS);
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


my $r;


# $d = new XmlDoc;
# $d->start('GetAccountInfoRequest', $MAILNS);
# $d->add('account', $MAILNS, { "by" => "name" }, "morgan\@dev.domain.org");
# $d->end();

# my $r = $SOAP->invoke($url, $d->root(), $context);





$d = new XmlDoc;
$d->start('DelegateAuthRequest', $MAILNS);
$d->add('account', $MAILNS, { by => "name" }, 
        "gab\@dev.domain.org");
$d->end();
$r = $SOAP->invoke($url, $d->root(), $context);
if ($r->name eq "Fault") {
    print "fault while delegating auth to gab\@dev.domain.org:\n";
    print Dumper($r);
    exit;
}
my $new_auth_token = $r->find_child('authToken')->content;
my $new_context = $SOAP->zimbraContext($new_auth_token, $sessionId);







$d = new XmlDoc;
# $d->start('GetInfoRequest', 'urn:zimbraAccount');
$d->start('GetFolderRequest', $Soap::ZIMBRA_MAIL_NS);
$d->end();


# print "\nOUTGOING XML:\n-------------\n";
# my $out =  $d2->to_string("pretty");
# $out =~ s/ns0\://g;
# print $out."\n";



# send the response to the server
# my $start = time;
# my $firstStart = time;

#my $response = $SOAP->invoke($url, $d->root(), $new_context);
my $response = $SOAP->invoke($url, $d->root(), $context);

print Dumper($response);

#for my $c (@{$response->children()->children()}) {
my $mc = (@{$response->children()})[0];
for my $c (@{$mc->children()}) {

    if (exists $c->attrs->{view} && $c->attrs->{view} eq "appointment") {
        print "cal: ", $c->attrs->{name}, "\n";
        print "owner: ", $c->attrs->{owner}, "\n"
            if (exists $c->attrs->{owner});
    }
    
    # print "c: /", Dumper $c, "/\n";
    # if (exists $c->attrs->{view} && $c->attrs->{view} eq "appointment") {
    #     print "cal: ", $c->attrs->{name}, "\n";
    # }
}

# my $acctInfo = $response->find_child('account');
# my $acctId = $acctInfo->attr("id");



# print "\nRESPONSE:\n--------------\n";
# $out =  $response->to_string("pretty");
# $out =~ s/ns0\://g;
# print $out."\n";

# print "AccountID is $acctId\n";
