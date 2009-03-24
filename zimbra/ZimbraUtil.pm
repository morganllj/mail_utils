package ZimbraUtil;
# Author: Morgan Jones (morgan@morganjones.org)
# Id:     $Id$
#

use strict;
use lib "/usr/local/zcs-5.0.2_GA_1975-src/ZimbraServer/src/perl/soap";
use XmlElement;
use XmlDoc;
use Soap;
use Data::Dumper;
use Net::LDAP;

our $url;
our $ACCTNS = "urn:zimbraAdmin";
our $MAILNS = "urn:zimbraAdmin";
our $SOAP;
our $sessionId;
our $zimbra_pass;
# max delete recurse depth -- how deep should we go before giving up
# searching for users to delete:
# 5 == aaaaa*
our $max_recurse = 5;
our $context;



#####
sub return_all_accounts {
    return operate_on_user_list(func=>\&parse_and_return_list, 
                                filter=>"(|(uid=j*)(uid=k*))");
}


#####
sub rename_all_archives {
#    return operate_on_user_list(func=>\&rename_archives, 
#                                filter=>"(|(uid=j*)(uid=k*))");

#    return operate_on_user_list(func=>\&rename_archives, 
#                                filter=>"(uid=a*)");

    return operate_on_user_list(func=>\&rename_archives);

}





sub new {
    my $class = shift;
    ($url, $zimbra_pass) = @_;

    my $self = {};

    bless($self, $class);

    $SOAP = $Soap::Soap12;

    $context = get_context();

    return $self;
}


# check for and correct expired authentication during invoke.
#  The idea is to catch an expired auth token on the fly so as to not 
#  interrupt the running script.
sub check_context_invoke {
    my ($d, $context_ref) = @_;

    my $debug=1;
    
    my $r = $SOAP->invoke($url, $d->root(), $$context_ref);

    if ($r->name eq "Fault") {
	my $rsn = get_fault_reason($r);
	if (defined $rsn && $rsn =~ /AUTH_EXPIRED/) {
	    # authentication timed out, re-authenticate and re-try the invoke
	    print "\tfault due to $rsn at ", `date`;
	    print "\tre-authenticating..\n";
	    $$context_ref = get_zimbra_context();
	    $r = $SOAP->invoke($url, $d->root(), $$context_ref);

# 	    print "killing $parent_pid to cause global ".
# 		"\$context to be reloaded..\n"
#                 if (defined $debug);
# 	    kill('HUP', $parent_pid);
	    if ($r->name eq "Fault") {
		$rsn = get_fault_reason($r);
		if (defined $rsn && $rsn =~ /AUTH_EXPIRED/) {
		    print "got $rsn *again* ... ".
			"this shouldn't happen, exiting.\n";
		    print Dumper($r);
		    exit;
		} else {
		    # we got a fault of some other sort, return to the
		    # caller to handle the fault
		    return $r;
		}
	    }
	}
    }
    return $r;
}







######
sub get_context {

    # authenticate to Zimbra admin url
    my $d = new XmlDoc;
    $d->start('AuthRequest', $ACCTNS);
    $d->add('name', undef, undef, "admin");
    $d->add('password', undef, undef, $zimbra_pass);
    $d->end();

    # get back an authResponse, authToken, sessionId & context.
    my $authResponse = $SOAP->invoke($url, $d->root());

    my $authToken = $authResponse->find_child('authToken')->content;
    # this needs to global to allow delegated auth to work..
    $sessionId = $authResponse->find_child('sessionId')->content;

    return $SOAP->zimbraContext($authToken, $sessionId);
}



#######
sub parse_and_return_list($) {
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
sub rename_archives($) {
    my $r = shift;

#    print "r passed in: ". Dumper ($r);

    my $ldap_host = "ldap0.domain.org";
    my $binddn = "cn=directory\ manager";
    my $bindpass = "pass";
    my $ldap_base = "dc=domain,dc=org";

    # bind to ldap
    my $ldap = Net::LDAP->new($ldap_host);
    my $rslt = $ldap->bind($binddn, password => $bindpass);
    $rslt->code && die "unable to bind as ", $binddn, ": ", $rslt->error;
    


    my @l;

    for my $child (@{$r->children()}) {
        my ($mail, $z_id, $archive, $amavis_to, $uid);

        for my $attr (@{$child->children}) {
            $mail = $attr->content()
                if (lc((values %{$attr->attrs()})[0]) eq "mail");
            $z_id = $attr->content()
                if (lc((values %{$attr->attrs()})[0]) eq "zimbraid");
            $archive = $attr->content()
                if (lc((values %{$attr->attrs()})[0]) eq "zimbraarchiveaccount");
            $amavis_to = $attr->content()
                if (lc((values %{$attr->attrs()})[0]) eq "amavisarchivequarantineto");
            $uid = $attr->content()
                if (lc((values %{$attr->attrs()})[0]) eq "uid");
        }

        # skip to next if we're on an archive account
        
        my $archive_suffix = "archive";
        next unless (defined $mail && $mail !~ /$archive_suffix$/);

        #print "working on mail: $mail\n";





        my $zimbra_limit_filter = "(objectclass=orgzimbraperson)";


        my $fil;
        $fil = "(&" . $zimbra_limit_filter
            if (defined $zimbra_limit_filter);

        $fil .= "(uid=$uid)";
        
        $fil .= ")";

        
#        print "searching $fil..\n";
        $rslt = $ldap->search(base => "$ldap_base", filter => $fil);
        $rslt->code && die "problem with search $fil: ".$rslt->error;  

        my $lusr = ($rslt->entries)[0];

        if (!defined $lusr) {
            print "$mail is not in ldap!?\n";
            next;
        }
                

        my $int_empl_id = $lusr->get_value("orgghrsintemplidno");

        if ($amavis_to ne $archive) {
            print "warning, amavisarchivequarantineto and zimbraarchiveaccount ".
                "don't match for $uid:\n";
            print $amavis_to . " vs. ". $archive. "\n";
            #TODO: do something?
        }
        
        
        my $archive_usr_part = (split /@/, $archive)[0];
        if (lc $int_empl_id !~ lc $archive_usr_part) {
            print "archive differs for $uid: $int_empl_id vs $archive\n";
            # TODO: make sure archive exists.  Create it?  move it.


            # rename archive account

            # if that's successful change the 

        }
    }
}



#####
sub operate_on_user_list() {
    my %args = @_;
    my $debug=1;

    exists $args{func} || return undef;
    
    my $func = $args{func};
    my $search_fil = undef;
    if (exists ($args{filter})) {
        $search_fil = $args{filter};
        print "set search filter: $search_fil\n";
    }

    #my $r = $SOAP->invoke($url, $d2->root(), $context);
    my $d = new XmlDoc;

#     $d->start('SearchDirectoryRequest', $MAILNS,
#                {'sortBy' => "uid",
#                 'attrs'  => "uid",
#                 'types'  => "accounts"}
#            ); 

     $d->start('SearchDirectoryRequest', $MAILNS, {'types'  => "accounts"}
            ); 


    if (defined $search_fil) {

        #print "searching with fil $search_fil\n" if $debug;
        $d->add('query', $MAILNS, { "types" => "accounts" }, $search_fil);
    } else {
        $d->add('query', $MAILNS, { "types" => "accounts" });
    }
    
# $d2->end();


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

            
            # @l = get_list_in_range(undef, "a", "z");
            @l = operate_on_range(undef, "a", "z", $func, $search_fil);
        } else {
            print "unhandled reason: $rsn, exiting.\n";
            exit;
        }
    } else {
#         if ($r->name ne "account") {
#             print "skipping delete, unknown record type returned: ", $r->name, "\n";
#             return;
#         }
        
        print "returned ", $r->num_children, " children\n";
        
        #@l = parse_and_return_list($r);
        @l = $func->($r);
    }

    return @l;
}








#######
# a, b, c, d, .. z
# a, aa, ab, ac .. az, ba, bb .. zz
# a, aa, aaa, aab, aac ... zzz
#sub get_list_in_range($$$) {
sub operate_on_range {
    #my ($prfx, $beg, $end) = @_;
    my ($prfx, $beg, $end, $func, $search_fil) = @_;

    my $debug=1;

#     print "deleting ";
#     print "${beg}..${end} ";
#     print "w/ prfx $prfx " if (defined $prfx);
#     print "\n";

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
# debugging:
# 	if ($r->name eq "Fault" || !defined $prfx || 
#	    scalar (split //, $prfx) < 6 ) {
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
                push @l, operate_on_range ($prfx2pass, $beg, $end, $func, $search_fil);
		decrement_del_recurse();
	    } else {
		print "unhandled reason: $rsn, exiting.\n";
		exit;
	    }

 	} else {
	    # push @l, parse_and_return_list($r);
	    push @l, $func->($r);
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
sub get_fault_reason {
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
