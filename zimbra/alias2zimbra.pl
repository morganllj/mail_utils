#!/usr/bin/perl -w
#
# alias2ldap.pl
# Author: Morgan Jones (morgan@morganjones.org)
# Id:     $Id$
#
# A generalized sendmail-style alias file to Zimbra sync tool
#

use strict;
use Getopt::Std;
#use Net::LDAP;
# The Zimbra SOAP libraries.  Download and uncompress the Zimbra
# source code to get them.
use lib "/home/morgan/Docs/zimbra/zcs-5.0.2_GA_1975-src/ZimbraServer/src/perl/soap";
use XmlElement;
use XmlDoc;
use Soap;

# sub protos
sub print_usage();
sub sendmail_into_elements($$$);
sub sync_alias($$$$$);
sub update_in_ldap($$$);
sub merge_into_zimbra($$);
sub add_alias($$);
sub lists_differ($$);


my $opts;

getopts('dna:p:z:', \%$opts);

my $alias_files = $opts->{a} || print_usage();
my $zimbra_pass = $opts->{p} || "pass";
my $zimbra_svr  = $opts->{z} || "dmail01.domain.org";

$|=1;
my $ACCTNS = "urn:zimbraAdmin";
my $MAILNS = "urn:zimbraAdmin";

my $url = "https://" . $zimbra_svr . ":7071/service/admin/soap/";
my $SOAP = $Soap::Soap12;

# authenticate to Zimbra admin url
my $d = new XmlDoc;
$d->start('AuthRequest', $ACCTNS);
$d->add('name', undef, undef, "admin");
$d->add('password', undef, undef, $zimbra_pass);
$d->end();

# get back an authResponse, authToken, sessionId & context.
my $authResponse = $SOAP->invoke($url, $d->root());
my $authToken = $authResponse->find_child('authToken')->content;
my $sessionId = $authResponse->find_child('sessionId')->content;
my $context = $SOAP->zimbraContext($authToken, $sessionId);


# our environment only does program delivery for delivery to majordomo lists.
#   we forward all aliases that do program delivery to an external host.
my $list_mgmt_host = qw/lists.domain.org/;

# list of alias files
my @alias_files;

if ($alias_files =~ /\,/) { 
    @alias_files = split /\s*\,\s*/, $alias_files; 
} else {
    @alias_files = ($alias_files)
}

# loop over the list of alias files, open and process each
for my $af (@alias_files) {
    my $aliases_in;
    open ($aliases_in, $af) || die "can't open /$af/";

    while (<$aliases_in>) {
	chomp;

	my ($lhs, $rhs);
	my $rc;
 	if (my $problem = sync_alias (\$lhs, \$rhs, $_, 
 				 \&alias_into_elements,
# 				 \&merge_into_ldap)) {
 				 \&merge_into_zimbra)) {
 	    print "skipping /$_/,\n\treason: $problem\n";
 	    next;
 	}
    }
}






sub print_usage() {
    print "usage: $0 [-d] [-n] -a <alias file1>,[<alias file2>],...\n\n";
    exit;
}


######
# sub sync_alias()
# break $alias into left ($l) and right ($r) elements using $into_elements_func
# merge into data store with $into_data_store_func
sub sync_alias($$$$$) {
    my ($l, $r, $alias, $into_elements_func, $into_data_store_func) = @_;

    my $ief_prob;
    $ief_prob = $into_elements_func->($l, $r, $alias) && return $ief_prob;
    $into_data_store_func->($l, $r) if (defined $$l && defined $$r);

}


######
# $into_elements_func alias_into_elements
#   Break a sendmail-style alias into elements (left and right hand sides)
sub alias_into_elements($$$) {
    my ($l, $r, $alias) = @_;

    # skip comments and blank lines
    return 0 if (/^\s*$/ || /^\s*\#/);
    # if ($alias =~ /\s*([^:\s+]+)(?:\s+|:):*\s*([^\s+]+|.*)\s*/) {

    if ($alias =~ /\s*([^:\s+]+)(?:\s+|:):*\s*(.*)\s*$/) {
	$$l = $1;
	$$r = $2;

	print "/$alias/ broken into:\n\t/$$l/ /$$r/\n"
	    if (exists $opts->{d});

    } else {
	return 1;
    }
    return 0;
}


sub sync_alias($$) {
    my ($l, $r) = @_;
    # try to find a user in zimbra matching $r

    my $d = new XmlDoc;

    my @z = get_z_aliases();
    my @t = split /\s*,\s*/, $r;
    
    if (lists_differ(\@z, \@t) ) {
	update_z_alias($l, @t);
    }
}


sub update_z_alias(@) {
    my $l = shift;
    my @contents = @_;
    
    print "updating zimbra list $l: ", join(', ', @l), "\n";
}


sub lists_differ {
    my ($l1, $l2) = @_;

    my @l1 = sort @$l1;
    my @l2 = sort @$l2;

    return 1 if ($#l1 != $#l2);

    my $i = 0;
    for (@l1) {
	return 1 if ($l1[$i] ne $l2[$i]);
    }
    return 0;
}



sub get_z_alias () {
    my ($name, $types) = @_;

    $types = "aliases,distributionLists"
	if (!defined $types);

    # search for a distribution list
    $d->start('SearchDirectoryRequest', $MAILNS);
    $d->add('query', $MAILNS, {"types" => $types},
	    "(|(uid=*$l*)(cn=*$l*)(sn=*$l*)(gn=*$l*)(displayName=*$l*)(zimbraId=$l)(mail=*$l*)(zimbraMailAlias=*$l*)(zimbraMailDeliveryAddress=*$l*)(zimbraDomainName=*$l*))");
    $d->end;

    my $r = SOAP->invoke($url, $d->root(), $context);
    if ($r->name eq "Fault") {
	print "Fault while getting zimbra alias:\n";
	return;
    }

    print Dump (@r);

 #     for my $child (@{$r->children}) {
	
#     }
    
}


# sub sync_multiple($$) {
#     my ($l, $r) = @_;
    
#     # build a Zimbra distribution list
    
    
# }



# sub included_into_z($$) {
#     my ($l, $r) = @_;

#     # open included file
#     my @a = get_addresses($r);
#     # build a Zimbra distribution list with the contents

# }

# sub executable_into_z($$) {
#     my ($l, $r) = @_;

#     # break up $r
    
#     # build a Zimbra distribution list forwarding to $list_mgmt_host

# }

# # TODO: executable + included?
# sub executable_plus_include_into_z($$) {
#     my ($l, $r) = @_;
    
#     # create one Zimbra distribution list:
#     #     forward to $list_mgmt_host
    
#     #     and build list from included file
#     my @a = get_addresses($r);

# }


######
# $into_data_store_func merge_into_zimbra
#   Merge an alias broken into left and right parts into ldap.
sub merge_into_zimbra ($$) {
    my ($l, $r) = @_;
    # $opts->{d} && print "\nmerging into Zimbra: /$$l/ /$$r/\n";

    # alias types:


    return "left hand side of alias failed sanity check"
	if ( $$l !~ /^\s*[a-zA-Z0-9\-_\.]+\s*$/);

    return "right hand side of alias failed sanity check."
        if (# examples to justify certain characters included in regex:
	    #
	    # char     example
	    # \/       alias_to_nowhere: /dev/null
	    # \\       olduser: \olduser,currentuser1,currentuser2
	    # :        alias   : :include:/path/to/textfile
	    # |        alias: "|/path/to/executable"
	    # \"       alias: "|/path/to/executable"
	    # \s       alias: user1, user2
	    #
	    $$r !~ /^\s*[a-zA-Z0-9\-_\,\@\.\/\\:|\"\s]+\s*$/ );


    # the lhs is always the alias, by now we know it's valid
    # the rhs is a
    #     - single or multple instances of
    #         - relative address         (morgan)
    #         - fully qualified adress   (morgan@morganjones.org)
    #     - path to an executable        (|/usr/local/bin/majordomo)
    #     - path to an included file     (: :include:/usr/local/lib/addresses)

    # single relative address
    #     morgan.jones: morgan
    # check that lhs exists in Zimbra, add as alias to that user


    # these are additive, in fact must be combined in most cases.
    # single alias
    my $sa = '\\\a-zA-Z0-9\-\_\.';
    # multiple alias
    my $ma = '\,@\s{1}';
    # included alias
    my $ia = ':include:\/';
    # executable alias
    my $ea = '|\/\s{1}@\"';

    #print "sa: /$sa/\n";

    print "\nalias: /$$l: $$r/\n";
 
    if    ($$r =~ /^\s*[$sa]+\s*$/) {
	print "single alias..\n";
        alias_into_z($$l, $$r);
    } elsif ($$r =~ /^\s*\/dev\/null\s*$/) {
	print "dev null alias..\n";

    } elsif ($$r =~ /^\s*[$sa$ma]+\s*$/) {
	print "multiple alias..\n";
	alias_into_z($$l, $$r);

    } elsif ($$r =~ /^\s*${ia}[$sa$ea]+\s*$/) {
	print "included alias..\n";

    } elsif ($$r =~ /^\s*[$sa$ea]+\s*$/) {
	print "executable alias..\n";

    } elsif ($$r =~ /^\s*${ia}${ea}|${ea}${ia}\s*$/) {
	print "executable and included alias..\n";
    } else {
	print "can't categorize this alias..\n";
    }





    # single full qualified address or multiple addresses
    #     systems: morgan@morganjones.org, tom@domain.com
    #     morgan.jones: morgan@morganjones.org
    # create zimbra distribution list

    # path to an executable
    #     majordom: |/usr/local/majordomo
    #     forward to $list_mgmt_host
    # TODO: revisit and generalize this assumption.. not all
    #       deliveries to an executable are going to lists

    # path to included file
    #     read contents of file and treat as above.

    return 0;    

}



sub add_alias($$) {
    my ($l, $r) = @_;

    # figure out the best way to add the entry:
    #   alias type == "local_user": add mailalternateaddress to user's entry
    #   alias type == "multiple":   add mail group
    #   alias type == "included_file": read the contents of the file and create a mail group
    #         or (?!) forward to majordomo host
    #   alias type == "prog_delivery": forward to majordomo host



#    print "in add_alias..\n";
    return 0;
}




# Identifies type of alias based on contents of rhs.
# sub alias_type($) {
#     my $r = shift;
	       
#     # print "r: $$r\n";

#     my $alias_type;
#     if ($$r =~ /^\s*[a-zA-Z0-9_\-_\.\\]+$/) {
# 	# one local user
# 	return "local_user";
#     } elsif ($$r =~ /^\s*[a-zA-Z0-9_\-\.\@\s\,\\]+$/) {
# 	# one non-local address or multiple addresses.
# 	# print "one nonlocal or multiple addresses: $$l: $$r\n";
# 	return "multiple";
#      } elsif ($$r =~ /:\s*include\s*:/ &&
# 	      $$r =~ /^\s*[a-zA-Z0-9_\-\.\@\s\,\\\/:]+$/) {
# 	 # included file
# 	 # print "included file: $$l: $$r\n";
# 	 return "included_file";
#      } elsif ($$r =~ /^\s*"\|[a-zA-Z0-9_\-\.\@\s\,\\\/:"]+$/) {
# 	 # deliver to a program
#          # print "deliver to a program: $$l: $$r\n";
#          return "prog_delivery";
#      } else {
#          return "unknown";
#      }
# }





# AddAccountAliasRequest:
# <soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope">
#     <soap:Header>
#         <context xmlns="urn:zimbra">
#             <userAgent name="ZimbraWebClient - FF2.0 (Linux)" version="undefined"/>
#             <sessionId id="233"/>
#             <authToken>
#                 0_140458fb56f1ddfc322a2f7e717f7cc8c3d135e3_69643d33363a30616261316231362d383364352d346663302d613432372d6130313737386164653032643b6578703d31333a313230363038333437323339353b61646d696e3d313a313b
#             </authToken>
#             <format type="js"/>
#         </context>
#     </soap:Header>
#     <soap:Body>
#         <AddAccountAliasRequest xmlns="urn:zimbraAdmin">
#             <id>
#                 2539f3c9-472c-449c-a707-b6016c534d05
#             </id>
#             <alias>
#                 morgan.jones@mail0.domain.org
#             </alias>
#         </AddAccountAliasRequest>
#     </soap:Body>
# </soap:Envelope>





# search out all aliases:
# <soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope">
#     <soap:Header>
#         <context xmlns="urn:zimbra">
#             <userAgent name="ZimbraWebClient - FF2.0 (Linux)" version="undefined"/>
#             <sessionId id="276"/>
#             <authToken>
#                 0_93974500ed275ab35612e0a73d159fa8ba460f2a_69643d33363a30616261316231362d383364352d346663302d613432372d6130313737386164653032643b6578703d31333a313230363539303038353132383b61646d696e3d313a313b
#             </authToken>
#             <format type="js"/>
#         </context>
#     </soap:Header>
#     <soap:Body>n
#         <SearchDirectoryRequest xmlns="urn:zimbraAdmin" offset="0" limit="25" sortBy="name" sortAscending="1" attrs="displayName,zimbraId,zimbraMailHost,uid,zimbraAccountStatus,description,zimbraMailStatus,zimbraCalResType,zimbraDomainType,zimbraDomainName" types="aliases">
#             <query/>
#         </SearchDirectoryRequest>
#     </soap:Body>
# </soap:Envelope>



# find an alias
# <soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope">
#     <soap:Header>
#         <context xmlns="urn:zimbra">
#             <userAgent name="ZimbraWebClient - FF2.0 (Linux)"/>
#             <sessionId id="33282"/>
#             <format type="js"/>
#             <authToken>
#                 0_bedba0ac9ca0f700dc84fea3c1647757717ebba7_69643d33363a38323539616631392d313031302d343366392d613338382d6439393038363234393862623b6578703d31333a313230373338353334383532363b61646d696e3d313a313b747970653d363a7a696d6272613b6d61696c686f73743d31363a3137302e3233352e312e3234313a38303b
#             </authToken>
#         </context>
#     </soap:Header>
#     <soap:Body>
#         <SearchDirectoryRequest xmlns="urn:zimbraAdmin" offset="0" limit="25" sortBy="name" sortAscending="1" attrs="displayName,zimbraId,zimbraMailHost,uid,zimbraAccountStatus,zimbraLastLogonTimestamp,description,zimbraMailStatus,zimbraCalResType,zimbraDomainType,zimbraDomainName" types="aliases">
#             <query>
#                 (|(uid=*morgan*)(cn=*morgan*)(sn=*morgan*)(gn=*morgan*)(displayName=*morgan*)(zimbraId=morgan)(mail=*morgan*)(zimbraMailAlias=*morgan*)(zimbraMailDeliveryAddress=*morgan*)(zimbraDomainName=*morgan*))
#             </query>
#         </SearchDirectoryRequest>
#     </soap:Body>
# </soap:Envelope>


# find a distribution list
# <soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope">
#     <soap:Header>
#         <context xmlns="urn:zimbra">
#             <userAgent name="ZimbraWebClient - FF2.0 (Linux)"/>
#             <sessionId id="33326"/>
#             <format type="js"/>
#             <authToken>
#                 0_bedba0ac9ca0f700dc84fea3c1647757717ebba7_69643d33363a38323539616631392d313031302d343366392d613338382d6439393038363234393862623b6578703d31333a313230373338353334383532363b61646d696e3d313a313b747970653d363a7a696d6272613b6d61696c686f73743d31363a3137302e3233352e312e3234313a38303b
#             </authToken>
#         </context>
#     </soap:Header>
#     <soap:Body>
#         <SearchDirectoryRequest xmlns="urn:zimbraAdmin" offset="0" limit="25" sortBy="name" sortAscending="1" attrs="displayName,zimbraId,zimbraMailHost,uid,zimbraAccountStatus,zimbraLastLogonTimestamp,description,zimbraMailStatus,zimbraCalResType,zimbraDomainType,zimbraDomainName" types="distributionlists">
#             <query>
#                 (|(uid=*morgan*)(cn=*morgan*)(sn=*morgan*)(gn=*morgan*)(displayName=*morgan*)(zimbraId=morgan)(mail=*morgan*)(zimbraMailAlias=*morgan*)(zimbraMailDeliveryAddress=*morgan*)(zimbraDomainName=*morgan*))
#             </query>
#         </SearchDirectoryRequest>
#     </soap:Body>
# </soap:Envelope>
