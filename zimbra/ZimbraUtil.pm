package ZimbraUtil;
# Author: Morgan Jones (morgan@morganjones.org)
# Id:     $Id$
#
# TODO: check where variables are initialized and move to new if appropriate.

use strict;
use lib "/usr/local/zcs-5.0.2_GA_1975-src/ZimbraServer/src/perl/soap";
use XmlElement;
use XmlDoc;
use Soap;
use Data::Dumper;
use Net::LDAP;



# Defaults
# max delete recurse depth -- how deep should we go before giving up
# searching for users to delete:
# 5 == aaaaa*
my $max_recurse = 5;
my $debug=0;
my $printonly=0;
my $parent_pid;
my %subset;
my $ldap;
my @exclude_list;

# ldap defaults
my %l_params = (
    l_host => "ldap0.domain.org",
    l_binddn => "cn=directory manager",
    l_bindpass => "pass",
    l_base => "dc=domain,dc=org",

    # debugging:
    # l_filter = 
    #  "(|(orghomeorgcd=9500)(orghomeorgcd=8020)(orghomeorgcd=5020))";
    #    "(orghomeorgcd=9500)";
    # l_filter = "(orghomeorgcd=9500)";
    #
    # production:
    l_filter => "(objectclass=orgZimbraPerson)"
);

my $exclude_group_rdn = "cn=orgexcludes";  # assumed to be in $ldap_base

# Zimbra defaults
my %z_params = (
    z_server => "dmail01.domain.org",
    z_pass => "pass",
    z_domain => "dev.domain.org",  # mail domain
    z_archive_mailhost => "dmail02.domain.org",
    z_archive_suffix => "archive",
    z_domain => "dev.domain.org",
    z_archive_mailhost => "dmail02.domain.org",
    # production:
    # z_archive_cos_id => "249ef618-29d0-465e-86ae-3eb407b65540",
    # dev:
    z_archive_cos_id => "c0806006-9813-4ff2-b0a9-667035376ece",
);
my $zimbra_limit_filter = "(objectclass=orgzimbraperson)";
my $ACCTNS = "urn:zimbraAdmin";
my $MAILNS = "urn:zimbraAdmin";
my $SOAP;
my $sessionId;
my $context;

$z_params{z_url} = "https://" . $z_params{z_server} . ":7071/service/admin/soap/";
$z_params{z_archive_domain} = $z_params{z_domain} . "." . "archive";

# general defaults
my %g_params;


# Top level public functions
#####
sub return_all_accounts {
    return operate_on_user_list(func=>\&ooul_func_return_list, 
                                filter=>"(|(uid=j*)(uid=k*))");
}


#####
sub rename_all_archives {
    shift if ((ref $_[0]) eq __PACKAGE__);

    return operate_on_user_list(func=>\&ooul_func_rename_archives, @_);
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

            if ($k eq "g_debug") { $debug = 1; }

            if ($k eq "g_printonly") {
                $printonly = $args{$k};
                print "-n used, no changes will be made..\n";
            }
            $g_params{$k} = $args{$k};
        } else {
            warn "can't find  matching key for ", __PACKAGE__, " named argument $k.  it will be ignored";
        }
    }
    

    my $self = {};

    bless($self, $class);

    $SOAP = $Soap::Soap12;

    $context = get_zimbra_context();

    return $self;
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


    # bind to ldap
    my $ldap = Net::LDAP->new($l_params{l_host});
    my $rslt = $ldap->bind($l_params{l_binddn}, password => $l_params{l_bindpass});
    $rslt->code && die "unable to bind as ", $l_params{l_binddn}, ": ", $rslt->error;

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
        
        $rslt = $ldap->search(base => $l_params{l_base}, filter => $fil);
        $rslt->code && die "problem with search $fil: ".$rslt->error;  

        my $lusr = ($rslt->entries)[0];

        if (!defined $lusr) {
            print "\n$mail is not in ldap..\n";
            next;
        }
        
        # get internal employee id from ldap

        my $int_empl_id;
        if (exists $args{attr_frm_ldap}) {
            $int_empl_id = $lusr->get_value($args{attr_frm_ldap});
        } else {
            die "no attribute received in ooul_func_rename_archives";
        }
        

        if (defined($amavis_to) && defined($archive) && $amavis_to ne $archive) {
            print "\nwarning, amavisarchivequarantineto and zimbraarchiveaccount ".
                "don't match for $uid:\n";
            print $amavis_to . " vs. ". $archive. "\n";
            #TODO: do something?
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

                unless ($printonly) {
                    my $r = check_context_invoke($d, \$context);
                    if ($r->name eq "Fault") {
                        my $rsn = get_fault_reason($r);
                        
                        print "problem renaming user: $rsn\n";
                        print Dumper($r);
                        next;
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

            unless ($printonly) {
                my $r2 = check_context_invoke($d2, \$context);
                if ($r->name eq "Fault") {
                    my $rsn = get_fault_reason($r2);
                    
                    print "problem setting attribures (zimbraarchiveaccount and ".
                        "amavisarchivequarantineto):\n\t$rsn\n";
                    print Dumper($r2);
                    next;
                }
            }
        }
    }
}







###################
# Utility functions
#####

sub get_zimbra_usrs_frm_ldap {
    shift if ((ref $_[0]) eq __PACKAGE__);

#TODO: unbind ldap
    my $fil = $l_params{l_filter};
    $ldap = Net::LDAP->new($l_params{l_host});
    my $rslt = $ldap->bind($l_params{l_binddn}, password => $l_params{l_bindpass});
    $rslt->code && die "unable to bind as ", $l_params{binddn}, ": ", $rslt->error;

    if (exists $l_params{l_subset}) {
        for my $u (split /\s*,\s*/, $l_params{l_subset}) {$subset{lc $u} = 1;}
        print "\nlimiting to subset of users:\n", join (', ', keys %subset), "\n";
        $fil = "(&" . $fil . "(|(uid=" . join (')(uid=', keys %subset) . ")))";
    }

    print "getting user list from ldap: $fil\n";

    $rslt = $ldap->search(base => $l_params{l_base}, filter => $fil);
    $rslt->code && die "problem with search $fil: ".$rslt->error;

    return $rslt->entries;
}

######
sub get_exclude_list() {
    shift if ((ref $_[0]) eq __PACKAGE__);
    
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

#    return $exclude->get_value("uniquemember");
    @exclude_list = $exclude->get_value("uniquemember");
}


######
# @exclude_list *must* be populated before this is run.
sub in_exclude_list($) {
    my $u = shift;
    
    for my $ex (@exclude_list) {
#	unless ($multi_domain_mode) {
	unless ($g_params{multi_domain_mode}) {
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

    return 1 if ($g_params{multi_domain_mode});
    return 0;
}


#########
sub in_subset {
    shift if ((ref $_[0]) eq __PACKAGE__);

    my $u = shift;

    my $username;
    if ($u =~ /@/) {
        $username = (split /\@/, $u)[0];
    }

    return 1
        if (!%subset || ((exists $subset{$u}) ||
                        (defined $username && exists $subset{$username})));

    return 0;
}


sub operate_on_user_list {
    shift if ((ref $_[0]) eq __PACKAGE__);

    my %args = @_;

    exists $args{func} || return undef;
    
    my $func = $args{func};
    my $search_fil = undef;

    my $d = new XmlDoc;
    $d->start('SearchDirectoryRequest', $MAILNS, {'types'  => "accounts"}); 

    if (exists $args{filter}) {
        print "searching with fil $args{filter}\n" if $debug;
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
                if $debug;

            @l = operate_on_range(undef, "a", "z", $func, %args);
        } else {
            print "unhandled reason: $rsn, exiting.\n";
            exit;
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
 	    if $debug;

	my $d = new XmlDoc;
	$d->start('SearchDirectoryRequest', $MAILNS);
	$d->add('query', $MAILNS, { "types" => "accounts" }, $fil);
	$d->end;
	
	#my $r = $SOAP->invoke($url, $d->root(), $context);
        my $r = check_context_invoke($d, \$context);

 	if ($r->name eq "Fault") {
	    my $rsn = get_fault_reason ($r);

	    # break down the search by alpha/numeric if reason is 
	    #    account.TOO_MANY_SEARCH_RESULTS
	    if (defined $rsn && $rsn eq "account.TOO_MANY_SEARCH_RESULTS") {
		if (defined $debug) {
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

		# push @l, get_list_in_range ($prfx2pass, $beg, $end);
                push @l, operate_on_range ($prfx2pass, $beg, $end, $func, %args);
		decrement_del_recurse();
	    } else {
		print "unhandled reason: $rsn, exiting.\n";
		exit;
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
    $d->add('name', undef, undef, "admin");
    $d->add('password', undef, undef, $z_params{z_pass});
    $d->end();

    # get back an authResponse, authToken, sessionId & context.
    my $r = $SOAP->invoke($z_params{z_url}, $d->root());

    # if we get a fault here there is not much that can be done.
    return undef
        if ($r->name eq "Fault");


    my $authToken = $r->find_child('authToken')->content;
    $sessionId = $r->find_child('sessionId')->content;

    my $cntxt = $SOAP->zimbraContext($authToken, $sessionId);

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
        $sessionId = $r->find_child('sessionId')->content;
        
        my $new_cntxt = $SOAP->zimbraContext($authToken, $sessionId);

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
                        if (defined $debug);
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

1;
