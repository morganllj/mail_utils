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
use Data::Dumper;
#use Net::LDAP;
# The Zimbra SOAP libraries.  Download and uncompress the Zimbra
# source code to get them.
use lib "/usr/local/zcs-5.0.2_GA_1975-src/ZimbraServer/src/perl/soap";
use XmlElement;
use XmlDoc;
use Soap;
use Net::LDAP;

# sub protos
sub print_usage();
sub sendmail_into_elements($$$);
sub sync_alias($$$$$);
sub update_in_ldap($$$);
sub merge_into_zimbra($$);
sub add_alias($$);
sub update_z_list($@);
sub lists_differ($$);
sub add_z_list($$@);
sub executable_into_z($$);


my $opts;

getopts('dna:p:z:', \%$opts);

my $alias_files = $opts->{a} || print_usage();
my $zimbra_pass = $opts->{p} || "pass";
my $zimbra_svr  = $opts->{z} || "dmail01.domain.org";

$|=1;

my $default_domain = "dev.domain.org";
# name of the host/domain where list software is running
#   all aliases with '|' will be forwarded there
my $list_mgmt_host = "dlists.domain.org";


################
# Zimbra SOAP
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


################
# Zimbra LDAP
my $z_ldap_host = "dmldap01.domain.org";
my $z_ldap_base = "dc=dev,dc=domain,dc=org";
my $z_ldap_binddn = "cn=config";
my $z_ldap_pass = "pass";

my $ldap = Net::LDAP->new($z_ldap_host) or die "$@";
$ldap->bind(dn=>$z_ldap_binddn, password=>$z_ldap_pass);






# list of alias files
my @alias_files;

if ($alias_files =~ /\,/) { 
    @alias_files = split /\s*\,\s*/, $alias_files; 
} else {
    @alias_files = ($alias_files)
}

# loop over the list of alias files, open and process each
for my $af (@alias_files) {

    print "working on $af..\n";
    my $aliases_in;
    open ($aliases_in, $af) || die "can't open alias file: $af: $!";

    while (<$aliases_in>) {
	chomp;

	my ($lhs, $rhs);
	my $rc;
  	if (my $problem = sync_alias (\$lhs, \$rhs, $_, 
  				 \&alias_into_elements,
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

#	print "/$alias/ broken into:\n\t/$$l/ /$$r/\n"
#	    if (exists $opts->{d});

    } else {
	return 1;
    }
    return 0;
}



sub alias_into_z($$) {
    my ($l, $r) = @_;
    # try to find a user in zimbra matching $r

    my ($ideal_type, $type, @z) = get_z_alias($l);
    my @t = split /\s*,\s*/, $r;

    for (@t) {
	s/^([^\@\s]+)\s*$/$1\@$default_domain/;
    }
    
    if (lists_differ(\@z, \@t) or $type eq $ideal_type) {
	update_z_list($type, $l, @t);
    } else {
	print "lists are the same, moving on..\n"
	    if (exists $opts->{d});
       
    }
}



#### sub update_z_list
# we know the recipient list is different
# we need to decide based on $type if 
#    we delete the list in Zimbra (if it exists but is the wrong type) and
#    we sync an existing list (if it exists and is the right type) or
#    add a new list (if it it's not there or we needed to delete it)
sub update_z_list($@) {
    my $existing_type = shift;
    my $l = shift;
    my @contents = @_;
    
    # if rhs is one value and it's either unqualified or @default_domain
    #    search for a user of the same name
    # if a user is found add it as an alias
    # otherwise add a dist_list and qualify it with @default_domain


    # I wonder if we need to qualify addresses after the check to see
    # if their valid users.  really it may not matter as sendmail aliases
    # currently don't check for valid users anyway.
    for (@contents) {
	# add the default domain if the account is unqualified
	$_ .= "\@" . $default_domain
	    if ($_ !~ /\@/);
    }


    # check to see if the rhs is a user, if so add forward or
    # forwards to the account
    
    print "checking for user matching lhs $l..\n";

    my $user;
    
    my $d = new XmlDoc;
    $d->start('GetAccountRequest', $MAILNS);
    $d->add('account', $MAILNS, { "by" => "name" }, $l);
    $d->end();
    
    my $r = $SOAP->invoke($url, $d->root(), $context);

# searching for "Fault" is not sufficient as a missing account will return a fault..
#    if ($r->name eq "Fault") {
	
    
#	print "problem searcing out $l:";
#	print Dumper($r)
#    }

    my $middle_child = $r->find_child('account');
    if (defined $middle_child) {
	# don't do this unless there is something there..
	
	for my $child (@{$middle_child->children()}) {
	    $user = $child->content()
		if (lc ((values %{$child->attrs()})[0]) eq "uid");
	}
    }

    if (defined $user && $user eq $l) {
	add_z_forward($l, @contents);
	return;
    }


    my $mail;
    if ($#contents == 0) {
	my $m = $contents[0];

	# check to see if the rhs is a user, if so add forward or
	# forwards to the account
	
 	print "checking for user matching rhs $m..\n";

 	my $d = new XmlDoc;
 	$d->start('GetAccountRequest', $MAILNS);
 	$d->add('account', $MAILNS, { "by" => "name" }, $m);
 	$d->end();

 	my $r = $SOAP->invoke($url, $d->root(), $context);
 	my $middle_child = $r->find_child('account');
 	if (defined $middle_child) {
 	    # don't do this unless there is something there..

 	    for my $child (@{$middle_child->children()}) {
 		$mail = $child->content()
 		    if (lc ((values %{$child->attrs()})[0]) eq "mail");
 	    }
 	}
    }
    

    # should we pass the type here since we're determining it anyway?
    if (defined $mail) {
	# add an alias/forward
	delete_z_list($l, $existing_type)
	    if ($existing_type ne "alias");
	add_z_list("alias", $l, @contents);
    } elsif ( $#contents > -1) {
	# add a dist list
	delete_z_list($l, $existing_type);
	add_z_list("distributionlist", $l, @contents)
	    if ($existing_type ne "dist_list");
    } else { # $#contents < 0
	# There's a list in the alias file that has no valid
	# recipients, delete it.
	delete_z_list($l, $existing_type);
    }
}



sub add_z_forward($@) {
    my ($user, @forwards) = @_;

    for (@forwards) {
	s/^\s*\\//;
    }

    if ($user !~ /\@/) {
	$user .= "\@".$default_domain;
    }


    if ($#forwards == 0) {
	$user        =~ s/domain\.org/dev.domain.org/
	    if ($user !~ /dev.domain.org/);
	$forwards[0] =~ s/domain\.org/dev.domain.org/
	    if ($forwards[0] !~ /dev.domain.org/);
	
    }

    # zimbra forwarding from mail.domain to domain makes some of these
    # forwards irrelevant
    return if (lc $user eq lc $forwards[0]);

    print "adding forward, /$user/: " . join ' ', @forwards, "\n";

    # if an address in @forward matches $user deliver locally & forward
    
    my $id;
    my $d = new XmlDoc;

    $d->start('GetAccountRequest', $MAILNS); 
    $d->add('account', $MAILNS, { "by" => "name" }, $user);
    $d->end();

    my $r = $SOAP->invoke($url, $d->root(), $context);

    my $middle_child = $r->find_child('account');
     #my $delivery_addr_element = $r->find_child('zimbraMailDeliveryAddress');

    # user entries return a list of XmlElements
    return undef if !defined $middle_child;
    for my $child (@{$middle_child->children()}) {
	# TODO: check for multiple attrs.  The data structure allows
	#     it but I don't think it will ever happen.
	#print "content: " . $child->content() . "\n";
	#print "attrs: ". (values %{$child->attrs()})[0];
	# print ((values %{$child->attrs()})[0], ": ", $child->content(), "\n");
	

	#$id =  $child->content();
	if ((values %{$child->attrs()})[0] eq "zimbraId") {
	    $id = $child->content();
	}
    }

    my $d2 = new XmlDoc;    
    print "modifing id: $id\n";
    $d2->start('ModifyAccountRequest', $MAILNS);
    $d2->add('id', $MAILNS, undef, $id);
    $d2->add('a', $MAILNS, 
	     { "n" => "zimbraFeatureMailForwardingEnabled"},
	     "TRUE");


    for my $f (@forwards) {
	my $forward_to = $f;
	$forward_to .= "\@" . $default_domain
	    unless ($forward_to =~ /\@/);

	print "adding $user: $forward_to\n";
	$d2->add('a', $MAILNS,
		 { "n" => "zimbraPrefMailForwardingAddress" },
		 $forward_to)
    }
    $d2->end();

    my $r2 = $SOAP->invoke($url, $d2->root(), $context);

    if ($r2->name eq "Fault") {
	print "Error adding forward(s) to $user, skipping.\n";
	return;
    }

}


sub add_z_list($$@) {
        my ($t, $n, @members) = @_;

        if ($t eq "distributionlist") {
	    my $d = new XmlDoc;

	    print "adding $t $n..\n";
	    
	    $d->start('CreateDistributionListRequest', $MAILNS);
	    $d->add('name', $MAILNS, undef, $n."\@". $default_domain);
	    $d->add('a', $MAILNS, {"n" => "zimbraMailStatus"}, "enabled");
	    $d->add('a', $MAILNS, {"n" => "zibraHideInGal"}, "TRUE");
	    $d->end;
	    
	    my $r = $SOAP->invoke($url, $d->root(), $context);
	    # TODO: error checking!

	    # print "add result: ", $r->name, "\n";
	    if ($r->name eq "Fault") {
		print "Error adding $n, skipping.\n";
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
	    
	    $d2->start ('AddDistributionListMemberRequest', $MAILNS);
	    $d2->add ('id', $MAILNS, undef, $z_id);
	    for (@members) {
		$_ .= "\@" . $default_domain
		    if ($_ !~ /\@/);
		$d2->add ('dlm', $MAILNS, undef, $_);
	    }
	    $d2->end;

	    my $r2 = $SOAP->invoke($url, $d2->root(), $context);
	    if ($r2->name eq "Fault") {
		print "error adding $n:\n";
		print Dumper ($r2);
	    }

	} elsif ($t eq "alias") {
	    print "adding $n of type $t to $members[0]\n";

	    my $z_id = get_account_id_by_name($members[0]);

	    my $d = new XmlDoc;
	    $d->start('AddAccountAliasRequest', $MAILNS);
	    $d->add('id', $MAILNS, undef, $z_id);
	    #my $a = $n . $default_domain;
	    $d->add('alias', $MAILNS, undef, $n . "\@" . $default_domain);
	    #$d->add('alias', $MAILNS, undef, $a);
	    $d->end;
	    my $r = $SOAP->invoke($url, $d->root(), $context);
	    

# TODO: see if alias exists before blindly adding it and ignoring the result
# 	    if ($r->name eq "Fault") {
# 		print "error adding $n:\n";
# 		print Dumper ($r);
		
# 	    }

	} else {
	    print "unknown type type $t in add_z_list!?\n";
	}
}


sub get_account_id_by_name($) {
    my $name = shift;

    my $d = new XmlDoc;

    $d->start('GetAccountRequest', $MAILNS); 
    $d->add('account', $MAILNS, { "by" => "name" }, $name);
    $d->end();
    
    my $r = $SOAP->invoke($url, $d->root(), $context);
    
    my $middle_child = $r->find_child('account');
    #my $delivery_addr_element = $r->find_child('zimbraMailDeliveryAddress');

    # user entries return a list of XmlElements
    return undef if !defined $middle_child;
    for my $child (@{$middle_child->children()}) {
	# TODO: check for multiple attrs.  The data structure allows
	#     it but I don't think it will ever happen.
	#print "content: " . $child->content() . "\n";
	#print "attrs: ". (values %{$child->attrs()})[0];
	# print ((values %{$child->attrs()})[0], ": ", $child->content(), "\n");
	
	
	#$id =  $child->content();
	if ((values %{$child->attrs()})[0] eq "zimbraId") {
	    return $child->content();
	}
    }
    return undef; # no id found
}



sub delete_z_list($$) {
    my ($n, $t) = @_;

    my $d = new XmlDoc;

    if ($t eq "distributionlist") {

	# search out the zimbraId

	my $fil = "(&(objectclass=zimbraDistributionList)(uid=$n))";
	print "searching ldap for dist list with $fil\n"
	    if ($opts->{n});
	
	my $sr = $ldap->search(base=>$z_ldap_base, filter=>$fil);
	$sr->code && die $sr->error;
	
	my @mbrs;
	my $z_id;
	for my $l_dist ($sr->entries) {
	    $z_id = $l_dist->get_value("zimbraId");
	    
	    #print "list: $list\n";
	    #print "members: " , join ' ', @mbrs , "\n";
	}

	if (defined $z_id) {
	    # list exists, delete it

	    print "deleting list $n with id $z_id\n"
		if (exists $opts->{d});

	    $d->start('DeleteDistributionListRequest', $MAILNS);
	    $d->add('id', $MAILNS, undef, $z_id);
	    $d->end();

	    my $r = $SOAP->invoke($url, $d->root(), $context);

	}

    } elsif ($t eq "alias") {
	print "would delete $n of type $t\n";
    } else {
	print "unknown type type $t in delete_z_list!?\n";
    }
}



sub lists_differ ($$) {
    my ($l1, $l2) = @_;

    my @l1 = sort @$l1;
    my @l2 = sort @$l2;

    if (exists $opts->{d}) {
	print "comparing lists:\n";
	print "\t", join (' ', @l1), " and\n";
	print "\t", join (' ', @l2), "\n";
    }

    return 1 if ($#l1 != $#l2);

    my $i = 0;
    for (@l1) {
	return 1 if ($l1[$i] ne $l2[$i]);
    }
    return 0;
}



sub get_z_alias () {
#    my ($name, $types) = @_;
    my ($name) = @_;



# search with Zimbra SOAP doesn't seem to work
#     $types = "distributionlists"
# 	if (!defined $types);

#     my $query = "(|(uid=*$name*)(cn=*$name*)(sn=*$name*)(gn=*$name*)(displayName=*$name*)(zimbraId=$name)(mail=*$name*)(zimbraMailAlias=*$name*)(zimbraMailDeliveryAddress=*$name*)(zimbraDomainName=*$name*))";

#     my $d = new XmlDoc;
    
#     # search for a distribution list
#     $d->start('SearchDirectoryRequest', $MAILNS); 
#     $d->add('query', $MAILNS, {"types" => $types}, $query);
#     $d->end;

#     my $r = $SOAP->invoke($url, $d->root(), $context);
#     if ($r->name eq "Fault") {
#  	print "Fault while getting zimbra alias:\n";
#  	return;
#     }
    
#     print Dumper ($r);


    # default to distribution list
    my $t = "distributionlist";

    my $fil = "(&(objectclass=zimbraDistributionList)(uid=$name))";
    print "searching ldap for dist list with $fil\n"
	if (exists $opts->{d});

    my $sr = $ldap->search(base=>$z_ldap_base, filter=>$fil);
    $sr->code && die $sr->error;

    my @mbrs;
    for my $l_dist ($sr->entries) {
	my $list = $l_dist->get_value("uid");
	@mbrs = $l_dist->get_value("zimbramailforwardingaddress");

	#print "list: $list\n";
	#print "members: " , join ' ', @mbrs , "\n";
    }
    
    
    
    my $fil2 = "(zimbramailalias=$name\@$default_domain)";

    my $d = new XmlDoc;
    $d->start('SearchDirectoryRequest', $MAILNS); 
    $d->add('query', $MAILNS, undef, $fil2);
    $d->end;
    
    my $r = $SOAP->invoke($url, $d->root(), $context);
    if ($r->name eq "Fault") {
  	print "Fault while getting zimbra alias:\n";
  	return;
    }

    my $user;
    my $middle_child = $r->find_child('account');
    if (defined $middle_child) {
	# don't do this unless there is something there..
	
	for my $child (@{$middle_child->children()}) {
	    $user = $child->content()
		if (lc ((values %{$child->attrs()})[0]) eq "mail");
	}
    }


    # ideal type
    my $it = "distribution_list";
    $it = "alias" if defined $user;
    
    return ($it, $t, @mbrs);
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

sub executable_into_z($$) {
    my ($l, $r) = @_;
    
    # build a Zimbra distribution list forwarding to $list_mgmt_host

    print "calling alias_into_z from executable_into_z\n";
    alias_into_z($l, $l . "\@$list_mgmt_host");
}

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

    print "\nalias: /$$l: $$r/\n"
	if (exists $opts->{d});
 
    if    ($$r =~ /^\s*[$sa]+\s*$/) {
	print "single alias..\n"
	    if (exists $opts->{d});
        alias_into_z($$l, $$r);
    } elsif ($$r =~ /^\s*\/dev\/null\s*$/) {
	print "dev null alias..\n"
	    if (exists $opts->{d});
    } elsif ($$r =~ /^\s*[$sa$ma]+\s*$/) {
	print "multiple alias..\n"
	    if (exists $opts->{d});
	alias_into_z($$l, $$r);
    } elsif ($$r =~ /^\s*${ia}[$sa$ea]+\s*$/) {
	print "included alias..\n"
	    if (exists $opts->{d});
    } elsif ($$r =~ /^\s*[$sa$ea]+\s*$/) {
	print "executable alias..\n"
	    if (exists $opts->{d});
	executable_into_z($$l, $$r);
    } elsif ($$r =~ /^\s*${ia}${ea}|${ea}${ia}\s*$/) {

	# TODO: wrong!
        # alias: /t: wilkins		: twilkins@mlp.domain.org/
        # executable and included alias..

	print "executable and included alias..\n"
	    if (exists $opts->{d});
	executable_into_z($$l, $$r);
    } else {
	print "can't categorize this alias..\n"
	    if (exists $opts->{d});
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



# <soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope">
#     <soap:Header>
#         <context xmlns="urn:zimbra">
#             <userAgent xmlns="" name="ZimbraWebClient - FF3.0 (Linux)"/>
#             <sessionId xmlns="" id="318"/>
#             <format xmlns="" type="js"/>
#             <authToken xmlns="">
#                 0_8613c974d429d5d76eee4bb1f6bf78f33b9e5f3e_69643d33363a38323539616631392d313031302d343366392d613338382d6439393038363234393862623b6578703d31333a313231343631303739343739373b61646d696e3d313a313b747970653d363a7a696d6272613b6d61696c686f73743d31363a3137302e3233352e312e3234313a38303b
#             </authToken>
#         </context>
#     </soap:Header>
#     <soap:Body>
#         <CreateDistributionListRequest xmlns="urn:zimbraAdmin">
#             <name xmlns="">
#                 testmultiple@dev.domain.org
#             </name>
#             <a xmlns="" n="zimbraMailStatus">
#                 enabled
#             </a>
#         </CreateDistributionListRequest>
#     </soap:Body>
# </soap:Envelope>



# <soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope">
#     <soap:Header>
#         <context xmlns="urn:zimbra">
#             <userAgent xmlns="" name="ZimbraWebClient - FF3.0 (Linux)"/>
#             <sessionId xmlns="" id="318"/>
#             <format xmlns="" type="js"/>
#             <authToken xmlns="">
#                 0_8613c974d429d5d76eee4bb1f6bf78f33b9e5f3e_69643d33363a38323539616631392d313031302d343366392d613338382d6439393038363234393862623b6578703d31333a313231343631303739343739373b61646d696e3d313a313b747970653d363a7a696d6272613b6d61696c686f73743d31363a3137302e3233352e312e3234313a38303b
#             </authToken>
#         </context>
#     </soap:Header>
#     <soap:Body>
#         <AddDistributionListMemberRequest xmlns="urn:zimbraAdmin">
#             <id xmlns="">
#                 3c67539f-97a4-4960-bb8c-5b19714497b7
#             </id>
#             <dlm xmlns="">
#                 morgan@dev.domain.org
#             </dlm>
#             <dlm xmlns="">
#                 morgantest@dev.domain.org
#             </dlm>
#         </AddDistributionListMemberRequest>
#     </soap:Body>
# </soap:Envelope>



