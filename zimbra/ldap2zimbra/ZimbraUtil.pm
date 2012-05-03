package ZimbraUtil;
# Author: Morgan Jones (morgan@morganjones.org)
# Id:     $Id$
#
# TODO: check where variables are initialized and move to new if appropriate.
#       generalize build_zmailhost()
#       unbind ldap explicitely
#

use strict;
use XmlElement;
use XmlDoc;
use Soap;
use Data::Dumper;
use Net::LDAP;

# global variables--modify in ZimbraUtil.cf
our @zimbra_special;
our @local_domains;
our $max_recurse;
our $relative_child_status_path;
our $in_multi_domain_mode;
our $create_archives;
our @z2l_literals;
our %l_params;
our $exclude_group_rdn;
our $z2l;
our %z2l_archive;
our %z_params;
our @global_cals;

my $parent_pid;
my %subset;
my $ldap;
my @exclude_list;
our $archive_name_attr;
my $archive_z2l;
my $zimbra_limit_filter;  # TODO: how is this used?
my $context;

# hash ref to store archive accounts that need to be sync'ed.
my $archive_accts;
# hash ref to store a list of users added/modified to extra users can
# be deleted from zimbra.
my $all_users;

my $ACCTNS = "urn:zimbraAdmin";
my $MAILNS = "urn:zimbraAdmin";
my $SOAP = $Soap::Soap12;
my $url;

my $cf_file = __PACKAGE__ . ".cf";
require $cf_file || die "can't open $cf_file";

my %g_params;




# Top level public functions
#####
sub is_local_domain {
    shift if ((ref $_[0]) eq __PACKAGE__);
    my $lu = shift;

    my $d = (split /@/, $lu)[1];
    
    return 1 unless ($in_multi_domain_mode);

    for (@local_domains) {
        return 1
            if (lc $_ eq lc $d);
    }

    print "\nskipping user in non-local domain: $lu\n";
    return 0;
}


#####
sub return_all_accounts {
    shift if ((ref $_[0]) eq __PACKAGE__);

    return operate_on_user_list(func=>\&ooul_func_return_list, 
                                filter=>"(objectclass=orgzimbraperson)");
}


#####
sub rename_all_archives {
    shift if ((ref $_[0]) eq __PACKAGE__);

    return operate_on_user_list(func=>\&ooul_func_rename_archives, @_);
}


######
# renew global $context--usually in response to a signal from a child
sub renew_context () {
    print "renewing global context in response to signal in proc $$"
	if (exists($g_params{g_debug}));

    $context = get_zimbra_context();
    
    if (!defined $context) {
        die "unable to get a valid context";
    }
}



# Package utility function(s)
#####
sub new {
    my $class;
    my %args;
    ($class, $parent_pid, %args) = @_;

    for my $k (keys %args) {
        if ($k =~ /^z_/) {
            $z_params{$k} = $args{$k}; 
        } elsif ($k =~ /^l_/) {
            $l_params{$k} = $args{$k};
        } elsif ($k =~ /^g_/) {
            if ($k eq "g_printonly") {
                print "-n used, no changes will be made..\n";
            }
            $g_params{$k} = $args{$k};
        } else {
            warn "can't find  matching key for ", __PACKAGE__, " named argument $k.  it will be ignored";
        }
    }
    # url for zimbra store.  It can be any of your stores
    $url = "https://" . $z_params{z_server} . ":7071/service/admin/soap/";

    my $self = {};

    bless($self, $class);

    $SOAP = $Soap::Soap12;

    $context = get_zimbra_context();
    die "unable to get a valid context. This usually means a password problem or\n".
        "Zimbra's LDAP is not running"
            if (!defined $context);

    init_ldap();
    get_exclude_list();
    check_for_global_cals();
    $SIG{HUP} = \&renew_context; # handler to cause context to be reloaded.

    $in_multi_domain_mode = $g_params{multi_domain_mode}
        if (exists $g_params{multi_domain_mode});


    return $self;
}


sub init_ldap {
    return if defined ($ldap);
    
    $ldap = Net::LDAP->new($l_params{l_host});
    my $rslt = $ldap->bind($l_params{l_binddn}, password => $l_params{l_bindpass});
    $rslt->code && die "unable to bind as ", $l_params{binddn}, ": ", $rslt->error;
}



# funcs to pass to operate_on_user_list
#######
sub ooul_func_return_list($) {
    shift if ((ref $_[0]) eq __PACKAGE__);

    my $r = shift;

    my @l;

    for my $child (@{$r->children()}) {
	my ($mail, $z_id);

	for my $attr (@{$child->children}) {
  	    if ((values %{$attr->attrs()})[0] eq "mail") {
  		$mail = $attr->content();
 	    }
  	    if ((values %{$attr->attrs()})[0] eq "zimbraId") {
  		$z_id = $attr->content();
  	    }
 	}
	push @l, $mail;
    }

    return @l
}


#######
sub ooul_func_rename_archives($) {
    shift if ((ref $_[0]) eq __PACKAGE__);
    my ($r, %args) = @_;

    my @l;

    # cycle through the zimbra result object.
    for my $child (@{$r->children()}) {
        my ($mail, $zimbra_id, $archive, $amavis_to, $uid);

        for my $attr (@{$child->children}) {
            $mail = $attr->content()
                if (lc((values %{$attr->attrs()})[0]) eq "mail");
            $zimbra_id = $attr->content()
                if (lc((values %{$attr->attrs()})[0]) eq "zimbraid");
            $archive = $attr->content()
                if (lc((values %{$attr->attrs()})[0]) eq "zimbraarchiveaccount");
            $amavis_to = $attr->content()
                if (lc((values %{$attr->attrs()})[0]) eq "amavisarchivequarantineto");
            $uid = $attr->content()
                if (lc((values %{$attr->attrs()})[0]) eq "uid");
        }

        # skip to next if we're on an archive account
        next unless (defined $mail && $mail !~ /$z_params{z_archive_suffix}$/);

        # find corresponding user in ldap
        my $fil;
        $fil = "(&" . $zimbra_limit_filter
            if (defined $zimbra_limit_filter);

        $fil .= "(uid=$uid)";
        
        $fil .= ")";
        
        my $rslt = $ldap->search(base => $l_params{l_base}, filter => $fil);
        $rslt->code && die "problem with search $fil: ".$rslt->error;  

        my $lusr = ($rslt->entries)[0];

        if (!defined $lusr) {
            print "\n$mail is not in ldap..\n";
            next;
        }
        
        # get internal employee id from ldap
        my $int_empl_id;
        if (exists $args{attr_frm_ldap}) {
#            $int_empl_id = $lusr->get_value($args{attr_frm_ldap});
            $int_empl_id = get_printable_value($lusr, $args{attr_frm_ldap});
        } else {
            die "no attribute received in ooul_func_rename_archives";
        }
        
        if (defined($amavis_to) && defined($archive) && $amavis_to ne $archive) {
            print "\nwarning, amavisarchivequarantineto and zimbraarchiveaccount ".
                "don't match for $uid:\n";
            print $amavis_to . " vs. ". $archive. "\n";
            #TODO: do something?  This is actually okay.. one is the
            #current archive, the other is past and perhaps also
            #current archive(s).
        }
        
        if (!defined $archive) {
            print "no zimbraArchiveAccount for $uid, no action taken.\n";
            return;
        }

        my $archive_usr_part = (split /@/, $archive)[0];
        if (lc $int_empl_id !~ lc $archive_usr_part) {

            print "\n" unless ($amavis_to ne $archive);

            # get zimbra id of existing archive from zimbra
            my $archive_zimbra_id = get_archive_account_id($archive);

            # build the name of the new archive
            my $new_archive = $int_empl_id . "@" . $z_params{z_archive_domain};

            # rename archive account
            if (defined $archive_zimbra_id) {
                print "renaming $archive to $new_archive\n";
                my $d = new XmlDoc();
                $d->start('RenameAccountRequest', $MAILNS);
                $d->add('id', $MAILNS, undef, $archive_zimbra_id);
                $d->add('newName', $MAILNS, undef, $new_archive);
                $d->end();

                unless (exists $g_params{g_printonly}) {
                    my $r = check_context_invoke($d, \$context);
                    if ($r->name eq "Fault") {
                        my $rsn = get_fault_reason($r);
                        
                        print "problem renaming user: $rsn\n";
                        print Dumper($r);
                        multi_proc_exit();
                    }
                }
            } else {
                print "archive $archive does not exist for $mail.  ".
                    "Only attributes will be changed.\n";
            }
            
            # if that was successful or no id was found for the archive
            # account change the attributes in the user account
            
            print "changing attributes in $mail to $new_archive..\n";
            my $d2 = new XmlDoc();
            $d2->start('ModifyAccountRequest', $MAILNS);
            $d2->add('id', $MAILNS, undef, $zimbra_id);
            $d2->add('a', $MAILNS, {"n" => "zimbraarchiveaccount"}, $new_archive);
            $d2->add('a', $MAILNS, {"n" => "amavisarchivequarantineto"}, $new_archive);
            $d2->end();

            unless (exists $g_params{g_printonly}) {
                my $r2 = check_context_invoke($d2, \$context);
                if ($r->name eq "Fault") {
                    my $rsn = get_fault_reason($r2);
                    
                    print "problem setting attributes (zimbraarchiveaccount and ".
                        "amavisarchivequarantineto):\n\t$rsn\n";
                    print Dumper($r2);
                    multi_proc_exit();
                }
            }
        }
    }
}







###################
# General utility functions
#####

sub get_zimbra_usrs_frm_ldap {
    shift if ((ref $_[0]) eq __PACKAGE__);

    my $fil = $l_params{l_filter};

    if (exists $l_params{l_subset}) {
        for my $u (split /\s*,\s*/, $l_params{l_subset}) {
            if (!in_multi_domain_mode()) {
                $u .= "@".get_z_domain()
                    if ($u !~ /\@/);
            }
            $subset{lc $u} = 1;
        }
        print "\nlimiting to subset of users:\n", join (', ', keys %subset), "\n";

        if (in_multi_domain_mode()) {
            $fil = "(&" . $fil . "(|(mail=" . join (')(mail=', keys %subset) . ")))";
        } else {
            #            $fil = "(&" . $fil . "(|(uid=" . join (')(uid=', keys %subset) . ")))";
            my @k = keys %subset;
            for (@k) { s/@.*//; }
            $fil = "(&" . $fil . "(|(uid=" . join (')(uid=', @k) . ")))";
        }
    }

    print "getting user list from ldap: $fil\n";

    my $rslt = $ldap->search(base => $l_params{l_base}, filter => $fil);
    $rslt->code && die "problem with search $fil: ".$rslt->error;

    return $rslt->entries;
}


######
sub get_exclude_list() {
    shift if ((ref $_[0]) eq __PACKAGE__);

    # if $exclude_group_rdn is non-existant or empty there is no exclude list
    return if (!defined $exclude_group_rdn || $exclude_group_rdn =~ /^\s*$/);
    
    my $r = $ldap->search(base => $l_params{l_base} , filter => $exclude_group_rdn);
    $r->code && die "problem retrieving exclude list: " . $r->error;

    my @e = $r->entries;  # do we need to check for multiple entries?

    if ($#e != 0) {
	print "more than one entry found for $exclude_group_rdn:\n";
	for my $lu (@e) {
	    print "dn: ", $lu->dn(), "\n";
	}
	die;
    }

    my $exclude = $e[0];

    @exclude_list = $exclude->get_value("uniquemember");
}


######
# @exclude_list *must* be populated before this is run.
sub in_exclude_list($) {
    shift if ((ref $_[0]) eq __PACKAGE__);
    my $u = shift;

    # if $exclude_group_rdn is non-existant or empty there is no exclude list
    return 0 if (!defined $exclude_group_rdn || $exclude_group_rdn =~ /^\s*$/);
    
    for my $ex (@exclude_list) {
	unless (in_multi_domain_mode()) {
	    $ex = (split(/\@/, $ex))[0];
	    $u  = (split(/\@/, $u))[0];
	}
	
	return 1
	    if (lc($ex) eq lc($u));
    }
    
    return 0;
}


##########
sub in_multi_domain_mode {
    shift if ((ref $_[0]) eq __PACKAGE__);

    return $in_multi_domain_mode;
    # TODO?
    # unless (in_multi_domain_mode()) {
}


#########
sub in_subset {
    shift if ((ref $_[0]) eq __PACKAGE__);
    my @mail = @_;

    return 1 if (!%subset);

    for my $m (@mail) {
        return 1 if (exists $subset{lc $m});
    }

    return 0;
}


######
sub sync_user {
    shift if ((ref $_[0]) eq __PACKAGE__);
    my ($zuser, $lu, $child_wtr_fh) = @_;

    find_and_apply_user_diffs($lu, $zuser);
    
    if ($create_archives) {
        # get the archive account. Returns undef if the archive in
        # the user account doesn't exist.
        my $archive_acct_name = get_archive_account($zuser);
        
        if (!defined ($archive_acct_name)) {
            if (!defined(get_archive_account_id(build_archive_account($lu)))) {
                # the archive account in the user does not exist.
                add_archive_acct($lu, $child_wtr_fh);
            }
            
        } else {
            print "writing existing archive to parent ($$): $archive_acct_name\n"
                if (exists $g_params{g_debug});
            print $child_wtr_fh "$archive_acct_name\n";
            
            # store the archive account name and the ldap user object for
            # later syncing.
            $archive_accts->{$archive_acct_name} = $lu
                if (exists $g_params{g_sync_archives});
        }
    }
    add_global_calendar((@{$zuser->{mail}})[0]);
}

#######
sub get_z_user($) {
    shift if ((ref $_[0]) eq __PACKAGE__);
    my $u = shift;

    my $ret;
    my $d = new XmlDoc;
    $d->start('GetAccountRequest', $MAILNS); 
    $d->add('account', $MAILNS, { "by" => "name" }, $u);
    $d->end();

    my $r = check_context_invoke($d, \$context);

    if ($r->name eq "Fault") {
	my $rsn = get_fault_reason($r);
	if ($rsn ne "account.NO_SUCH_ACCOUNT") {
	    print "problem searching out user:\n";
	    print Dumper($r);
            multi_proc_exit();
	}
    }

    my $middle_child = $r->find_child('account');

    # user entries return a list of XmlElements
    return undef if !defined $middle_child;
    for my $child (@{$middle_child->children()}) {
	# TODO: check for multiple attrs.  The data structure allows
	#     it but I don't think it will ever happen.
	push @{$ret->{lc ((values %{$child->attrs()})[0])}}, $child->content();
     }

    return $ret;
}


sub get_z_domain {
    return $z_params{z_domain};
}



######
sub add_user {
    shift if ((ref $_[0]) eq __PACKAGE__);
    my $lu = shift;
    my $child_wtr_fh = shift;

#    print "\nadding: ", $lu->get_value("uid"), ", ",
#        $lu->get_value("cn"), "\n";

    print "\nadding: ", get_printable_value($lu, "uid"), ", ",
      get_printable_value($lu,"cn"), "\n";

    my $z2l = get_z2l();

    # org hack
    # TODO: define a 'required' attribute in user definable section above.
#    unless (defined build_target_z_value($lu, "orgghrsintemplidno", $z2l)) {
    if ($create_archives) {
#        unless (defined build_target_z_value($lu, $archive_name_attr, $z2l)) {
        unless (defined build_target_z_value($archive_name_attr, $z2l, $lu)) {
            print "\t***no $archive_name_attr ldap attribute.  Archives can't be created.  Not adding.\n";
            return;
        }
    }

    my $d = new XmlDoc;
    $d->start('CreateAccountRequest', $MAILNS);
    my $an;
    if (in_multi_domain_mode()) {
        $an = $lu->get_value("mail");
    } else {
#        $an = $lu->get_value("uid")."@".get_z_domain();
        $an = get_printable_value($lu, "uid")."@".get_z_domain();
    }
    $d->add('name', $MAILNS, undef,$an);

    for my $zattr (sort keys %$z2l) {
#	my $v = build_target_z_value($lu, $zattr, $z2l);
	my $v = build_target_z_value($zattr, $z2l, $lu);

	if (!defined($v)) {
	    print "unable to build value for $zattr, skipping..\n"
	      if (exists $g_params{g_debug});
	    next;
	}

	$d->add('a', $MAILNS, {"n" => $zattr}, $v);
    }
    $d->end();

    my $o;
    if (exists $g_params{g_debug}) {
	print "here's what we're going to change:\n";
	$o = $d->to_string("pretty")."\n";
	$o =~ s/ns0\://g;
	print $o."\n";
    }

    if (!exists $g_params{g_printonly}) {
	my $r = check_context_invoke($d, \$context);

	if ($r->name eq "Fault") {
	    print "problem adding user:\n";
	    print Dumper $r;
            multi_proc_exit();
	}

	my $mail;
	for my $c (@{$r->children()}) {
	    for my $attr (@{$c->children()}) {
		if ((values %{$attr->attrs()})[0] eq "mail") {
		    $mail = $attr->content();
		}
	    }
	}
	if (exists $g_params{g_debug} && !exists $g_params{g_printonly}) {
	    $o = $r->to_string("pretty");
	    $o =~ s/ns0\://g;
	    print $o."\n";
	}

	add_global_calendar($mail, $parent_pid);
    }



    if ($create_archives) {
        # The user is newly created so does not have a legacy archive account..
        # get the archive name
        my $archive_acct_name = build_archive_account($lu);

        if (!defined(get_archive_account_id($archive_acct_name))) {
            # if the archive doesn't exist add it.
            add_archive_acct($lu, $child_wtr_fh);
        } else {
            # if the archive exists do nothing.
            print "found existing archive account: ",$archive_acct_name,"\n";
        }
    }
}


{
    my $archive_cache;  # local to sub get_archive_account()
    
    # get an active archive account from a user account
    sub get_archive_account {
        shift if ((ref $_[0]) eq __PACKAGE__);
	my ($zuser) = @_;

        return undef if (!defined $zuser);

	if (exists $zuser->{mail}) {
            return $archive_cache->{(@{$zuser->{mail}})[0]}
                if (exists $archive_cache->{(@{$zuser->{mail}})[0]});
	}

	if (exists $zuser->{zimbraarchiveaccount}) {
	    my $acct_name;

	    for $acct_name (@{$zuser->{zimbraarchiveaccount}}) {
		# check for archive account
		my $d2 = new XmlDoc;
		$d2->start('GetAccountRequest', $MAILNS); 
		$d2->add('account', $MAILNS, { "by" => "name" }, 
			 #build_archive_account($lu));
			 $acct_name);
		$d2->end();
		
		my $r2 = check_context_invoke($d2, \$context);

		if ($r2->name eq "Fault") {
		    my $rsn = get_fault_reason($r2);
		    if ($rsn ne "account.NO_SUCH_ACCOUNT") {
			print "problem searching out archive $acct_name\n";
			print Dumper($r2);
                        multi_proc_exit();
		    }
		}

		my $mc = $r2->find_child('account');

		if (defined $mc) {
		    $archive_cache->{(@{$zuser->{mail}})[0]} = 
			$mc->attrs->{name};
		    return ($mc->attrs->{name});
		}
	    }
	}
	return undef;
    }
}


######
sub add_archive_acct {
    shift if ((ref $_[0]) eq __PACKAGE__);
    my $lu = shift;
    my $child_wtr_fh = shift;

    my $z2l = get_z2l("archive");

    my $archive_account = build_archive_account($lu);

    print "adding archive: ", $archive_account,
#        " for ", $lu->get_value("uid"), "\n";
        " for ", get_printable_value($lu,"uid"), "\n";
    print "writing newly created archive to parent ($$): $archive_account\n"
	if (exists $g_params{g_debug});
    print $child_wtr_fh "$archive_account\n";

    my $d3 = new XmlDoc;
    $d3->start('CreateAccountRequest', $MAILNS);
    $d3->add('name', $MAILNS, undef, $archive_account);


    for my $zattr (sort keys %$z2l) {
	my $v;

#	$v = build_target_z_value($lu, $zattr, $z2l);
	$v = build_target_z_value($zattr, $z2l, $lu);

	if (!defined($v)) {
	    print "ERROR: unable to build value for $zattr, skipping..\n";
	    next;
	}
	
	$d3->add('a', $MAILNS, {"n" => $zattr}, $v);
    }
    $d3->end();

    my $o;
    if (exists $g_params{g_debug}) {
	print "here's what we're going to change:\n";
	$o = $d3->to_string("pretty")."\n";
	$o =~ s/ns0\://g;
	print $o."\n";
    }

    if (!exists $g_params{g_printonly}) {
	my $r3 = check_context_invoke($d3, \$context);

	if ($r3->name eq "Fault") {
	    print "problem adding user:\n";
	    print Dumper $r3;
            multi_proc_exit();
	}

	if (exists $g_params{g_debug} && !exists $g_params{g_printonly}) {
	    $o = $r3->to_string("pretty");
	    $o =~ s/ns0\://g;
	    print $o."\n";
	}
    }

}


######
#sub build_target_z_value($$$) {
sub build_target_z_value {
    shift if ((ref $_[0]) eq __PACKAGE__);
#    my ($lu, $zattr, $z2l) = @_;
    my ($zattr, $z2l, $lu, $zu) = @_;

    # $zu is only defined if called from a modify (vs an add).  The rest need to be defined.
    return undef unless (defined $lu && defined $zattr && defined $z2l);
    
    my $t = ref($z2l->{$zattr});
    if ($t eq "CODE") {
        if (defined $zu) {
            return &{$z2l->{$zattr}}($lu, $zu);
        } else {
            return &{$z2l->{$zattr}}($lu);
        }
    }

    my $ret = join ' ', (
	map {
    	    my @ldap_v;
	    my $v = $_;

	    map {
		if ($v eq $_) {
		    $ldap_v[0] = $v;
		}
	    } @z2l_literals;

	    if ($#ldap_v < 0) {
#		@ldap_v = $lu->get_value($v);
		@ldap_v = get_printable_value($lu, $v);
		
		map { fix_case ($_) } @ldap_v;
	    } else {
		@ldap_v;
	    }

	} @{$z2l->{$zattr}}   # get the ldap side of z2l hash
    );

    # special case rule to remove space before and after open parentheses
    # and after close parentheses.  I don't think there's a better
    # way/place to do this.
    $ret =~ s/\(\s+/\(/;
    $ret =~ s/\s+\)/\)/;
    # if just () remove.. another hack for now.
    $ret =~ s/\s*\(\)\s*//g;

    return $ret;
}

######
sub operate_on_user_list {
    shift if ((ref $_[0]) eq __PACKAGE__);
    my %args = @_;

    exists $args{func} || return undef;
    
    my $func = $args{func};
    my $search_fil = undef;

    my $d = new XmlDoc;
    $d->start('SearchDirectoryRequest', $MAILNS, {'types'  => "accounts"}); 

    if (exists $args{filter}) {
        print "searching with fil $args{filter}\n" if exists $g_params{g_debug};
        $d->add('query', $MAILNS, { "types" => "accounts" }, $args{filter});
    } else {
        $d->add('query', $MAILNS, { "types" => "accounts" });
    }

    my $r = check_context_invoke($d, \$context);

    my @l;
    if ($r->name eq "Fault") {
        my $rsn = get_fault_reason($r);
        
        # break down the search by alpha/numeric if reason is 
        #    account.TOO_MANY_SEARCH_RESULTS
        if (defined $rsn && $rsn eq "account.TOO_MANY_SEARCH_RESULTS") {
	    print "\tfault due to $rsn\n".
                "\trecursing deeper to return fewer results.\n"
                if exists $g_params{g_debug};

            @l = operate_on_range(undef, "a", "z", $func, %args);
        } else {
            print "unhandled reason: $rsn, exiting.\n";
            print Dumper($r);
            multi_proc_exit();
        }
    } else {
        print "returned ", $r->num_children, " children\n";
        @l = $func->($r, %args);
    }

    return @l;
}




#######
# called from within operate_on_user_list if an account.TOO_MANY_SEARCH_RESULTS Fault is thrown
# a, b, c, d, .. z
# a, aa, ab, ac .. az, ba, bb .. zz
# a, aa, aaa, aab, aac ... zzz
#sub get_list_in_range($$$) {
sub operate_on_range {
    shift if ((ref $_[0]) eq __PACKAGE__);

    my ($prfx, $beg, $end, $func, %args) = @_;

# TODO: if debug:
#     print "deleting ";
#     print "${beg}..${end} ";
#     print "w/ prfx $prfx " if (defined $prfx);
#     print "\n";
    
    my $search_fil;
    
    $search_fil = $args{filter}
        if (exists $args{filter});

    my @l;

    for my $l (${beg}..${end}) {
	my $fil = '(uid=';
	$fil .= $prfx if (defined $prfx);
	$fil .= "${l}\*)";

	$fil = "(&(" . $fil . $search_fil . "))"
	    if (defined ($search_fil));

 	print "searching $fil\n"
 	    if exists $g_params{g_debug};

	my $d = new XmlDoc;
	$d->start('SearchDirectoryRequest', $MAILNS);
	$d->add('query', $MAILNS, { "types" => "accounts" }, $fil);
	$d->end;
	
        my $r = check_context_invoke($d, \$context);

 	if ($r->name eq "Fault") {
	    my $rsn = get_fault_reason ($r);

	    # break down the search by alpha/numeric if reason is 
	    #    account.TOO_MANY_SEARCH_RESULTS
	    if (defined $rsn && $rsn eq "account.TOO_MANY_SEARCH_RESULTS") {
		if (exists $g_params{g_debug}) {
		    print "\tfault due to $rsn\n";
		    print "\trecursing deeper to return fewer results.\n";
		}
		
		my $prfx2pass = $l;
		$prfx2pass = $prfx . $prfx2pass if defined $prfx;
		
		increment_del_recurse();
		if (get_del_recurse() > $max_recurse) {
		    print "\tmax recursion ($max_recurse) hit, backing off.. \n";
		    print "\tThis may mean a truncated user list.\n";
		    decrement_del_recurse();
		    return 1; # return failure so caller knows to return
		              # and not keep trying to recurse to this
		              # level

		}

                push @l, operate_on_range ($prfx2pass, $beg, $end, $func, %args);
		decrement_del_recurse();
	    } else {
		print "unhandled reason: $rsn, exiting.\n";
                print Dumper($r);
                multi_proc_exit();
	    }

 	} else {
	    push @l, $func->($r, %args);
        }
    }

    return @l;
}



# static variable to limit recursion depth
BEGIN {
    my $del_recurse_counter = 0;

    sub increment_del_recurse() {
	$del_recurse_counter++;
    }

    sub decrement_del_recurse() {
	$del_recurse_counter--;
    }
    
    sub get_del_recurse() {
	return $del_recurse_counter;
    }
}


######
sub get_zimbra_context {
    shift if ((ref $_[0]) eq __PACKAGE__);

    my $delegate_to=shift;

    # authenticate to Zimbra admin url
    my $d = new XmlDoc;
    $d->start('AuthRequest', $ACCTNS);
    $d->add('SessionId', undef, undef, undef);
    $d->add('name', undef, undef, "admin");
    $d->add('password', undef, undef, $z_params{z_pass});
    $d->end();

    # get back an authResponse, authToken, sessionId & context.
    my $r = $SOAP->invoke($z_params{z_url}, $d->root());

    # if we get a fault here there is not much that can be done.
    return undef
        if ($r->name eq "Fault");


    my $authToken = $r->find_child('authToken')->content;

#    $sessionId = $r->find_child('sessionId')->content;

#    my $cntxt = $SOAP->zimbraContext($authToken, $sessionId);
    my $cntxt = $SOAP->zimbraContext($authToken, undef);

    if (defined($delegate_to)) {
        $d = new XmlDoc;

        $d->start('DelegateAuthRequest', $MAILNS);
        $d->add('account', $MAILNS, { by => "name" }, 
              $delegate_to);
        $d->end();

        $r = $SOAP->invoke($z_params{z_url}, $d->root());


        # if we get a fault here there is not much that can be done.
        return undef
            if ($r->name eq "Fault");

        $authToken = $r->find_child('authToken')->content;
#        $sessionId = $r->find_child('sessionId')->content;
        
#        my $new_cntxt = $SOAP->zimbraContext($authToken, $sessionId);
        my $new_cntxt = $SOAP->zimbraContext($authToken, undef);

        #TODO:  only print if debug?
        #print "returning new_cntxt because delegate_to is $delegate_to\n";

        return $new_cntxt;
    }

    return $cntxt;
}




######
# for compatibility
sub get_archive_account_id($) {
    shift if ((ref $_[0]) eq __PACKAGE__);

    return get_account_id(@_);
}


######
sub get_account_id($) {
    shift if ((ref $_[0]) eq __PACKAGE__);
    my $a = shift;

    my $d2 = new XmlDoc;
    $d2->start('GetAccountRequest', $MAILNS); 
    $d2->add('account', $MAILNS, { "by" => "name" }, $a);
    $d2->end();
    
    my $r2 = check_context_invoke($d2, \$context);

    if ($r2->name eq "Fault") {
	my $rsn = get_fault_reason($r2);
	if ($rsn ne "account.NO_SUCH_ACCOUNT") {
	    print "problem searching out account $a\n";
	    print Dumper($r2);
	    return;
	}
    }

    my $mc = $r2->find_child('account');

    return $mc->attrs->{id}
        if (defined $mc);
	
    return undef;
}


######
# check for and correct expired authentication during invoke.
#  The idea is to catch an expired auth token on the fly so as to not 
#  interrupt the running script.
sub check_context_invoke {
    shift if ((ref $_[0]) eq __PACKAGE__);
    my ($d, $context_ref, $delegate_to) = @_;
    
    if ((ref $d) ne "XmlDoc") {
        shift; 
        ($d, $context_ref) = @_;
    }

    my $r = $SOAP->invoke($z_params{z_url}, $d->root(), $$context_ref);

    if ($r->name eq "Fault") {
	my $rsn = get_fault_reason($r);
	if (defined $rsn && $rsn =~ /AUTH_EXPIRED/) {
	    # authentication timed out, re-authenticate and re-try the invoke
	    print "\tfault due to $rsn at ", `date`;
	    print "\tre-authenticating..\n";
	    $$context_ref = get_zimbra_context($delegate_to);

            if (!defined $$context_ref) {
                # if we can't get a valid context but are delegating it is likely 
                #   just a problem with that user, ie maintenance mode..  Return undef 
                #   and let the caller figure out what to do.

                return undef
                    if (defined $delegate_to);
                die "unable to get a valid context";
            }

	    $r = $SOAP->invoke($z_params{z_url}, $d->root(), $$context_ref);

            if (defined ($parent_pid)) {
                print "killing $parent_pid to cause global ".
                    "\$context to be reloaded..\n"
                        if (exists $g_params{g_debug});
                kill('HUP', $parent_pid);
            }
	    if ($r->name eq "Fault") {
		$rsn = get_fault_reason($r);

                print "got a second fault in check_context_invoke.\n";
		if (defined $rsn) {
                    print "\treason: $rsn.\n";
                }
                print "exiting..";
                print Dumper($r);
                exit;
	    }
	}
    }
    return $r;
}



######
# find_and_apply_user_diffs knows it's been passed an archive
# account when it gets a zimbra_id as its last argument.
sub find_and_apply_user_diffs {
    shift if ((ref $_[0]) eq __PACKAGE__);
    my ($lu, $zuser, $syncing_archive_acct) = @_;

    my $z2l;

    if (defined $syncing_archive_acct && $syncing_archive_acct == 1) {
	$z2l = get_z2l("archive");
    } else {
	$z2l = get_z2l();
	$syncing_archive_acct = 0;
    }

    my $zimbra_id = (@{$zuser->{zimbraid}})[0];

    my $d = new XmlDoc();
    $d->start('ModifyAccountRequest', $MAILNS);
    $d->add('id', $MAILNS, undef, $zimbra_id);

    my $diff_found=0;

    for my $zattr (sort keys %$z2l) {
	my $l_val_str = "";
	my $z_val_str = "";

	if (!exists $zuser->{$zattr}) {
	    $z_val_str = "";
	} else {
	    $z_val_str = join (' ', sort @{$zuser->{$zattr}});
	}

	if ($syncing_archive_acct && $zattr eq "zimbramailhost") {
	    $l_val_str = $z_params{z_archive_mailhost};
	} else {
	    # build the values from ldap using zimbra capitalization
#	    $l_val_str = build_target_z_value($lu, $zattr, $z2l);
	    $l_val_str = build_target_z_value($zattr, $z2l, $lu, $zuser);

	    if (!defined($l_val_str)) {
		print "unable to build value for $zattr, skipping..\n"
                    if (exists $g_params{g_debug});
		next;
	    }
	}

 	if (($zattr =~ /amavisarchivequarantineto/i ||
 	    $zattr =~ /zimbraarchiveaccount/i) && 
	    !$syncing_archive_acct) {

 	    # set the archive acct attrs if the archive account exists
 	    # and is tied to the user.
 	    # if we don't set it here it will be set by
 	    # build_target_z_value above
 	    my $acct = get_archive_account($zuser);
 	    if (defined $acct) {
 		$l_val_str = $acct;
 	    }
	}

	if ($l_val_str ne $z_val_str) {
	    
	    if ($diff_found == 0) {
		print "\n" if (!exists $g_params{g_debug});
		print "syncing ", (@{$zuser->{mail}})[0], "\n";
	    }
	    
	    if (exists $g_params{g_debug}) {
		print "different values for $zattr:\n".
		    "\tldap:   $l_val_str\n".
		    "\tzimbra: $z_val_str\n";
	    } else {
		print "was: $zattr: $z_val_str\n";
	    }
	    
	    # zimbraMailHost 
	    if ($zattr =~ /^\s*zimbramailhost\s*$/) {
# 		print "zimbraMailHost diff found for ";
# 		print "", (@{$zuser->{mail}})[0];
# 		print " Skipping.\n";
# 		print "\tldap:   $l_val_str\n".
# 		    "\tzimbra: $z_val_str\n";

                
                print "", (@{$zuser->{mail}})[0], " should be on $l_val_str\n";
		next;
	    }

	    # if the values differ push the ldap version into Zimbra
	    $d->add('a', $MAILNS, {"n" => $zattr}, $l_val_str);
	    $diff_found++;
	}
    }

    $d->end();

    if ($diff_found) {
	my $o;
	$o = $d->to_string("pretty");
	$o =~ s/ns0\://g;
	print $o;

	if (!exists $g_params{g_printonly}) {
	    my $r = check_context_invoke($d, \$context);

            # TODO: check result of invoke?

	    if (exists $g_params{g_debug}) {
		print "response:\n";
		$o = $r->to_string("pretty");
		$o =~ s/ns0\://g;
		print $o."\n";
	    }
	}
    }

}



######
sub sync_archive_accts {
    return unless ($create_archives);

    if (!exists $g_params{g_sync_archives}) {
        print "\nnot syncing archives (enable with -a)\n";
        return;
    }

    # sync archive accounts.  We do this last as it more than doubles the
    # run time of the script and it's not critical.
    # TODO: parallelize this?
    print "\nsyncing archives, ", `date`;
    for my $acct_name (keys %$archive_accts) {

	print "\nworking on archive $acct_name ", " ", `date`
	    if (exists $g_params{g_debug});

 	find_and_apply_user_diffs($archive_accts->{$acct_name}, 
				  get_z_user($acct_name), 1);
    }
}


#######
# a, b, c, d, .. z
# a, aa, ab, ac .. az, ba, bb .. zz
# a, aa, aaa, aab, aac ... zzz
#sub delete_in_range($$$) {
sub delete_in_range {
    shift if ((ref $_[0]) eq __PACKAGE__);
    my ($prfx, $beg, $end) = @_;

    my $i=1;
    do {

        for my $l (${beg}..${end}, "_", "-") {
            my $fil = 'uid=';
            $fil .= $prfx if (defined $prfx);
            $fil .= "${l}\*";

            print "searching $fil\n";
            my $d = new XmlDoc;
            $d->start('SearchDirectoryRequest', $MAILNS);
            $d->add('query', $MAILNS, undef, $fil);
            $d->end;

	    my $r = check_context_invoke($d, \$context);

            if ($r->name eq "Fault") {
                # TODO: limit recursion depth
                print "\tFault! ..recursing deeper to return fewer results.\n";
                my $prfx2pass = $l;
                $prfx2pass = $prfx . $prfx2pass if defined $prfx;

                increment_del_recurse();
                if (get_del_recurse() > $max_recurse) {
                    print "\tmax recursion ($max_recurse) hit, backing off..\n";
                    decrement_del_recurse();
                    return undef; #return failure so caller knows to return
                    #and not keep trying to recurse to this
                    #level
                }
                my $rc = delete_in_range ($prfx2pass, $beg, $end);
                decrement_del_recurse();
                return if ($rc); # should cause us to drop back one level
                # in recursion
            } else {
                parse_and_del($r);
            }
        }

        if ($beg =~ /[a-zA-Z]+/i && $end =~ /[0-9]+/) {
            $beg = 0;
        } elsif ($end =~ /[a-zA-Z]+/i && $beg =~ /[0-9]+/) {
            $beg = "a";
            lc $end;
        } elsif ($i > 0) {
            $i--;
        }

    } while ($i--);

}


sub is_zimbra_special {
    shift if ((ref $_[0]) eq __PACKAGE__);
    my @mail = @_;

    for my $zs (@zimbra_special) {
        for my $m (@mail) {
            $m = (split /\@/, $m)[0]
                if ($m =~ /\@/);
            return 1 if $m =~ /^$zs$/;
        }
    }

    return 0;
}

#######
sub in_all_users(@) {
    shift if ((ref $_[0]) eq __PACKAGE__);
    my @mail = @_;

    for my $m (@mail) {
        return 1 if exists $all_users->{$m};
    }
    
    return 0;
}


#######
sub is_archive_acct(@) {
    shift if ((ref $_[0]) eq __PACKAGE__);
    my @mail = @_;

    for my $m (@mail) {
        return 1 if ($m =~ /archive\s*$/i);
    }
    
    return 0;
}


#######
sub parse_and_del($) {
    shift if ((ref $_[0]) eq __PACKAGE__);
    my $r = shift;

    for my $child (@{$r->children()}) {
	my ($uid, $z_id);
        my @mail;

	for my $attr (@{$child->children}) {
	    $uid = $attr->content()
		if ((values %{$attr->attrs()})[0] eq "uid");

            # multiple mail aliases
            push @mail, $attr->content()
                if ((values %{$attr->attrs()})[0] eq "mail");

	    $z_id = $attr->content()
		if ((values %{$attr->attrs()})[0] eq "zimbraId");
 	}

	# skip special users
        # TODO: what about multidomain mode?
        if (in_exclude_list($uid)) {
	    print "\tskipping special user $uid\n"
		if (exists $g_params{g_debug});
	    next;
	}

        next if in_all_users(@mail);
        
        if (exists $g_params{g_dont_delete_archives} && is_archive_acct(@mail)) {
            print "\tnot deleting archive: $uid, ", join ' ', @mail, "\n";
            next;
        }

        next if (is_zimbra_special(@mail));
    
        next unless in_subset(@mail);

        print "\ndeleting $uid, ", join ' ', @mail, "\n";

        my $d = new XmlDoc;
        $d->start('DeleteAccountRequest', $MAILNS);
        $d->add('id', $MAILNS, undef, $z_id);
        $d->end();

        if (!exists $g_params{g_printonly}) {
            my $r = check_context_invoke($d, \$context);

            if (exists $g_params{g_debug}) {
                my $o = $r->to_string("pretty");
                $o =~ s/ns0\://g;
                print $o."\n";
            }
        }
    }
}


sub get_default_domain {
    return $z_params{z_domain};
}

#####
# takes an argument because all subs called out of get_z2l have to.
# It ignores the argument.
sub get_archive_cos_id($) {
    return $z_params{z_archive_cos_id};
}


######
sub add_to_all_users {
    shift if ((ref $_[0]) eq __PACKAGE__);
    my $usr = shift;

    $all_users->{$usr} = 1;
}


######
# ignore argument
sub get_z_archive_mailhost($) {

    return $z_params{z_archive_mailhost};
}

#######
sub return_string($) {
    return shift;
}

#######
sub get_z2l($) {
    shift if ((ref $_[0]) eq __PACKAGE__);

    my $type = shift;
    # left  (lhs): zimbra ldap attribute
    # right (rhs): corresponding enterprise ldap attribute.
    # 
    # It's safe to duplicate attributes on rhs.
    #
    # These need to be all be lower case
    #
    # You can use literals (like '(' or ')') but you need to identify
    # them in @z2l_literals at the top of the script.
    #
    # If the attribute requires processing specify a subroutine on the
    # rhs and built_target_zimbra_value will run that sub instead of
    # mapping to ldap attributes.


    # SDP mapping:
    # zimbra       ULC/AMS         Example       LDAP
    # -----------------------------------------------
    # street       ULC-SUPPLY-ST-ADD ULC-SUP-NAME-2  
    #                              4th Floor - Suite 404 440 N. Broad Street
    #                                            orgWorkStreetShort
    # st           ULC-STATE-CODE  PA            orgWorkState
    # l            ULC-CITY        Philadelphia  orgWorkCity
    # postalCode   ULC-SUPPLY-ZIP  19130         orgWorkZip
    # displayname  ? ?             Levov, Sylvia sn, givenname
    # zimbrapreffromdisplay
    #              ? ?
    #                              Levov, Sylvia sn, givenname
    # company      ORG-LONG-DD     Technology Services
    #                                            orgHomeOrg
    # co           ULC-AREA-CD ULC-PHONE-NUM ULC-FAX-AREA-CD ULC-FAX-NUM
    #                              Phone: 215.400.1234 Fax: 215.400.3456
    #                                            orgWorkTelephone orgWorkFax
    # zimbramailhost
    # zimbracosid

    if (defined $type && $type eq "archive") {
        return $archive_z2l;
    } elsif (defined $type) {
	die "unknown type $type received in get_z2l.. ";
    } else {
        return $z2l;
    }

#    return $z2l;
}

#####
sub build_last_first($) {
    shift if ((ref $_[0]) eq __PACKAGE__);
    my $lu = shift;

    my $r = undef;

#    if (defined (my $l = $lu->get_value("sn"))) {
    if (defined (my $l = get_printable_value($lu, "sn"))) {
	$r .= $l;
    }

#    if (defined (my $f = $lu->get_value("givenname"))) {
    if (defined (my $f = get_printable_value($lu, "givenname"))) {
	$r .= ", " if (defined $r);
	$r .= $f;
    }

    return fix_case($r);
}





######
sub build_phone_fax($) {
    shift if ((ref $_[0]) eq __PACKAGE__);
    my $lu = shift;

    my $r = undef;

    my $phone_separator = '-';

#    if (defined (my $p = $lu->get_value("orgworktelephone"))) {
    if (defined (my $p = get_printable_value($lu, "orgworktelephone"))) {
	$p =~ s/(\d{3})(\d{3})(\d{4})/$1$phone_separator$2$phone_separator$3/;
	$r .= "Phone: " . $p; 
    }

#    if (defined (my $f = $lu->get_value("orgworkfax"))) {
    if (defined (my $f = get_printable_value($lu, "orgworkfax"))) {
        # only add "<br>" if there's a telephone
	$r .= "<BR>" if (defined $r);
	$f =~ s/(\d{3})(\d{3})(\d{4})/$1$phone_separator$2$phone_separator$3/;
	$r .= "Fax: " . $f;
    }

    return $r;
}

######
sub build_phone($) {
    shift if ((ref $_[0]) eq __PACKAGE__);
    my $lu = shift;

    my $phone_separator = '-';

    if (defined (my $p = get_printable_value($lu, "orgworktelephone"))) {
	$p =~ s/(\d{3})(\d{3})(\d{4})/$1$phone_separator$2$phone_separator$3/;
	return $p;
    }
    return undef;
}

sub build_fax($) {
    shift if ((ref $_[0]) eq __PACKAGE__);
    my $lu = shift;

    my $phone_separator = '-';

    if (defined (my $p = get_printable_value($lu, "orgworkfax"))) {
	$p =~ s/(\d{3})(\d{3})(\d{4})/$1$phone_separator$2$phone_separator$3/;
	return $p;
    }
    return undef;
}



######
sub build_address($) {
    shift if ((ref $_[0]) eq __PACKAGE__);
    my $lu = shift;

    return fix_case($lu->get_value("orgworkstreetshort"));
}

######
# build a new archive account from $lu
sub build_archive_account($) {
    shift if ((ref $_[0]) eq __PACKAGE__);
    my $lu = shift;

#    return $lu->get_value("orgghrsintemplidno")."\@".get_z_domain().".".$z_params{z_archive_suffix};
    return get_printable_value($lu, "orgghrsintemplidno")."\@".get_z_domain().".".$z_params{z_archive_suffix};
}



sub build_split_domain_zmailtransport {
    shift if ((ref $_[0]) eq __PACKAGE__);
    my ($lu, $zu) = @_;

    return "smtp:smtp.domain.org:25"
        if (!exists ($zu->{zimbramailtransport}));

    return (@{$zu->{zimbramailtransport}})[0];
}


######
sub build_org_zmailhost($) {
    shift if ((ref $_[0]) eq __PACKAGE__);
    my $lu = shift;

#    my $org_id = $lu->get_value("orgghrsintemplidno");
    my $org_id = get_printable_value($lu, "orgghrsintemplidno");


    if (!defined $org_id) {
	print "WARNING! undefined SDP id, zimbraMailHost will be undefined\n";
	return undef;
    }

    my @i = split //, $org_id;
    my $n = pop @i;

    # TODO: revisit!  Add provisions for dmail02 and unknown domain
    if (get_z_domain() eq "domain.org") {
	if ($n =~ /^[01]{1}\s*$/) {
	    return "mail01.domain.org";
	} elsif ($n =~ /^[23]{1}\s*$/) {
	    return "mail02.domain.org";
	} elsif ($n =~ /^[45]{1}\s*$/) {
	    return "mail03.domain.org";
	} elsif ($n =~ /^[67]{1}\s*$/) {
	    return "mail04.domain.org";
	} elsif ($n =~ /^[89]{1}\s*$/) {
	    return "mail05.domain.org";
	} else {
	    print "WARNING! SDP id /$org_id/ did not resolve to a valid ".
		"zimbraMailHost.\n  This shouldn't be possible..\n";
	    return undef;
	}
    } elsif (get_z_domain() eq "dev.domain.org") {
	if ($n =~ /^[0123456789]{1}$/) {
	    return "dmail01.domain.org";
	} else {
	    print "WARNING! SDP id $org_id did not resolve to a valid ".
		"zimbraMailHost.\n  This shouldn't be possible.. ".
		"returning undef.";
	    return undef;
	}
    } elsif (get_z_domain() eq "dmail02.domain.org") {
        return "dmail02.domain.org";
    } else {
	print "WARNING! zimbraMailHost will be undefined because domain ",
            get_z_domain(), " is not recognized.\n";
	return undef;
    }
}






######
sub fix_case($) {
    shift if ((ref $_[0]) eq __PACKAGE__);
    my $s = shift;

    # upcase the first character after each
    my $uc_after_exp = '\s\-\/\.&\'\(\)'; # exactly as you want it in [] 
                                          #   (char class) in regex
    # upcase these when they're standing alone
    my @uc_clusters = qw/hs hr ms es avts pd/;

    # state abbreviations
    # http://www.usps.com/ncsc/lookups/usps_abbreviations.html#states
    push @uc_clusters, qw/AL AK AS  AZ AR CA CO CT DE DC FM FL GA GU HI ID IL IN IA KS KY LA ME MH MD MA MI MN MS MO MT NE NV NH NJ NM NY NC ND MP OH OK OR PW PA PR RI SC SD TN TX UT VT VI VA WA WV WI WY AE AA AE AE AE AP/;


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
sub delete_not_in_ldap() {
    if (!exists $g_params{g_extensive}) {
        print "\nnot deleting accounts (enable with -e)\n";
        return;
    }

    print "\ndelete phase..", `date`;

    my $r;
    my $d = new XmlDoc;
    
    $d->start('SearchDirectoryRequest', $MAILNS,
          {'types'  => "accounts"});
    if (exists $l_params{l_subset}) {
        my $fil;
        if (in_multi_domain_mode()) {
            $fil = "(|(mail=" . join (')(mail=', keys %subset) . "))";
        } else {
            $fil = "(|(uid=" . join (')(uid=', keys %subset) . "))";
        }
        # commented 110412, I'm pretty sure it was a mistake.
#        my $fil = "(|(uid=m*)(uid=" . join (')(uid=', keys %subset) . "))";
        print "using subset filter: $fil\n";

        $d->add('query', $MAILNS, { "types" => "accounts" }, $fil);
    } else {
        $d->add('query', $MAILNS, { "types" => "accounts" });
    }
    $d->end();

    $r = check_context_invoke($d, \$context);

    if ($r->name eq "Fault") {
	my $rsn = get_fault_reason($r);

	# break down the search by alpha/numeric if reason is 
	#    account.TOO_MANY_SEARCH_RESULTS
	if (defined $rsn && $rsn eq "account.TOO_MANY_SEARCH_RESULTS") {
	    print "\tfault due to $rsn\n".
	      "\trecursing deeper to return fewer results.\n"
		if (exists $g_params{g_debug});
	    
	    delete_in_range(undef, "a", "9");
	    return;
	}

	if ($r->name ne "account") {
	    print "skipping delete, unknown record type returned: ", 
	    $r->name, "\n";
	}

        print "problem during delete: \n";
        print Dumper($r);
        return;
    }

    parse_and_del($r);
}



#####
sub get_printable_value ($$) {
    shift if ((ref $_[0]) eq __PACKAGE__);
    my ($ldap_user, $value) = @_;

    if (wantarray()) {
	my @v = $ldap_user->get_value($value);
	for (@v) {
	    s/[^[:print:]\?]/ /g;
	}
	return (@v);
    } else {
	my $v = $ldap_user->get_value($value);
	if (defined $v) {
	    $v =~ s/[^[:print:]]/ /g
	}
	return $v;
    }
}





######
sub get_fault_reason {
    shift if ((ref $_[0]) eq __PACKAGE__);
    my $r = shift;

    # get the reason for the fault
    for my $v (@{$r->children()}) {
        if ($v->name eq "Detail") {
	    for my $v2 (@{@{$v->children()}[0]->children()}) {
		if ($v2->name eq "Code") {
		    return $v2->content;
		}
	    }
	}
    }

    return "<no reason found..>";
}











############ Calendar subroutines

{ my $no_such_folder_notified = 0;  # remember if we've notified about
				    # a mail.NO_SUCH_FOLDER error so
				    # we don't notify over and over.
  sub add_global_calendar($) {
      shift if ((ref $_[0]) eq __PACKAGE__);
      my $mail = shift;

      return unless (@global_cals);

      my @work_gcs;

      for my $gc (@global_cals) {
          push @work_gcs, $gc
              if ($gc->{exists});
      }

      my $d = new XmlDoc;
      $d->start('DelegateAuthRequest', $MAILNS);
      $d->add('account', $MAILNS, { by => "name" }, 
              $mail);
      $d->end();

      my $r = check_context_invoke($d, \$context);

      if ($r->name eq "Fault") {
          print "fault while delegating auth to $mail:\n";
          print Dumper($r);
          print "global calendars will not be added.\n";
          return;
      }
      
      my $new_auth_token = $r->find_child('authToken')->content;
      my $new_context = $SOAP->zimbraContext($new_auth_token, undef);

      # Compare user calendars with defined calendars
      for my $gc (@work_gcs) {
          # if the cal is already shared to $mail do nothing.
          clear_stale_cal_share($mail, $gc->{name}, $gc->{owner});
          next if cal_exists($mail, $gc->{name}, $gc->{owner});

          print "adding calendar ",$gc->{name}," to $mail\n";

          $d = new XmlDoc;
          $d->start('CreateMountpointRequest', "urn:zimbraMail");
          $d->add('link', "urn:zimbraMail", 
                  {"owner" => $gc->{owner},
                  "l" => "1",
                  "path" => $gc->{path},
                  "name" => $gc->{name}});
          $d->end();

      if (!exists $g_params{g_printonly}) {
	  $r = check_context_invoke($d, \$new_context, $mail);

              # check_context_invoke returns undef if there's a problem getting 
              #   a context while delegating to a user.  This means there's a 
              #   problem with that user account but not with the system in 
              #   general so we just skip that user and move on.
              if (!defined $r) {
                  print "problem delegating auth to $mail: ".
                      "user in maint mode?\n";
                  return;
              }

              if ($r->name eq "Fault") {
                  my $rsn = get_fault_reason($r);
	      
                  if ($rsn eq "mail.NO_SUCH_FOLDER") { 
                      unless ($no_such_folder_notified) {
                          print "\n*** ERROR: There is no calendar named ".
                              $gc->{name}, " under".
                              "\n*** user ", $gc->{owner}, ".  No calendar will be ".
                              "shared.".
                              "\n*** This error will re-occur for every ".
                              "user but".
                              "\n*** this notification ".
                              "will only repeat periodically.\n";
                          $no_such_folder_notified = 1;
                      }
                  } else {
                      print "\tFault during calendar $gc->{name} create mount: $rsn\n";
                  }
              }
          }
      }
  }
}



{ my %cached_cals;

# cal_exists() checks:
# if just $acct and $cal check for a calendar named $cal
# if $acct, $cal and $owner 
#      check in $owner for a cal with an id that matches an rid in $acct.
# if $acct and $id it checks for a calendar with $id in $acct.
######
sub cal_exists(@) {
    shift if ((ref $_[0]) eq __PACKAGE__);
    my $acct  = shift;
    my $cal   = shift;
    my $owner = shift;

    if (!defined $acct or !defined $cal) {
        die "cal_exists needs account and calendar name";
    }

    prime_cal_cache($acct);

    if (defined $owner) {
        # $acct, $cal and $owner
        # check $owner for a calendar with id matching rid
        prime_cal_cache($owner);

        my $cal_exists_in_acct=0;

        if (exists $cached_cals{$acct} && exists $cached_cals{$owner}) {
            my ($id, $rid);
            
            # get the id of the calendar to be shared:
            for my $c (@{$cached_cals{$owner}}) {
                $id = $c->{id}
                    if ($c->{name} eq $cal);
            }

            if (defined $id) {
                # the user could have renamed the calendar share so look for a 
                #  calendar with an rid that matches $id
                for my $c (@{$cached_cals{$acct}}) {
                    if (exists $c->{rid} && $id == $c->{rid}) {
                        # print $c->{name}, " is the share of $cal..\n";
                        return 1;
                    }

                }
            }
        }

        # check for a conflicting named calendar in $acct:
        for my $c (@{$cached_cals{$acct}}) {
            if (lc $c->{name} eq lc $cal) {
                # print "conflicting cal named $cal found in $acct.\n";
                return 1;
            }
        }
    } else {
        # just $acct and $cal
        # check for a calendar with name $cal
        if (exists $cached_cals{$acct}) {
            for my $c (@{$cached_cals{$acct}}) {
                if ($c->{name} eq $cal) {
                    # print "\t$cal exists in account $acct\n";
                    return 1;
                }
            }
        }
    }
    
    return 0; # cal was not found.
}


#######
sub clear_stale_cal_share {
    shift if ((ref $_[0]) eq __PACKAGE__);
    my $acct  = shift;
    my $cal   = shift;
    my $owner = shift;

    if (!defined $acct || !defined $cal || !defined $owner) {
        die "clear_stale_cal_share needs account, calendar name and owner";
    }
    prime_cal_cache($owner);
    prime_cal_cache($acct);

    my ($id, $rid, $share_owner, $cal_id);

    # if the user renamed the calendar there is nothing we can do: the
    # renamed share will be orphaned if the parent calendar is
    # deleted.  The user can delete it themselves of course.  If a new
    # global calednar is created the user will get a share with the
    # original name which they can then rename if they'd like.

    for my $ac (@{$cached_cals{$acct}}) {
        if ($ac->{name} eq $cal) {
            $rid = $ac->{rid};
            $cal_id = $ac->{id};
            $share_owner = $ac->{owner};
        }
    }

    # get the id of the calendar that might be shared:
    for my $oc (@{$cached_cals{$owner}}) {
        $id = $oc->{id}
            if ($oc->{name} eq $cal);
    }

    if (defined $id &&       # if the calendar exists in the user account
            defined $rid && defined $share_owner && # and it's a share
            $owner eq $share_owner && # and it's shared from $owner
            $rid != $id) {  # but they're not linked
        print "removing stale share $cal in $acct.\n";
        delete_cal($acct, $cal_id);
        # delete $acct from the cache so the change will be pulled
        # from Zimbra next time
        delete $cached_cals{$acct};
    }


}


#######
sub prime_cal_cache($) {
    shift if ((ref $_[0]) eq __PACKAGE__);
    my $acct = shift;

    return unless defined $acct;
    
    return if (exists $cached_cals{$acct});
    
    # See if the Calendar Mount exists.
    # delegate auth to the user
    my $d = new XmlDoc;
    $d->start('DelegateAuthRequest', $MAILNS);
    $d->add('account', $MAILNS, { by => "name" }, $acct);
    $d->end();

    my $r = check_context_invoke($d, \$context, $acct);

    # no need to do anything if a context can't be obtained.. the cache just won't be populated.
    return
        if (!defined $r);

    if ($r->name eq "Fault") {
        print "fault while delegating auth to $acct:\n";
        print Dumper($r);
        print "global calendars will not be added.\n";
        return;
    }

    my $new_auth_token = $r->find_child('authToken')->content;

    # assumes get_zimbra_context has been called to populate
    # $sessionId already.  I think that is a safe assumption
#    my $new_context = $SOAP->zimbraContext($new_auth_token, $sessionId);
    my $new_context = $SOAP->zimbraContext($new_auth_token, undef);

    my @my_cals;

    # Get all calendar mounts for the user
    $d = new XmlDoc();
    $d->start('GetFolderRequest', $Soap::ZIMBRA_MAIL_NS);
    $d->end();
      
    $r = $SOAP->invoke($url, $d->root(), $new_context);

    my $mc = (@{$r->children()})[0];

    for my $c (@{$mc->children()}) {
        if (exists $c->attrs->{view} && $c->attrs->{view} eq "appointment") {
                    
            if (defined $c->attrs->{rid}) {
                push @{$cached_cals{$acct}}, {name => $c->attrs->{name},
                                              rid => $c->attrs->{rid},
                                              owner => $c->attrs->{owner},
                                              id => $c->attrs->{id}};
            } else {
                push @{$cached_cals{$acct}}, {name => $c->attrs->{name},
                                              id => $c->attrs->{id}};
            }
        }
    }
}

}

#######
sub delete_cal {
    shift if ((ref $_[0]) eq __PACKAGE__);
    my $acct = shift;
    my $id = shift;

    defined $acct || return undef;
    defined $id || return undef;

    my $d = new XmlDoc;
    $d->start('DelegateAuthRequest', $MAILNS);
    $d->add('account', $MAILNS, { by => "name" }, $acct);
    $d->end();

    my $r = check_context_invoke($d, \$context, $acct);

    return undef
        if (!defined $r);

    if ($r->name eq "Fault") {
        print "fault while delegating auth to $acct:\n";
        print Dumper($r);
        return;
    }

    my $new_auth_token = $r->find_child('authToken')->content;
    my $new_context = $SOAP->zimbraContext($new_auth_token, undef);

    # Get all calendar mounts for the user
    $d = new XmlDoc();
    $d->start('FolderActionRequest', "urn:zimbraMail");
    $d->add('action', "urn:zimbraMail", {op => "delete", id => $id});
    $d->end();
      
    $r = check_context_invoke($d, \$new_context, $acct);
}

sub check_for_global_cals() {
    for my $c (@global_cals) {
        $c->{exists} = cal_exists($c->{owner}, $c->{name});
    }

}

sub get_relative_child_status_path {
    
    return $relative_child_status_path;
}


sub multi_proc_exit() {
    print "killing parent to cause complete exit..\n";
    kill('TERM', $parent_pid);            
    exit;
}


1;




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



# SearchDirectoryRequest for all users:
#
# <soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope">
#     <soap:Header>
#         <context xmlns="urn:zimbra">
#             <userAgent name="ZimbraWebClient - FF2.0 (Linux)"/>
#             <sessionId id="3481"/>
#             <authToken>
#                 0_8b41a60cf6a7dc8cb7c7e00fc66f939ce66cad5f_69643d33363a38373834623434372d346562332d343934342d626230662d6362373734303061303466653b6578703d31333a313139383930323638303831343b61646d696e3d313a313b747970653d363a7a696d6272613b
#             </authToken>
#             <format type="js"/>
#         </context>
#     </soap:Header>
#     <soap:Body>
#         <SearchDirectoryRequest xmlns="urn:zimbraAdmin" offset="0" limit="25" sortBy="name" sortAscending="1" attrs="displayName,zimbraId,zimbraMailHost,uid,zimbraAccountStatus,zimbraLastLogonTimestamp,description,zimbraMailStatus,zimbraCalResType,zimbraDomainType,zimbraDomainName" types="accounts">
#             <query/>
#         </SearchDirectoryRequest>
#     </soap:Body>
# </soap:Envelope>
#
#
# search directory request for a pattern:
# <soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope">
#     <soap:Header>
#         <context xmlns="urn:zimbra">
#             <userAgent name="ZimbraWebClient - FF2.0 (Linux)" version="undefined"/>
#             <sessionId id="277"/>
#             <authToken>
#                 0_93974500ed275ab35612e0a73d159fa8ba460f2a_69643d33363a30616261316231362d383364352d346663302d613432372d6130313737386164653032643b6578703d31333a313230363539303038353132383b61646d696e3d313a313b
#             </authToken>
#             <format type="js"/>
#         </context>
#     </soap:Header>
#     <soap:Body>
#         <SearchDirectoryRequest xmlns="urn:zimbraAdmin" offset="0" limit="25" sortBy="name" sortAscending="1" attrs="displayName,zimbraId,zimbraMailHost,uid,zimbraAccountStatus,description,zimbraMailStatus,zimbraCalResType,zimbraDomainType,zimbraDomainName" types="accounts">
#             <query>
#                 (|(uid=*morgan*)(cn=*morgan*)(sn=*morgan*)(gn=*morgan*)(displayName=*morgan*)(zimbraId=morgan)(mail=*morgan*)(zimbraMailAlias=*morgan*)(zimbraMailDeliveryAddress=*morgan*)(zimbraDomainName=*morgan*))
#             </query>
#         </SearchDirectoryRequest>
#     </soap:Body>
# </soap:Envelope>



# SearchDirectoryRequest for one user:
# <soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope">
#     <soap:Header>
#         <context xmlns="urn:zimbra">
#             <userAgent xmlns="" name="ZimbraWebClient - FF3.0 (Mac)"/>
#             <sessionId xmlns="" id="365"/>
#             <format xmlns="" type="js"/>
#             <authToken xmlns="">
#                 0_4902fe1a09f366ce4b32081df93a6798824aba26_69643d33363a66383466393832642d616464342d343034332d393734382d3431346366373035646539303b6578703d31333a313236343732343235333132383b61646d696e3d313a313b747970653d363a7a696d6272613b
#             </authToken>
#         </context>
#     </soap:Header>
#     <soap:Body>
#         <SearchDirectoryRequest xmlns="urn:zimbraAdmin" offset="0" limit="25" 
#         sortBy="name" sortAscending="1" 
#         attrs="displayName,zimbraId,zimbraMailHost,uid,zimbraCOSId,zimbraAccountStatus,zimbraLastLogonTimestamp,description,zimbraMailStatus,zimbraCalResType,zimbraDomainType,zimbraDomainName" 
#         types="accounts,aliases,distributionlists,resources,domains">
#             <query xmlns="">
#                 (|(uid=*morgan*)(cn=*morgan*)(sn=*morgan*)(gn=*morgan*)(displayName=*morgan*)(zimbraId=morgan)(mail=*morgan*)(zimbraMailAlias=*morgan*)(zimbraMailDeliveryAddress=*morgan*)(zimbraDomainName=*morgan*))
#             </query>
#         </SearchDirectoryRequest>
#     </soap:Body>
# </soap:Envelope>


# DeleteAccountRequest:
# <soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope">
#     <soap:Header>
#         <context xmlns="urn:zimbra">
#             <userAgent name="ZimbraWebClient - FF2.0 (Linux)"/>
#             <sessionId id="318864"/>
#             <format type="js"/>
#             <authToken>
#                 0_7b49e3d97c1a15ef72f5a0a344bfe417b82fc9a6_69643d33363a38323539616631392d313031302d343366392d613338382d6439393038363234393862623b6578703d31333a313230353830353735353338343b61646d696e3d313a313b747970653d363a7a696d6272613b6d61696c686f73743d31363a3137302e3233352e312e3234313a38303b
#             </authToken>
#         </context>
#     </soap:Header>
#     <soap:Body>
#         <DeleteAccountRequest xmlns="urn:zimbraAdmin">
#             <id>
#                 74c747fb-f209-475c-82c0-04fa09c5dedb
#             </id>
#         </DeleteAccountRequest>
#     </soap:Body>
# </soap:Envelope>


# search out all users in the store:
# <soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope">
#     <soap:Header>
#         <context xmlns="urn:zimbra">
#             <userAgent name="ZimbraWebClient - FF2.0 (Linux)"/>
#             <sessionId id="3174"/>
#             <format type="js"/>
#             <authToken>
#                 0_af79e67ac4da7ae8e7a298d97392b4f82bdd8f03_69643d33363a38323539616631392d313031302d343366392d613338382d6439393038363234393862623b6578703d31333a313230353931313737363633303b61646d696e3d313a313b747970653d363a7a696d6272613b6d61696c686f73743d31363a3137302e3233352e312e3234313a38303b
#             </authToken>
#         </context>
#     </soap:Header>
#     <soap:Body>
#         <SearchDirectoryRequest xmlns="urn:zimbraAdmin" offset="0" limit="25" sortBy="name" sortAscending="1" 
#         attrs="displayName,zimbraId,zimbraMailHost,uid,zimbraAccountStatus,zimbraLastLogonTimestamp,description,zimbraMailStatus,zimbraCalResType,zimbraDomainType,zimbraDomainName" types="accounts">
#             <query/>
#         </SearchDirectoryRequest>
#     </soap:Body>
# </soap:Envelope>
