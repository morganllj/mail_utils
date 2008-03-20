#!/usr/bin/perl -w
#
# alias2ldap.pl
# Morgan Jones (morgan@morganjones.org)
# Version 0.01
#
# A generalized sendmail-style alias file to ldap sync tool
#

use strict;
use Getopt::Std;
use Net::LDAP;

my $basedn = "dc=domain,dc=org";
my $binddn = "cn=directory manager";
my $bindpw = "pass";
my $ldaphost = "comms.demo.domain.org";
my $ldapport = 1389;

# sub protos
sub print_usage();
sub sendmail_into_elements($$$);
sub sync_alias($$$$$);
sub find_in_ldap($$);
sub update_in_ldap($$$);
#sub alias_type($);
sub remove_alias($$);
sub add_alias($$);
sub create_ldap_update($$$);


my $opts;

getopts('da:', \%$opts);

# How I decide if the alias is in LDAP: (should be schema independent)
#   search for each of @user_alias_attrs  as <attr_name>=<alias_name>@*
#   search for each of @group_alias_attrs as <attr_name>=<alias_name>
#
# How I decide what to delete:
#   Delete the entry if it contains one of @delete_entry_indicators
#   Delete the attribute from the entry if it contains
#       @user_alias_attrs or @group_alias_attrs that are not in
#       @delete_entry_indicators
#
# Delete Exception:
#   @identify_as_user: if an alias (lhs) is the same as a user, don't
#       delete the user instead:
#          - if the rhs contains \<user> add a forward
#          - otherwise complain but make no changes.
#
my @user_alias_attrs = qw/mailAlternateAddress mailEquivalentAddress mail/;
my @group_alias_attrs = qw/cn/;

my @identify_as_user = qw/inetMailUser/;
my @identify_as_group = qw/inetMailGroup/;

my @delete_entry_indicators = qw/cn mail/;

my $user_naming_attr = qw/uid/;

# our environment only does program delivery for delivery to majordomo lists.
#   we forward all aliases that do program delivery to an external host.
my $list_mgmt_host = qw/lists.domain.org/;


my $group_member_attribute = qw/rfc822MailMember/;
my $user_member_attribute = $user_alias_attrs[0];
my $user_forward_attribute = qw/mailForwardingAddress/;

my $alias_files = $opts->{a} || print_usage();


my @alias_files;

if ($alias_files =~ /\,/) { 
    @alias_files = split /\s*\,\s*/, $alias_files; 
} else {
    @alias_files = ($alias_files)
}

for my $alias_file (@alias_files) {
    my $aliases_in;
    open ($aliases_in, $alias_file) || die "can't open $alias_file";

    while (<$aliases_in>) {
	chomp;

	my ($lhs, $rhs);
	my $rc;
 	if (my $problem = sync_alias (\$lhs, \$rhs, $_, 
 				 \&alias_into_elements,
 				 \&merge_into_ldap)) {
 	    print "skipping /$_/,\n\treason: $problem\n";
 	    next;
 	}

	
    }
}



sub print_usage() {
    print "usage: $0 [-d] -a <alias file1>,[<alias file2>],...\n\n";
    exit;
}


# break $alias into left ($l) and right ($r) elements using $into_elements_func
# merge into data store with $into_data_store_func
sub sync_alias($$$$$) {
    my ($l, $r, $alias, $into_elements_func, $into_data_store_func) = @_;

    my $ief_prob;
    $ief_prob = $into_elements_func->($l, $r, $alias) && return $ief_prob;
    $into_data_store_func->($l, $r) if (defined $$l && defined $$r);
}



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
    } else {
	return 1;
    }
    return 0;
}


# $into_data_store_func merge_into_ldap
#   Merge an alias broken into left and right parts into ldap.
sub merge_into_ldap ($$) {
    my ($l, $r) = @_;

    $opts->{d} && print "\nworking on /$$l/ /$$r/\n";

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

    my $ldap_rslt;
    my $fil_result = find_in_ldap($l, \$ldap_rslt);
    return $fil_result if $fil_result;

    $opts->{d} && print $ldap_rslt->count ." entries returned from ldap\n";

    my $clu_result = create_ldap_update ($l, $r, $ldap_rslt);
    return $clu_result if $clu_result;

#    add_alias($l, $r) unless remove_alias($l, $ldp_rslt);

    return 0;

}


sub create_ldap_update($$$) {
    my ($l, $r, $ldp_rslt) = @_;

    my $type;   # user, group, include or prog_delivery
#    my $alias = $$l;  # never changes, always lhs from the alias
    #my $aliasfile_entries; # entries as we would add them to ldap.

    # contains alias attributes from file
    my $alias_in_file;



    my $_type;
    my $_member_attr;
    my $_attrs
    
    if ($$r =~ /^\s*[a-zA-Z0-9_\-_\.\\]+$/) {
	# one local user
	#$aliasfile_entries->{$user_member_attribute} = [ ($$r) ];
	$_type =        qw/user/;
	$_attrs =       [ ($$r) ];
	$_member_attr = $user_member_attribute;

    } elsif ($$r =~ /^\s*[a-zA-Z0-9_\-\.\@\s\,\\]+$/) {
	# one or more non-local address or multiple addresses.
	# could be a straight alias to multiple addresses
	# a store locally and forward (bob: \bob, bob@remote.com).
	my @r = split /\,/, $$r;
	if (grep /\\$$l/i, @r) {
# 	    $type = qw/store_forward/;
# 	    $aliasfile_entries->{$group_member_attribute} = [ grep !/\\$$l/i, @r ];
	    $_type =        qw/store_forward/;
	    $_attrs =       [ grep !/\\$$l/i, @r ];
	    $_member_attr = $user_member_attribute;
	} else {
# 	    $type = qw/group/;
# 	    $aliasfile_entries->{$group_member_attribute} = [ split /\s*,\s*/, $$r ];
	    $_type =        qw/group/;
	    $_attrs =       [ split /\s*,\s*/, $$r ];
	    $_member_attr = $user_member_attribute;
	}
    } elsif ($$r =~ /:\s*include\s*:/ &&
	     $$r =~ /^\s*[a-zA-Z0-9_\-\.\@\s\,\\\/:]+$/) {
	# included file
# 	$type = qw/include/;
 	$opts->{d} && print "included file: $$l: $$r\n";
	$_type =        qw/include/;
	$_attrs =       $list_mgmt_host;
	$_member_attr = $user_forward_attribute;

    } elsif ($$r =~ /^\s*\"\|[a-zA-Z0-9_\-\.\@\s\,\\\/:\"]+$/) {
	#$type = qw/prog_delivery/;
        # deliver to a program
	$opts->{d} && print "deliver to a program: $$l: $$r\n";

	$_type =        qw/prog_delivery/;
	$_attrs =       $list_mgmt_host;
	$_member_attr = $user_forward_attribute;
    } else {
	$opts->{d} && print "yet to be dealt with alias format: $$l: $$r\n";
	return;
    }


	$alias_in_file->{type} =        $_type;
	$alias_in_file->{member_attr} = $_member_attr; 
	$alias_in_file->{attrs} =       $_attrs


#    my $at_return = alias_type($l, $r, \$type);
#    return $at_return if ($at_return);

    $opts->{d} && print "alias type: $type\n";
    if ($aliasfile_entries && $opts->{d}) {
	for (keys %$aliasfile_entries) {
	    print "(aliasfile) $_: ", join " ", @{$aliasfile_entries->{$_}}, "\n";;
	}
    }


    for (my $i=0; $i < $ldp_rslt->count; $i++) {
	my $le = $ldp_rslt->entry($i);

	print "objectclasses: ", join " ", $le->get_value("objectclass"), "\n";

	if (map {grep /$_/i, $le->get_value("objectclass")} @identify_as_user) {
	    $opts->{d} && print "ldap entry is a user\n";
	    if ($type eq "user") {
		# we don't want to delete a user to add an alias.
		return "alias conflicts with user already in ldap.";
	    } elsif ($type eq "store_forward") {
		$opts->{d} && print "add ", join " ", @{$aliasfile_entries->{$_}}, 
		" to ", $le->get_value($user_naming_attr), "\n";
		return "unknown type $type caught at $.";
	    } elsif ($type eq "group") {

	    } elsif ($type eq "prog_delivery") {
		$opts->{d} && print "forward to $$l\@", 
	    } else {
		return "unknown type $type caught at $.";
	    }		
	} elsif (map {grep /$_/i, $le->get_value("objectclass")} @identify_as_group) {
	    $opts->{d} && print "ldap entry is a group\n";
	} else {
	    return "unable to id as user or group,".
		"\n\t\tcheck \@identify_as_user and \@identify_as_group values.".
		"\n\t\tdn: ".$le->dn;
	}
	
    }

}


sub remove_alias ($$) {
    my ($l, $ldp_rslt) = @_;

    return 0 unless $ldp_rslt->count;

#    remove_attr($ldp_rslt, @user_alias_attrs);
#    remove_entry_containing_attrs($ldap_rslt, @group_alias_attrs);


    for my $entry ($ldp_rslt->entries) {
	# Delete the attribute if the alias is in a 
        #    @user_alias_attr or @group_alias_attr
	# Delete the entry if the alias is in a @delete_entry_indicator

	print $entry->dn . "\n";
	print "delete entry:..\n";
	print "\t" . join "\n\t",  map {$entry->get_value($_)} @delete_entry_indicators;

	print "\n" . "delete attrs:\n";
	print "\t" . join "\n\t",  map {$entry->get_value($_)} @user_alias_attrs, @group_alias_attrs;
    }

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


sub find_in_ldap($$) {
    my ($l, $rslt) = @_;
    
    # search ldap for the alias.  
    #  It will either be 
    #    - a user, 
    #    - an alias to a user (mailequivalentaddress or mailalternateaddress) or
    #    - a group.
    #
    
    my $local_user = $$l;
    $local_user =~ s/^\s*\\//;

    my $ldap = Net::LDAP->new($ldaphost, port => $ldapport);
    $ldap->bind($binddn, password => $bindpw);

    # determine if the alias already exists in ldap
#     my $filter = "(|(mailalternateaddress=$local_user\@*)".
# 	"(mailequivalentaddress=$local_user\@*)(mail=$local_user\@*)".
# 	"(cn=$local_user))";
    my $filter = "(|" . join ("" , map {"(" . $_ . "=$local_user\@*)"} 
			      @user_alias_attrs) .
			join ("" , map {"(" . $_ . "=$local_user)"} 
			      @group_alias_attrs) . ")";
    $opts->{d} && print "filter: /$filter/\n";
    $$rslt = $ldap->search(
        base => $basedn, 
        filter => $filter,
        attrs  => ["objectclass", "mailalternateaddress", "mailequivalentaddress",
 	          "mail"]);
    $$rslt->code && return "LDAP: ".$rslt->error;

    return 0;
}





