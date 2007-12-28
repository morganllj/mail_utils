#!/usr/bin/perl -w
#
# Author: Morgan Jones (morgan@morganjones.org)
# Id:     $Id$
#
# Search an enterprise ldap and add/sync/delete users to a Zimbra
# infrastructure
#
# One way sync: define attributes mastered by LDAP, sync them to
# Zimbra.  attributes mastered by Zimbra do not go to LDAP.

use strict;
use Getopt::Std;
use Net::LDAP;
use Data::Dumper;

# The Zimbra SOAP libraries.  Download and uncompress the Zimbra
# source code to get them.
use lib "/home/morgan/zcs-5.0.0_RC1_1538-src/ZimbraServer/src/perl/soap";

#use LWP::UserAgent;
use XmlElement;
use XmlDoc;
use Soap;

sub print_usage();
sub get_z2l();
sub add_user($);
sub sync_user($$);
sub get_z_user($);
sub fix_case($);
sub build_target_z_value($$);

my $opts;
getopts('h:D:w:b:em:nd', \%$opts);

$|=1;
my $ACCTNS = "urn:zimbraAdmin";
my $MAILNS = "urn:zimbraAdmin";

#my $url = "https://dmail02.domain.org:7071/service/admin/soap/";
my $url = "https://dmail01.domain.org:7071/service/admin/soap/";
my $SOAP = $Soap::Soap12;

# these accounts will never be removed or modified
#   use perl regex format.
#
#   This rule will cause you trouble if you have users that start with
#   ham. or spam.  For instance: ham.jones.  Unlikely perhaps but
#   possible.

#my @zimbra_special = qw/admin wiki spam* ham*/;
my $zimbra_special = '^admin|wiki|spam\.[a-z]+|ham\.[a-z]+|ser$';
# run SDP case fixing algorithm (fix_case()) on these attrs.
#   Basically upcase after spaces and certain chars
my @z_attrs_2_fix_case = qw/cn displayname sn givenname/;

# attributes that will not be looked up in ldap when building z2l hash
# (see sub get_z2l()
my @z2l_literals = qw/( )/;

my $ldap_host = $opts->{h}     || print_usage();
my $ldap_base = $opts->{b}     || "dc=domain,dc=org";
my $binddn =    $opts->{D}     || "cn=Directory Manager";
my $bindpass =  $opts->{w}     || "pass";
my $zimbra_domain = $opts->{m} || "dev.domain.org";
my $zimbra_default_pass = $opts->{p} || "pass";
#my $fil = "(objectclass=posixAccount)";
my $fil = "(|(orghomeorgcd=9500)(orghomeorgcd=8020)(orghomeorgcd=5020))";
#my $fil = "(|(orghomeorgcd=9500)(orghomeorgcd=8020))";


print "starting at ", `date`;
### keep track of accounts in ldap and added.
### search out every account in ldap.

# bind to ldap
my $ldap = Net::LDAP->new($ldap_host);
my $rslt = $ldap->bind($binddn, password => $bindpass);
$rslt->code && die "unable to bind as $binddn: $rslt->error";

# authenticate to Zimbra admin url
my $d = new XmlDoc;
$d->start('AuthRequest', $ACCTNS);
$d->add('name', undef, undef, "admin");
$d->add('password', undef, undef, $zimbra_default_pass);
$d->end();

# get back an authResponse, authToken, sessionId & context.
my $authResponse = $SOAP->invoke($url, $d->root());
my $authToken = $authResponse->find_child('authToken')->content;
my $sessionId = $authResponse->find_child('sessionId')->content;
my $context = $SOAP->zimbraContext($authToken, $sessionId);


print "searching out users $fil\n";
$rslt = $ldap->search(base => "$ldap_base", filter => $fil);
$rslt->code && die "problem with search $fil: ".$rslt->error;

for my $lusr ($rslt->entries) {
    my $usr = $lusr->get_value("uid");

    # skip special users
    if ($usr =~ /$zimbra_special/) {
	print "skipping special user $usr because of rule /$_/\n"
	    if (exists $opts->{d});
	next;
    }

    ### check for a corresponding zimbra account
    my $zu_h = get_z_user($usr);

    if (!defined $zu_h) {
 	add_user($lusr);
    } else {
 	sync_user($zu_h, $lusr)
    }
}


### get a list of zimbra accounts, compare to ldap accounts, delete
### zimbra accounts no longer in in LDAP.


$rslt = $ldap->unbind;

print "finished at ", `date`;



######
sub add_user($) {
    my $lu = shift;

    print "\nadding: ", $lu->get_value("uid"), ", ",
        $lu->get_value("cn"), "\n";

    my $z2l = get_z2l();

    my $d = new XmlDoc;
    $d->start('CreateAccountRequest', $MAILNS);
    $d->add('name', $MAILNS, undef, $lu->get_value("uid")."@".$zimbra_domain);
    for my $zattr (sort keys %$z2l) {
	my $v = build_target_z_value($lu, $zattr);
	$d->add('a', $MAILNS, {"n" => $zattr}, $v);
    }
    $d->end();

    my $o;
    if (exists $opts->{d}) {
	print "here's what we're going to change:\n";
	$o = $d->to_string("pretty")."\n";
	$o =~ s/ns0\://g;
	print $o."\n";
    }

    my $r = $SOAP->invoke($url, $d->root(), $context)
	if (!exists $opts->{n});


    if (exists $opts->{d} && !exists $opts->{n}) {
	$o = $r->to_string("pretty");
	$o =~ s/ns0\://g;
	print $o."\n";
    }

}

######
sub sync_user($$) {
    my ($zu, $lu) = @_;

    my $z2l = get_z2l();

    my $d = new XmlDoc();
    $d->start('ModifyAccountRequest', $MAILNS);
    $d->add('id', $MAILNS, undef, (@{$zu->{zimbraid}})[0]);

    my $diff_found=0;

    for my $zattr (sort keys %$z2l) {
	my $l_val_str = "";
	my $z_val_str = "";

	$z_val_str = join (' ', sort @{$zu->{$zattr}});

	# build the values from ldap using zimbra capitalization
	$l_val_str = build_target_z_value($lu, $zattr);

	# too much noise with a lot of users
        # if (exists $opts->{d}) {
        #     print "comparing values for $zattr:\n".
	# 	"\tldap:   $l_val_str\n".
	# 	"\tzimbra: $z_val_str\n";
	# }

	if ($l_val_str ne $z_val_str) {
	    if (exists $opts->{d}) {
		print "difference values for $zattr:\n".
		    "\tldap:   $l_val_str\n".
		    "\tzimbra: $z_val_str\n";
	    }

	    # if the values differ push the ldap version into Zimbra
	    $d->add('a', $MAILNS, {"n" => $zattr}, $l_val_str);
	    $diff_found++;
	}
    }

    $d->end();

    if ($diff_found) {

	print "\nsyncing ", $lu->get_value("uid"), ", ",
            $lu->get_value("cn"),"\n";

	my $o;
	print "here's what we're going to change:\n";
	$o = $d->to_string("pretty")."\n";
	$o =~ s/ns0\://g;
	print $o."\n";

	my $r = $SOAP->invoke($url, $d->root(), $context)
	    if (!exists $opts->{n});

	if (exists $opts->{d} && !exists $opts->{n}) {
	    print "response:\n";
	    $o = $r->to_string("pretty");
	    $o =~ s/ns0\://g;
	    print $o."\n";
	}
    }

}



######
sub print_usage() {
    print "\n";
    print "usage: $0 [-n] [-d] [-e] -h <ldap host> [-b <basedn>]\n";
    print "\t[-D <binddn>] [-w <bindpass>] [-d <Zimbra domain>]\n";
    print "\t[-p <default pass>]\n";
    print "\n";
    print "\toptions in [] are optional\n";
    print "\t-d debug\n";
    print "\t-n print, don't make changes";
    print "\t-D <binddn> Must have unlimited sizelimit, lookthroughlimit\n".
	"\t\tnearly Directory Manager privilege to view users.\n";
    print "\t-e exhaustive search.  Search out all Zimbra users and delete\n".
	"\tany that are not in your enterprise ldap.  This is probably safe\n".
	"\tunless you have more than tens of thousands of users.\n";
    print "\n";
    print "example: $0 -h ldap.domain.com -b dc=domain,dc=com -w pass\n";
    print "\n";

    exit 0;
}




sub get_z2l() {
    # left  (lhs): zimbra ldap attribute
    # right (rhs): corresponding enterprise ldap attribute.
    # 
    # It's safe to duplicate attributes on rhs.
    #
    # These need to be all be lower case
    #
    # You can use literals (like '(' or ')') but you need to identify
    # them in @z2l_literals at the top of the script.

    # orgOccupationalGroup

    return {
	"cn" =>                    ["cn"],
	"displayname" =>           ["givenname", "sn", 
				    "(", "orgoccupationalgroup", ")"],
#	"zimbrapreffromdisplay" => ["cn"],
	"sn" =>                    ["sn"],
        "givenname" =>             ["givenname"]
	};
}
    
    
sub get_z_user($) {
    my $u = shift;

    my $ret = undef;
    my $d = new XmlDoc;
    $d->start('GetAccountRequest', $MAILNS); 
    { $d->add('account', $MAILNS, { "by" => "name" }, $u);} 
    $d->end();

    my $resp = $SOAP->invoke($url, $d->root(), $context);

#    print Dumper($resp);
    my $middle_child = $resp->find_child('account');
     #my $delivery_addr_element = $resp->find_child('zimbraMailDeliveryAddress');

    # user entries return a list of XmlElements
    return undef if !defined $middle_child;
    for my $child (@{$middle_child->children()}) {
	# TODO: check for multiple attrs.  The data structure allows
	#     it but I don't think it will ever happen.
	#print "content: " . $child->content() . "\n";
	#print "attrs: ". (values %{$child->attrs()})[0];
	# print ((values %{$child->attrs()})[0], ": ", $child->content(), "\n");
	push @{$ret->{lc ((values %{$child->attrs()})[0])}}, $child->content();
     }

     #my $acct_info = $response->find_child('account');

    return $ret;
}



######
sub fix_case($) {
    my $s = shift;

    # upcase the first character after each
    my $uc_after_exp = '\s\-\/\.&\'\(\)'; # exactly as you want it in [] 
                                      #   (char class) in regex
    # upcase these when they're standing alone
    my @uc_clusters = qw/hs hr ms es avts pd/;

    # upcase char after if a word starts with this
    my @uc_after_if_first = qw/mc/;


    # uc anything after $uc_after_exp characters
    $s = ucfirst(lc($s));
    my $work = $s;
    $s = '';
    while ($work =~ /[$uc_after_exp]+([a-z]{1})/) {
	$s = $s . $` . uc $&;

	my $s1 = $` . $&;
	# parentheses and asterisks confuse regexes if they're not escaped.
	#   we specifically use parenthesis and asterisks in the cn
	$s1 =~ s/([\*\(\)]{1})/\\$1/g;

	#$work =~ s/$`$&//;
	$work =~ s/$s1//;

    }
    $s .= $work;


    # uc anything in @uc_clusters
    for my $cl (@uc_clusters) {
	$s = join (' ', map ({
	    if (lc $_ eq lc $cl){
		uc($_);
	    } else {
		    $_;
	    } } split(/ /, $s)));
    }

    
    # uc anything after @uc_after_first
    for my $cl2 (@uc_after_if_first) {

	$s = join (' ', map ({ 
 	    if (lc $_ =~ /^$cl2([a-z]{1})/i) {

		
		my $pre =   ucfirst (lc $cl2);
		my $thing = uc $1;
		my $rest =  $_;
		$rest =~ s/$cl2$thing//i;
		$_ = $pre . $thing . $rest;
 	    } else {
 		$_;
 	    }}
 	    split(/ /, $s)));
	
    }

    return $s;
}


######
#sub build_value($$$) {
#    my ($type, $lu, $zattr) = @_;
sub build_target_z_value($$) {
    my ($lu, $zattr) = @_;
    
    my $z2l = get_z2l();
    
    my $ret = join ' ', (
	map {
    	    my @ldap_v;
	    my $v = $_;
	    
	    map {
		if ($v eq $_) {
		   $ldap_v[0] = $v;
		}} @z2l_literals;

	    if ($#ldap_v < 0) {
		@ldap_v = $lu->get_value($v);
		map { fix_case ($_) } @ldap_v;
	    } else {
		@ldap_v;
	    }

	} @{$z2l->{$zattr}}
    );

    # special case rule to remove space before after open parentheses
    # and after close parentheses.  I don't think there's a better
    # way/place to do this.
    $ret =~ s/\(\s+/\(/;
    $ret =~ s/\s+\)/\)/;

    return $ret;
}




# ModifyAccount example:
#
# <soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope">
#     <soap:Header>
#         <context xmlns="urn:zimbra">
#             <userAgent name="ZimbraWebClient - FF2.0 (Linux)"/>
#             <sessionId id="3106"/>
#             <authToken>
#                 0_b70de391fdcdf4b0178bd2ea98508fee7ad8f422_69643d33363a61383836393466312d656131662d346462372d613038612d3939313766383737313532623b6578703d31333a313139363333333131363139373b61646d696e3d313a313b747970653d363a7a696d6272613b
#             </authToken>
#             <format type="js"/>
#         </context>
#     </soap:Header>
#     <soap:Body>
#         <ModifyAccountRequest xmlns="urn:zimbraAdmin">
#             <id>
#                 a95351c1-7590-46e2-9532-de20f2c5a046
#             </id>
#             <a n="displayName">
#                 morgan jones (director of funny walks)
#             </a>
#         </ModifyAccountRequest>
#     </soap:Body>
# </soap:Envelope>



# CreateAccount example:
#
# <soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope">
#     <soap:Header>
#         <context xmlns="urn:zimbra">
#             <userAgent name="ZimbraWebClient - FF2.0 (Linux)"/>
#             <sessionId id="331"/>
#             <authToken>
#                 0_d34449e3f2af2cd49b7ece9fb6dd1e2153cc55b8_69643d33363a61383836393466312d656131662d346462372d613038612d3939313766383737313532623b6578703d31333a313139363232333436303236343b61646d696e3d313a313b747970653d363a7a696d6272613b
#             </authToken>
#             <format type="js"/>
#         </context>
#     </soap:Header>
#     <soap:Body>
#         <CreateAccountRequest xmlns="urn:zimbraAdmin">
#             <name>
#                 morgan03@dmail02.domain.org
#             </name>
#             <a n="zimbraAccountStatus">
#                 active
#             </a>
#             <a n="displayName">
#                 morgan jones
#             </a>
#             <a n="givenName">
#                 morgan
#             </a>$
#             <a n="sn">
#                 jones
#             </a>
#         </CreateAccountRequest>
#     </soap:Body>
# </soap:Envelope>



# GetAccount example:
#
# <soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope">
#     <soap:Header>
#         <context xmlns="urn:zimbra">
#             <userAgent name="ZimbraWebClient - FF2.0 (Linux)"/>
#             <sessionId id="325"/>
#             <authToken>
#                 0_d34449e3f2af2cd49b7ece9fb6dd1e2153cc55b8_69643d33363a61383836393466312d656131662d346462372d613038612d3939313766383737313532623b6578703d31333a313139363232333436303236343b61646d696e3d313a313b747970653d363a7a696d6272613b
#             </authToken>
#             <format type="js"/>
#         </context>
#     </soap:Header>
#     <soap:Body>
#         <GetAccountRequest xmlns="urn:zimbraAdmin" applyCos="0">
#             <account by="id">
#                 74faaafb-13db-40e4-bd0f-576069035521
#             </account>
#         </GetAccountRequest>
#     </soap:Body>
# </soap:Envelope>
