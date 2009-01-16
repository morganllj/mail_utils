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


# TODO:
#       generalize build_zmailhost()
#       correct hacks.  Search in script for "hack."

# *****************************


##################################################################
#### Site-specific settings
#
# The Zimbra SOAP libraries.  Download and uncompress the Zimbra
# source code to get them.
use lib "/usr/local/zcs-5.0.2_GA_1975-src/ZimbraServer/src/perl/soap";
use POSIX ":sys_wait_h";
use IO::Handle;
# these accounts will never be added, removed or modified
#   It's a perl regex
my $exclude_group_rdn = "cn=orgexcludes";  # assumed to be in $ldap_base

# run case fixing algorithm (fix_case()) on these attrs.
#   Basically upcase after spaces and certain chars
my @z_attrs_2_fix_case = qw/cn displayname sn givenname/;

# attributes that will not be looked up in ldap when building z2l hash
# (see sub get_z2l() for more detail)
my @z2l_literals = qw/( )/;

# max delete recurse depth -- how deep should we go before giving up
# searching for users to delete:
# 5 == aaaaa*
my $max_recurse = 5;

# Number of processes to run simultaneously.
# I've only tested parallelism <= 4. 
# I suggest you test larger numbers for $parallelism and
# $users_per_proc on a development system..
my $parallelism = 4;
# number of users to process per fork.  If this number is too low the
# overhead of perl fork() can lock a Linux system solid.  I suggest
# keeping this > 50.
my $users_per_proc = 100;

# hostname for zimbra store.  It can be any of your stores.
# it can be overridden on the command line.
my $default_zimbra_svr = "dmail01.domain.org";
# zimbra admin password
my $default_zimbra_pass  = 'pass';

# default domain, used every time a user is created and in some cases
# modified.  Can be overridden on the command line.
my $default_domain       = "dev.domain.org";

my $archive_mailhost = "dmail02.domain.org";

# TODO: look up cos by name instead of requiring the user enter the cos id.
# prod:
#my $archive_cos_id = "249ef618-29d0-465e-86ae-3eb407b65540";
# dev:
my $archive_cos_id = "c0806006-9813-4ff2-b0a9-667035376ece";

# Global Calendar settings.  ldap2zimbra can create a calendar share
# in every user.
my $cal_owner = "calendar-admin\@" . $default_domain;
my $cal_name  = "Academic Calendar";
my $cal_path  = "/" . $cal_name;

my $child_status_path="/home/ldap2zimbra";





# default ldap settings, can be overridden on the command line
# my $default_ldap_host    = "ldap0.domain.org";
my $default_ldap_host    = "ldap0.domain.org";
my $default_ldap_base    = "dc=domain,dc=org";
my $default_ldap_bind_dn = "cn=Directory Manager";
my $default_ldap_pass    = "pass";
# good for testing/debugging:
my $default_ldap_filter = 
  "(|(orghomeorgcd=9500)(orghomeorgcd=8020)(orghomeorgcd=5020))";
#    "(orghomeorgcd=9500)";
# my $default_ldap_filter = "(orghomeorgcd=9500)";
#
# production:
#my $default_ldap_filter = "(objectclass=orgZimbraPerson)";

#### End Site-specific settings
#############################################################




use strict;
use Getopt::Std;
use Net::LDAP;
use Data::Dumper;
use XmlElement;
use XmlDoc;
use Soap;
$|=1;

sub print_usage();
sub add_user($);
sub sync_user($$);
sub get_z_user($);
sub fix_case($);
sub build_target_z_value($$$);
sub delete_not_in_ldap();
sub delete_in_range($$$);
sub parse_and_del($);
sub renew_context();
sub in_exclude_list($);
sub get_exclude_list();
sub build_archive_account($);


my $opts;
getopts('hl:D:w:b:em:ndz:s:p:a', \%$opts);

$opts->{h}                     && print_usage();
my $ldap_host = $opts->{l}     || $default_ldap_host;
my $ldap_base = $opts->{b}     || $default_ldap_base;
my $binddn =    $opts->{D}     || $default_ldap_bind_dn;
my $bindpass =  $opts->{w}     || $default_ldap_pass;
my $zimbra_svr = $opts->{z}    || $default_zimbra_svr;
my $zimbra_domain = $opts->{m} || $default_domain;
my $zimbra_pass = $opts->{p}   || $default_zimbra_pass;
my $subset_str = $opts->{s};

my $multi_domain_mode = $opts->{u} || "0";  # the default is to treat
					    # all users as in the
					    # default domain --
					    # basically take the 'uid'
					    # atribute from ldap and
					    # concat the default
					    # domain.

my $archive_domain = $zimbra_domain . ".archive";

my $fil = $default_ldap_filter;

# url for zimbra store.  It can be any of your stores
# my $url = "https://dmail01.domain.org:7071/service/admin/soap/";
my $url = "https://" . $zimbra_svr . ":7071/service/admin/soap/";

my $ACCTNS = "urn:zimbraAdmin";
my $MAILNS = "urn:zimbraAdmin";
my $SOAP = $Soap::Soap12;
my $sessionId;  # set in get_zimbra_context()

# hash ref to store a list of users added/modified to extra users can
# be deleted from zimbra.
my $all_users;
my $subset;
# has ref to store archive accounts that need to be sync'ed.
my $archive_accts;

print "-n used, no changes will be made.\n"
    if (exists $opts->{n});
print "-a used, archive accounts will be synced--".
    "this will almost double run time.\n"
    if (exists $opts->{a});

if (defined $subset_str) {
    for my $u (split /\s*,\s*/, $subset_str) {$subset->{lc $u} = 0;}
    print "\nlimiting to subset of users:\n", join (', ', keys %$subset), "\n";
    $fil = "(&" . $fil . "(|(uid=" . join (')(uid=', keys %$subset) . ")))";
}


print "\nstarting at ", `date`;
### keep track of accounts in ldap and added.
### search out every account in ldap.

# bind to ldap
my $ldap = Net::LDAP->new($ldap_host);
my $rslt = $ldap->bind($binddn, password => $bindpass);
$rslt->code && die "unable to bind as ", $binddn, ": ", $rslt->error;

my @exclude_list = get_exclude_list();  # this must be run before
					# in_exclude_list

my $context = get_zimbra_context();

# search users out of ldap
# here:
print "getting user list from ldap: $fil\n";
$rslt = $ldap->search(base => "$ldap_base", filter => $fil);
$rslt->code && die "problem with search $fil: ".$rslt->error;

# increment through users returned from ldap
print "\nadd/modify phase..", `date`;

my $pids;  # keep track of PIDs as child processes run
$SIG{HUP} = \&renew_context; # handler to cause context to be reloaded.
my $parent_pid; # used by check_context_invoke in the children: it
		# needs to know the proc to kill to tell the parent to
		# reload a stale $context

my $sleep_count=0;
my $usrs;

my @ldap_entries = $rslt->entries;
print $#ldap_entries + 1, " entries to process..\n"
    if (exists $opts->{d});

my $users_left = $#ldap_entries + 1;

#for my $lusr ($rslt->entries) {
for my $lusr (@ldap_entries) {
    my $usr;

    $users_left--;

    if ($multi_domain_mode) {
 	$usr = lc $lusr->get_value("mail");
    } else {
 	$usr = lc $lusr->get_value("uid") . "@" . $default_domain
    }

    # if $usr is undefined or empty there is likely no mail attribute: 
    # get the uid attribute and concatenate the default domain
    $usr = $lusr->get_value("uid") . "@" . $zimbra_domain
	if (!defined $usr || $usr =~ /^\s*$/);

    # keep track of users as we work on them so we can decide who to
    # delete later on.
    $all_users->{$usr} = 1;

    # skip user if a subset was defined on the command line and this
    # user is not part of it.
    if (defined $subset_str) {
 	my $username = (split /\@/, $usr)[0];

 	next unless (exists ($subset->{$username}) ||
 		     exists ($subset->{$usr}));
    }

    # skip users in ldap exclude list
    #   TODO: describe format of exclude list above
    #     should there be an option to skip checking for the exclude
    #     list?

      if (in_exclude_list($usr)) {
   	print "skipping special user $usr\n"
   	    if (exists $opts->{d});
   	next;
      }

    # batch users before continuing and forking.
    $usrs->{$usr} = $lusr;

    # loop unless we have $users_per_proc batched or we're out of users
    next
	if (keys %$usrs < $users_per_proc && $users_left != 0);
    print "heading for do..\n";

    my $proc_running = 0;  # indicates a process has been started.
    my $pidcount = 0;      # number of running processes.
    
    do {
	$pidcount = keys %$pids;

 	print "pidcount: $pidcount, parallelism: $parallelism\n"
 	    if (exists $opts->{d});

	# fork a process if there are less than $parallelism processes
	# running and there are users left to process.

	if ($pidcount < $parallelism && defined $usrs) {
	    $sleep_count = 1;

	    $parent_pid = $$;

	    my $pid = fork();
	    
	    if (defined($pid) && $pid == 0) {
		print "opening for reading: ". $child_status_path . "/" . $parent_pid.".".$$.".childout\n"
		    if (exists $opts->{d});

		open CHILD_WTR, ">". $child_status_path . "/" . $parent_pid.".".$$.".childout"
		    || die "can't open for writing: " . 
		    $child_status_path . "/" . $parent_pid.".".$$.".childout";
		for my $u (keys %$usrs) {
		    print "\nworking on ", $u, " ($$) ", `date`
			if (exists $opts->{d});
		    ### check for a corresponding zimbra account
		    my $zu_h = get_z_user($u);
		    if (!defined $zu_h) {
			add_user($usrs->{$u});
		    } else {
			sync_user($zu_h, $usrs->{$u})
		    }
		}
		close(CHILD_WTR);
		exit 0;
	    } elsif (defined($pid) && $pid > 0) {
		print "proc forked..\n";
		# $usrs has been passed to the child, clear it.
		$usrs = undef;
		$pids->{$pid} = 1;
		$proc_running++;
		$pidcount++;
	    } else {
		# TODO: count number of fork() failures and fail after a count.
		print "problem forking!? Sleeping and retrying..\n";
		sleep 1;
		next;
	    }

	}


	my $proc_reclaimed = 0;

	for my $p (keys %$pids) {
	    my $ret = waitpid(-1, WNOHANG);

	    if ($ret<0 || $ret>0) {
		print "process $ret finished..\n"
		    if (exists $opts->{d});
		open FROM_CHILD, $child_status_path . "/" . $parent_pid.".".$ret.".childout" ||
		    die "can't open for reading: ".
		    $child_status_path . "/" . $parent_pid.".".$ret.".childout";
		while (<FROM_CHILD>) {
		    chomp;
		    print "from child: /$_/\n";
		    $all_users->{$_} = 1;
		}
		close (FROM_CHILD);
		unlink ($child_status_path . "/" . $parent_pid.".".$ret.".childout");
		delete $pids->{$ret};
		$proc_reclaimed = 1;
	    }
	}

	# only sleep if one or more process didn't finish..  this
	#   allows us to spin off a new process if one's available
	#   but keeps us from busy waiting if all the processes
	#   are busy.
	unless ($proc_reclaimed) {
	    print "sleeping ", $sleep_count, ": no processes reclaimed...\n"
		if (exists $opts->{d});
	    sleep $sleep_count;
	    $sleep_count += 5;

	    # TODO: revisit this.. it really shouldn't happen but
	    # it will cause an infinite loop if it does.
	    # if ($sleep_count > 15) {
	    #    die "sleep_count is too high!  Aborting..";
	    # }
	}


	

    } until ($proc_running && $users_left > 0 || # a process is running and there are still users to process
 	     ($users_left == 0 && $pidcount < 1));   # or all processes
						  # are finished
						  # running and there are no users to process.
}


if (exists $opts->{e}) {
    # delete accounts that are not in ldap
    print "\ndelete phase, ",`date`;
    delete_not_in_ldap();
} else {
    print "\ndelete phase skipped (enable with -e)\n";
}


if (exists $opts->{a}) {
    # sync archive accounts.  We do this last as it more than doubles the
    # run time of the script and it's not critical.
    # TODO: parallelize this?
    print "\nsyncing archives, ", `date`;
    for my $acct_name (keys %$archive_accts) {

	print "\nworking on archive $acct_name ", " ", `date`
	    if (exists $opts->{d});

 	find_and_apply_user_diffs($archive_accts->{$acct_name}, 
				  get_z_user($acct_name), 1);
    }
} else {
    print "\nnot syncing archives (enable with -a)\n";
}


### get a list of zimbra accounts, compare to ldap accounts, delete
### zimbra accounts no longer in LDAP.

print "\nfinished at ", `date`;
$rslt = $ldap->unbind;




######
sub add_user($) {
    my $lu = shift;

    print "\nadding: ", $lu->get_value("uid"), ", ",
        $lu->get_value("cn"), "\n";

    my $z2l = get_z2l();

    # org hack
    # TODO: define a 'required' attribute in user definable section above.
    unless (defined build_target_z_value($lu, "orgghrsintemplidno", $z2l)) {
	print "\t***no orgghrsintemplidno, not adding.\n";
	return;
    }

    my $d = new XmlDoc;
    $d->start('CreateAccountRequest', $MAILNS);
    $d->add('name', $MAILNS, undef, $lu->get_value("uid")."@".$zimbra_domain);

    for my $zattr (sort keys %$z2l) {
	my $v = build_target_z_value($lu, $zattr, $z2l);

	if (!defined($v)) {
	    print "unable to build value for $zattr, skipping..\n";
	    next;
	}

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

    if (!exists $opts->{n}) {
	my $r = check_context_invoke($d, \$context);

	if ($r->name eq "Fault") {
	    print "problem adding user:\n";
	    print Dumper $r;
	    return;
	}

	my $mail;
	for my $c (@{$r->children()}) {
	    for my $attr (@{$c->children()}) {
		if ((values %{$attr->attrs()})[0] eq "mail") {
		    $mail = $attr->content();
		}
	    }
	}
	if (exists $opts->{d} && !exists $opts->{n}) {
	    $o = $r->to_string("pretty");
	    $o =~ s/ns0\://g;
	    print $o."\n";
	}

	add_global_calendar($mail);
    }



    # The user is newly created so does not have a legacy archive account..
    # get the archive name
    my $archive_acct_name = build_archive_account($lu);

    if (!defined(get_archive_account_id($archive_acct_name))) {
	# if the archive doesn't exist add it.
 	add_archive_acct($lu);
    } else {
	# if the archive exists do nothing.
	print "found existing archive account: ",$archive_acct_name,"\n";
    }
}



{
    my $archive_cache;  # local to sub get_archive_account()
    
    # get an active archive account from a user account
    sub get_archive_account {
	my ($zu) = @_;

	if (defined $zu && exists $zu ->{mail}) {
	    if (exists $archive_cache->{(@{$zu->{mail}})[0]}) {
		return $archive_cache->{(@{$zu->{mail}})[0]};
	    }
	}

	if (defined $zu &&
	    exists $zu->{zimbraarchiveaccount}) {

	    my $acct_name;

	    for $acct_name (@{$zu->{zimbraarchiveaccount}}) {
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
			return;
		    }
		}

		my $mc = $r2->find_child('account');

		if (defined $mc) {
		    #return ($mc->attrs->{name}, $mc->attrs->{id});
		    $archive_cache->{(@{$zu->{mail}})[0]} = 
			$mc->attrs->{name};
		    return ($mc->attrs->{name});
		}
	    }
	}
	return undef;
    }
}


{ my $no_such_folder_notified = 0;  # remember if we've notified about
				    # a mail.NO_SUCH_FOLDER error so
				    # we don't notify over and over.
  sub add_global_calendar($) {
      my $mail = shift;

      # delegate auth to the user
      my $d = new XmlDoc;
      $d->start('DelegateAuthRequest', $MAILNS);
      $d->add('account', $MAILNS, { by => "name" }, 
	      $mail);
      $d->end();

      my $r = check_context_invoke($d, \$context);

      if ($r->name eq "Fault") {
	  print "fault while delegating auth to $mail:\n";
	  print Dumper($r);
	  print "calendar $cal_name will not be added.\n";
	  return;
      }


      my $new_auth_token = $r->find_child('authToken')->content;

      # assumes get_zimbra_context has been called to populate
      # $sessionId already.  I think that is a safe assumption
      my $new_context = $SOAP->zimbraContext($new_auth_token, $sessionId);

      # create an xmlDoc
      my $d2 = new XmlDoc;
      # type of request (GetAccountRequest, CreateAccountRequest)
      $d2->start('CreateMountpointRequest', "urn:zimbraMail");
      $d2->add('link', "urn:zimbraMail", 
	       {"owner" => $cal_owner,
		"l" => "1",
		"path" => $cal_path,
		"name" => $cal_name});
      $d2->end();

      if (!exists $opts->{n}) {
	  my $r2 = check_context_invoke($d2, \$new_context);

	  if ($r2->name eq "Fault") {
	      my $rsn = get_fault_reason($r2);
	      
	      if ($rsn eq "mail.ALREADY_EXISTS") {
		  # do nothing
	      } elsif ($rsn eq "mail.NO_SUCH_FOLDER") { 
		  unless ($no_such_folder_notified) {
		      print "\n*** ERROR: There is no calendar named ".
                          "$cal_name under".
                     
			  "\n*** user $cal_owner.  No calendar will be ".
                          "shared.".

                          "\n*** This error will re-occur for every ".
                          "user but".

                          "\n*** this is the only notification you ".
                          "will receive.\n";

		      $no_such_folder_notified = 1;
		  }
	      } else {
		  print "\nFault during calendar create mount:\n";
		  print Dumper ($r2);
	      }
	  } else {
	      print "added calendar $cal_name to $mail\n";
	  }
      }
  }
}


# build a new archive account from $lu
sub build_archive_account($) {
    my $lu = shift;

    return $lu->get_value("orgghrsintemplidno")."\@".$archive_domain;
}


######
sub get_exclude_list() {
    
    my $r = $ldap->search(base => $ldap_base, filter => $exclude_group_rdn);
    $r->code && die "problem retrieving exclude list:" . $rslt->error;

    my @e = $r->entries;  # do we need to check for multiple entries?

    if ($#e != 0) {
	print "more than one entry found for $exclude_group_rdn:\n";
	for my $lu (@e) {
	    print "dn: ", $lu->dn(), "\n";
	}
	die;
    }

    my $exclude = $e[0];

    return $exclude->get_value("uniquemember");
}


######
# @exclude_list *must* be populated before this is run.
sub in_exclude_list($) {
    my $u = shift;
    
    for my $ex (@exclude_list) {
	unless ($multi_domain_mode) {
	    $ex = (split(/\@/, $ex))[0];
	    $u  = (split(/\@/, $u))[0];
	}
	
	return 1
	    if (lc($ex) eq lc($u));
    }
    
    return 0;
}


#####
# takes an argument because all subs called out of get_z2l have to.
# It ignores the argument.
sub get_archive_cos_id($) {

    return $archive_cos_id;
}


######
sub get_archive_account_id($) {
    my $a = shift;

    my $d2 = new XmlDoc;
    $d2->start('GetAccountRequest', $MAILNS); 
    $d2->add('account', $MAILNS, { "by" => "name" }, $a);
    $d2->end();
    
    my $r2 = check_context_invoke($d2, \$context);

    if ($r2->name eq "Fault") {
	my $rsn = get_fault_reason($r2);
	if ($rsn ne "account.NO_SUCH_ACCOUNT") {
	    print "problem searching out archive $a\n";
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
sub sync_user($$) {
    my ($zu, $lu) = @_;

    find_and_apply_user_diffs($lu, $zu);

    # get the archive account. Returns undef if the archive in
    # the user account doesn't exist.
    my $archive_acct_name = get_archive_account($zu);    
    
    if (!defined ($archive_acct_name)) {
	if (!defined(get_archive_account_id(build_archive_account($lu)))) {
	    # the archive account in the user does not exist.
	    add_archive_acct($lu);
	}
    } else {
	#$all_users->{$archive_acct_name} = 1;
	print "writing existing archive to parent ($$): $archive_acct_name\n"
	    if (exists $opts->{d});
	print CHILD_WTR "$archive_acct_name\n";

	# store the archive account name and the ldap user object for
	# later syncing.
	$archive_accts->{$archive_acct_name} = $lu
	    if (exists $opts->{a});
    }

    add_global_calendar((@{$zu->{mail}})[0]);
}



######
# find_and_apply_user_diffs knows it's been passed an archive
# account when it gets a zimbra_id as its last argument.
sub find_and_apply_user_diffs {
    my ($lu, $zu, $syncing_archive_acct) = @_;

    my $z2l;

    if (defined $syncing_archive_acct && $syncing_archive_acct == 1) {
	$z2l = get_z2l("archive");
    } else {
	$z2l = get_z2l();
	$syncing_archive_acct = 0;
    }

    my $zimbra_id = (@{$zu->{zimbraid}})[0];

    my $d = new XmlDoc();
    $d->start('ModifyAccountRequest', $MAILNS);
    $d->add('id', $MAILNS, undef, $zimbra_id);

    my $diff_found=0;

    for my $zattr (sort keys %$z2l) {
	my $l_val_str = "";
	my $z_val_str = "";

	if (!exists $zu->{$zattr}) {
	    $z_val_str = "";
	} else {
	    $z_val_str = join (' ', sort @{$zu->{$zattr}});
	}

	if ($syncing_archive_acct && $zattr eq "zimbramailhost") {
	    $l_val_str = $archive_mailhost;
	} else {
	    # build the values from ldap using zimbra capitalization
	    $l_val_str = build_target_z_value($lu, $zattr, $z2l);

	    if (!defined($l_val_str)) {
		print "unable to build value for $zattr, skipping..\n";
		next;
	    }
	}

# 	if (!defined($l_val_str)) {
# 	    print "$zattr is not defined, can't add user.  Aborting.\n";
# 	    return;
# 	}

 	if (($zattr =~ /amavisarchivequarantineto/i ||
 	    $zattr =~ /zimbraarchiveaccount/i) && 
	    !$syncing_archive_acct) {

 	    # set the archive acct attrs if the archive account exists
 	    # and is tied to the user.
 	    # if we don't set it here it will be set by
 	    # build_target_z_value above
 	    my $acct = get_archive_account($zu);
 	    if (defined $acct) {
 		$l_val_str = $acct;
 	    }
	}

	if ($l_val_str ne $z_val_str) {
	    
	    if ($diff_found == 0) {
		print "\n" if (!exists $opts->{d});
		print "syncing ", (@{$zu->{mail}})[0], "\n";
	    }
	    
	    if (exists $opts->{d}) {
		print "different values for $zattr:\n".
		    "\tldap:   $l_val_str\n".
		    "\tzimbra: $z_val_str\n";
	    } else {
		print "was: $zattr: $z_val_str\n";
	    }
	    
	    # zimbraMailHost 
	    if ($zattr =~ /^\s*zimbramailhost\s*$/) {
		print "zimbraMailHost diff found for ";
		print "", (@{$zu->{mail}})[0];
		print " Skipping.\n";
		print "\tldap:   $l_val_str\n".
		    "\tzimbra: $z_val_str\n";
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

	if (!exists $opts->{n}) {
	    my $r = check_context_invoke($d, \$context);

	    if (exists $opts->{d}) {
		print "response:\n";
		$o = $r->to_string("pretty");
		$o =~ s/ns0\://g;
		print $o."\n";
	    }
	}
    }

}



######
sub print_usage() {
    print "\n";
    print "usage: $0 [-n] [-d] [-e] [-h] -l <ldap host> -b <basedn>\n".
	"\t-D <binddn> -w <bindpass> -m <zimbra domain> -z zimbra host\n".
	"\t[-s \"user1,user2, .. usern\"] -p <zimbra admin user pass>\n";
    print "\n";
    print "\toptions in [] are optional, but all can have defaults\n".
	"\t(see script to set defaults)\n";
    print "\t-n print, don't make changes\n";
    print "\t-d debug\n";
    print "\t-e exhaustive search.  Search out all Zimbra users and delete\n".
	"\t\tany that are not in your enterprise ldap.  Steps have been \n".
	"\t\tto make this scale arbitrarily high.  It's been tested on \n".
	"\t\ttens of thousands successfully.\n";
    print "\t-h this usage\n";
    print "\t-D <binddn> Must have unlimited sizelimit, lookthroughlimit\n".
	"\t\tnearly Directory Manager privilege to view users.\n";
    print "\t-s \"user1, user2, .. usern\" provision a subset, useful for\n".
	"\t\tbuilding dev environments out of your production ldap or\n".
	"\t\tfixing a few users without going through all users\n".
	"\t\tIf you specify -e as well all other users will be deleted\n";
    print "\n";
    print "example: ".
	"$0 -l ldap.morganjones.org -b dc=morganjones,dc=org \\\n".
	"\t\t-D cn=directory\ manager -w pass -z zimbra.morganjones.org \\\n".
        "\t\t-m morganjones.org\n";
    print "\n";

    exit 0;
}


#######
sub get_z2l($) {
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
    #                                            orgWorkStreetShort (*proposed*)
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

    my $z2l;
    if (defined $type && $type eq "archive") {
	$z2l = {
	    "zimbramailhost" => \&get_z_archive_mailhost,
	    "zimbracosid"    => \&get_archive_cos_id,
	};
    } elsif (defined $type) {
	die "unknown type $type received in get_z2l.. ";
    } else {
	$z2l = {
	    "cn" =>                    ["cn"],
	    "zimbrapreffromdisplay" => ["givenname", "sn"],
	    "givenname" =>             ["givenname"],
	    "sn" =>                    ["sn"],
	    "company" =>               ["orghomeorg"],
	    "st" =>                    ["orgworkstate"],
	    "l" =>                     ["orgworkcity"],
	    "postalcode" =>            ["orgworkzip"],

	    "zimbramailhost" =>            \&build_zmailhost,
	    "zimbraarchiveaccount" =>      \&build_archive_account,
	    "amavisarchivequarantineto" => \&build_archive_account,
	    "co" =>                        \&build_phone_fax,
	    "street" =>                    \&build_address,
	    "displayname" =>               \&build_last_first,
            "zimbrapreffromdisplay" =>     \&build_last_first,
	};
    }

    return $z2l;
}


sub build_last_first($) {
    my $lu = shift;

    my $r = undef;

    if (defined (my $l = $lu->get_value("sn"))) {
	$r .= $l;
    }

    if (defined (my $f = $lu->get_value("givenname"))) {
	$r .= ", " if (defined $r);
	$r .= $f;
    }

    return $r;
}




######
sub build_phone_fax($) {
    my $lu = shift;

    my $r = undef;

    my $phone_separator = '-';

    if (defined (my $p = $lu->get_value("orgworktelephone"))) {
	$p =~ s/(\d{3})(\d{3})(\d{4})/$1$phone_separator$2$phone_separator$3/;
	$r .= "Phone: " . $p; 
    }

    if (defined (my $f = $lu->get_value("orgworkfax"))) {
	$r .= "  " if (defined $r);
	$f =~ s/(\d{3})(\d{3})(\d{4})/$1$phone_separator$2$phone_separator$3/;
	$r .= "Fax: " . $f;
    }

    return $r;
}


######
sub build_address($) {
    my $lu = shift;

    return $lu->get_value("orgworkstreet");
    return $lu->get_value("orgworkstreetshort");

}


######
sub build_zmailhost($) {
    my $lu = shift;

    my $org_id = $lu->get_value("orgghrsintemplidno");

    if (!defined $org_id) {
	print "WARNING! undefined SDP id, zimbraMailHost will be undefined\n";
	return undef;
    }

    my @i = split //, $org_id;
    my $n = pop @i;

    # TODO: revisit!  Add provisions for dmail02 and unknown domain
    if ($zimbra_domain eq "domain.org") {
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
		"zimbraMailHost.\n  This shouldn't be possible.. ";
	    return undef;
	}
    } elsif ($zimbra_domain eq "dev.domain.org") {
	if ($n =~ /^[0123456789]{1}$/) {
	    return "dmail01.domain.org";
	} else {
	    print "WARNING! SDP id $org_id did not resolve to a valid ".
		"zimbraMailHost.\n  This shouldn't be possible.. ".
		"returning undef.";
	    return undef;
	}
    } else {
	print "WARNING! zimbraMailHost will be undefined because domain ".
	    "$zimbra_domain is not recognized.\n";
	return undef;
    }
}


#######
sub get_z_user($) {
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
	    exit;
	}
    }

    my $middle_child = $r->find_child('account');
     #my $delivery_addr_element = $resp->find_child('zimbraMailDeliveryAddress');

    # user entries return a list of XmlElements
    return undef if !defined $middle_child;
    for my $child (@{$middle_child->children()}) {
	# TODO: check for multiple attrs.  The data structure allows
	#     it but I don't think it will ever happen.
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
# ignore argument
sub get_z_archive_mailhost($) {

    return $archive_mailhost;
}

######
sub build_target_z_value($$$) {
    my ($lu, $zattr, $z2l) = @_;

    my $t = ref($z2l->{$zattr});
    if ($t eq "CODE") {
	return &{$z2l->{$zattr}}($lu);
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
		@ldap_v = $lu->get_value($v);
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
sub delete_not_in_ldap() {
    my $r;
    my $d = new XmlDoc;
    $d->start('SearchDirectoryRequest', $MAILNS,
	      {'sortBy' => "uid",
	       'attrs'  => "uid",
	       'types'  => "accounts"}
	); 
    { $d->add('query', $MAILNS, { "types" => "accounts" });} 
    $d->end();

    $r = check_context_invoke($d, \$context);

    if ($r->name eq "Fault") {
	my $rsn = get_fault_reason($r);

	# break down the search by alpha/numeric if reason is 
	#    account.TOO_MANY_SEARCH_RESULTS
	if (defined $rsn && $rsn eq "account.TOO_MANY_SEARCH_RESULTS") {
	    print "\tfault due to $rsn\n";
	    print "\trecursing deeper to return fewer results.\n";
	    
	    delete_in_range(undef, "a", "z");
	    return;
	}

	if ($r->name ne "account") {
	    print "skipping delete, unknown record type returned: ", 
	    $r->name, "\n";
	    return;
	}

	parse_and_del($r);
    }
}



# check for and correct expired authentication during invoke.
#  The idea is to catch an expired auth token on the fly so as to not 
#  interrupt the running script.
sub check_context_invoke {
    my ($d, $context_ref) = @_;

    my $r = $SOAP->invoke($url, $d->root(), $$context_ref);

    if ($r->name eq "Fault") {
	my $rsn = get_fault_reason($r);
	if (defined $rsn && $rsn =~ /AUTH_EXPIRED/) {
	    # authentication timed out, re-authenticate and re-try the invoke
	    print "\tfault due to $rsn at ", `date`;
	    print "\tre-authenticating..\n";
	    $$context_ref = get_zimbra_context();
	    $r = $SOAP->invoke($url, $d->root(), $$context_ref);

	    print "killing $parent_pid to cause global ".
		"\$context to be reloaded..\n"
		if (exists $opts->{d});
	    kill('HUP', $parent_pid);
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
# renew global $context--usually in response to a signal from a child
sub renew_context () {
    print "renewing global context in response to signal in proc $$"
	if (exists($opts->{d}));

    $context = get_zimbra_context();
}



#######
# a, b, c, d, .. z
# a, aa, ab, ac .. az, ba, bb .. zz
# a, aa, aaa, aab, aac ... zzz
sub delete_in_range($$$) {
    my ($prfx, $beg, $end) = @_;

#     print "deleting ";
#     print "${beg}..${end} ";
#     print "w/ prfx $prfx " if (defined $prfx);
#     print "\n";

    for my $l (${beg}..${end}) {
	my $fil = 'uid=';
	$fil .= $prfx if (defined $prfx);
	$fil .= "${l}\*";

	print "searching $fil\n";
	my $d = new XmlDoc;
	$d->start('SearchDirectoryRequest', $MAILNS);
	$d->add('query', $MAILNS, undef, $fil);
	$d->end;

	my $r = check_context_invoke($d, \$context);
# debugging:
# 	if ($r->name eq "Fault" || !defined $prfx || 
#	    scalar (split //, $prfx) < 6 ) {
 	if ($r->name eq "Fault") {
# 	    # TODO: limit recursion depth
	    print "\tFault! ..recursing deeper to return fewer results.\n";
	    my $prfx2pass = $l;
	    $prfx2pass = $prfx . $prfx2pass if defined $prfx;

	    increment_del_recurse();
	    if (get_del_recurse() > $max_recurse) {
		print "\tmax recursion ($max_recurse) hit, backing off..\n";
		decrement_del_recurse();
		return 1; #return failure so caller knows to return
			  #and not keep trying to recurse to this
			  #level
	    }
 	    my $rc = delete_in_range ($prfx2pass, $beg, $end);
	    decrement_del_recurse();
	    return if ($rc);  # should cause us to drop back one level
			      # in recursion
 	} else {

	    parse_and_del($r);

        }
    }
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


#######
sub parse_and_del($) {

    my $r = shift;

    for my $child (@{$r->children()}) {
	my ($uid, $mail, $z_id);

	for my $attr (@{$child->children}) {

	    $uid = $attr->content()
		if ((values %{$attr->attrs()})[0] eq "uid");

	    $mail = $attr->content()
		if ((values %{$attr->attrs()})[0] eq "mail");

	    $z_id = $attr->content()
		if ((values %{$attr->attrs()})[0] eq "zimbraId");
 	}

	# skip special users
        if (in_exclude_list($uid)) {
	    print "\tskipping special user $uid\n"
		if (exists $opts->{d});
	    next;
	}

 	if (defined $mail && defined $z_id && 
	    !exists $all_users->{$mail}) {

	    if (defined $subset_str) {
		next unless (exists($subset->{$uid}) || 
			     exists($subset->{$mail}));
	    }

	    print "deleting $mail..\n";

 	    my $d = new XmlDoc;
 	    $d->start('DeleteAccountRequest', $MAILNS);
 	    $d->add('id', $MAILNS, undef, $z_id);
 	    $d->end();

 	    if (!exists $opts->{n}){
		my $r = check_context_invoke($d, \$context);

		if (exists $opts->{d}) {
		    my $o = $r->to_string("pretty");
		    $o =~ s/ns0\://g;
		    print $o."\n";
		}
	    }
	}
    }
}
    

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


sub get_zimbra_context {

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




sub add_archive_acct {
    #my ($lu, $z2l) = @_;
    my ($lu) = shift;

    my $z2l = get_z2l("archive");

    my $archive_account = build_archive_account($lu);

    print "adding archive: ", $archive_account,
        " for ", $lu->get_value("uid"), "\n";
#    $all_users->{(split /\@/, $archive_account)[0]} = 1;
    #$all_users->{$archive_account} = 1;
    print "writing newly created archive to parent ($$): $archive_account\n"
	if (exists $opts->{d});
    print CHILD_WTR "$archive_account\n";

    my $d3 = new XmlDoc;
    $d3->start('CreateAccountRequest', $MAILNS);
    $d3->add('name', $MAILNS, undef, $archive_account);


    for my $zattr (sort keys %$z2l) {
	my $v;

	$v = build_target_z_value($lu, $zattr, $z2l);

	if (!defined($v)) {
	    print "ERROR: unable to build value for $zattr, skipping..\n";
	    next;
	}
	
	$d3->add('a', $MAILNS, {"n" => $zattr}, $v);
    }
    $d3->end();

    my $o;
    if (exists $opts->{d}) {
	print "here's what we're going to change:\n";
	$o = $d3->to_string("pretty")."\n";
	$o =~ s/ns0\://g;
	print $o."\n";
    }

    if (!exists $opts->{n}) {
	my $r3 = check_context_invoke($d3, \$context);

	if ($r3->name eq "Fault") {
	    print "problem adding user:\n";
	    print Dumper $r3;
	}

	if (exists $opts->{d} && !exists $opts->{n}) {
	    $o = $r3->to_string("pretty");
	    $o =~ s/ns0\://g;
	    print $o."\n";
	}
    }

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
