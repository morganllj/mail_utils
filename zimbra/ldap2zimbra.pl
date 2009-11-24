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
#       check that writing tmp files failure doesn't cause all users to be deleted

# *****************************
my $script_dir;
BEGIN {
    # get the current working directory from $0 and add it to @INC so 
    #    ZimbraUtil can be found in the same directory as ldap2zimbra.
    $script_dir = $0;
    if ($0 =~ /\/[^\/]+$/) {
        $script_dir =~ s/\/[^\/]+\/*\s*$//;
        unshift @INC, $script_dir;
    }
}

# my $script_dir = $0;
# if ($0 =~ /\/[^\/]+$/) {
#     $script_dir =~ s/\/[^\/]+\/*\s*$//;
#     unshift @INC, $script_dir;
# } else {
#     $script_dir = ".";
# }

##################################################################
#### Site-specific settings
#
# The Zimbra SOAP libraries.  Download and uncompress the Zimbra
# source code to get them.
use lib "/usr/local/zcs-5.0.2_GA_1975-src/ZimbraServer/src/perl/soap";
use POSIX ":sys_wait_h";
use IO::Handle;

# run case fixing algorithm (fix_case()) on these attrs.
#   Basically upcase after spaces and certain chars
#my @z_attrs_2_fix_case = qw/cn displayname sn givenname/;

# attributes that will not be looked up in ldap when building z2l hash
# (see sub get_z2l() for more detail)
#my @z2l_literals = qw/( )/;

# Number of processes to run simultaneously.
# I've only had consistent success with <= 2. 
# I suggest you test larger numbers for $parallelism and
# $users_per_proc on a development system..
my $parallelism = 2;
# number of users to process per fork.  If this number is too low the
# overhead of perl fork() can lock a Linux system solid.  I suggest
# keeping this > 50.
my $users_per_proc = 500;

my $child_status_path=$script_dir . "/child_status";
die "can't write to child status directory: $child_status_path" if (! -w $child_status_path);

#### End Site-specific settings
#############################################################
use strict;
use Getopt::Std;
use Data::Dumper;
use ZimbraUtil;
$|=1;

sub print_usage();

my %opts;
my %arg_h;
getopts('hl:D:w:b:em:ndz:s:p:ar', \%opts);

exists $opts{h} && print_usage();
my $zimbra_svr =    $opts{z};
my $zimbra_domain = $opts{m};
my $zimbra_pass =   $opts{p};

# my $archive_domain = $zimbra_domain . ".archive";

# TODO handle unimplemented args:
for my $k (keys %opts) {
    if    ($k eq "h")   { print_usage() }
    elsif ($k eq "l")   { $arg_h{l_host}      = $opts{l}; }
    elsif ($k eq "D")   { $arg_h{l_binddn}    = $opts{D}; } 
    elsif ($k eq "w")   { $arg_h{l_bindpass}  = $opts{w}; }
    elsif ($k eq "b")   { $arg_h{l_base}      = $opts{b}; }
    elsif ($k eq "z")   { $arg_h{z_server}    = $opts{z}; }
    elsif ($k eq "m")   { $arg_h{z_domain}    = $opts{m}; }
    elsif ($k eq "p")   { $arg_h{z_pass}      = $opts{p}; }
    elsif ($k eq "e")   { $arg_h{g_extensive} = 1; }
    elsif ($k eq "n")   { $arg_h{g_printonly} = 1; }
    elsif ($k eq "d")   { $arg_h{g_debug}     = 1; }
    elsif ($k eq "p")   { $arg_h{g_multi_domain} = 1; }
    elsif ($k eq "s")   { $arg_h{l_subset}    = $opts{s}; }
    elsif ($k eq "a")   { $arg_h{g_sync_archives} = 1; }
    elsif ($k eq "r")   { $arg_h{g_dont_delete_archives} = 1; }
    elsif ($k eq "h")   { print_usage(); }
    else                { print "unimplemented option: -${k}:"; 
                          print_usage(); }
}


my $parent_pid = $$;
my $zu = new ZimbraUtil($parent_pid, %arg_h);

print "-a used, archive accounts will be synced--".
    "this will almost double run time.\n"
    if (exists $opts{a});
print "-r used, archives will not be deleted\n"
    if (exists $opts{r});

#$zu->check_for_global_cals();

print "\nstarting at ", `date`;

my @ldap_entries = $zu->get_zimbra_usrs_frm_ldap();
#$zu->get_exclude_list();

print "\nadd/modify phase..", `date`;

my $pids;  # keep track of PIDs as child processes run
$SIG{HUP} = \&renew_context; # handler to cause context to be reloaded.

my $sleep_count=0;
my $usrs;

print $#ldap_entries + 1, " entries to process..\n";

my $users_left = $#ldap_entries + 1;

for my $lusr (@ldap_entries) {
    my $usr;

    $users_left--;

    if ($zu->in_multi_domain_mode()) {
  	$usr = lc $lusr->get_value("mail");
    } else {
  	$usr = lc $lusr->get_value("uid") . "@" . $zu->get_z_domain()
    }

    # if $usr is undefined or empty there is likely no mail attribute: 
    # get the uid attribute and concatenate the default domain
    $usr = $lusr->get_value("uid") . "@" . $zu->get_zimbra_domain()
	if (!defined $usr || $usr =~ /^\s*$/);

    # keep track of users as we work on them so we can decide who to
    # delete later on.
    $zu->add_to_all_users($usr);

    # skip user if a subset was defined on the command line and this
    # user is not part of it.
    # if no subset is defined this sub is a noop.
    next unless ($zu->in_subset($usr));

    # skip users in ldap exclude list
    #   TODO: describe format of exclude list above
    #     should there be an option to skip checking for the exclude
    #     list?
    
    if ($zu->in_exclude_list($usr)) {
   	print "skipping special user $usr\n"
            if (exists $opts{d});
   	next;
    }

    # batch users before continuing and forking.
    $usrs->{$usr} = $lusr;
        
    # loop unless we have $users_per_proc batched or we're out of users
    next
	if (keys %$usrs < $users_per_proc && $users_left != 0);

    my $proc_running = 0;  # indicates a process has been started.
    my $pidcount = 0;      # number of running processes.
    
    do {
	$pidcount = keys %$pids;

 	print "pidcount: $pidcount, parallelism: $parallelism\n"
 	    if (exists $opts{d});

	# fork a process if there are less than $parallelism processes
	# running and there are users left to process.

	if ($pidcount < $parallelism && defined $usrs) {
	    $sleep_count = 1;

	    my $pid = fork();
	    
	    if (defined($pid) && $pid == 0) {
                # Child
                my $child_status_file = $child_status_path . "/" . 
                    $parent_pid.".".$$.".childout\n";

		print "opening for writing: ". $child_status_file
		    if (exists $opts{d});
		open CHILD_WTR, ">". $child_status_file
		    || die "can't open for writing: " . $child_status_file;

		for my $u (keys %$usrs) {
		    print "\nworking on ", $u, " ($$) ", `date`
			if (exists $opts{d});
		    ### check for a corresponding zimbra account
		    my $zu_h = $zu->get_z_user($u);
		    if (!defined $zu_h) {
			$zu->add_user($usrs->{$u}, *CHILD_WTR{IO});
		    } else {
			$zu->sync_user($zu_h, $usrs->{$u}, *CHILD_WTR{IO})
		    }
		}
		close(CHILD_WTR);
		exit 0;
	    } elsif (defined($pid) && $pid > 0) {
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
		    if (exists $opts{d});
		
		my $child_status_file = $child_status_path . "/" . 
                    $parent_pid.".".$ret.".childout";

                die "can't read child status file: ". $child_status_file
                    if (! -r $child_status_file);

		open FROM_CHILD, $child_status_file ||
		    die "can't open for reading: " . $child_status_file;

		while (<FROM_CHILD>) {
		    chomp;
		    print "from child: /$_/\n"
		      if exists ($opts{d});
                    $zu->add_to_all_users($_);
		}
		close (FROM_CHILD);
		unlink $child_status_file;
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
		if (exists $opts{d});
	    sleep $sleep_count;
	    $sleep_count += 5;

	    # TODO: revisit this.. it really shouldn't happen but
	    # it will cause an infinite loop if it does.
	    # if ($sleep_count > 15) {
	    #    die "sleep_count is too high!  Aborting..";
	    # }
	}

    } until ($proc_running && $users_left > 0 || # a process is running and 
                                                 # there are still users to process
 	     ($users_left == 0 && $pidcount < 1)); # or all processes
						   # are finished
						   # running and there are no users to process.
}

# these will check to see if delete/archive sync are enabled before doing anything.
$zu->delete_not_in_ldap();
$zu->sync_archive_accts();

# TODO: unbind in ZimbraUtil.
#$rslt = $ldap->unbind;
print "\nfinished at ";
print `date`;















# ######
# sub get_archive_account_id($) {
#     my $a = shift;

#     my $d2 = new XmlDoc;
#     $d2->start('GetAccountRequest', $MAILNS); 
#     $d2->add('account', $MAILNS, { "by" => "name" }, $a);
#     $d2->end();
    
#     my $r2 = $zu->check_context_invoke($d2, \$context);

#     if ($r2->name eq "Fault") {
#         my $rsn = $zu->get_fault_reason($r2);
# 	if ($rsn ne "account.NO_SUCH_ACCOUNT") {
# 	    print "problem searching out archive $a\n";
# 	    print Dumper($r2);
# 	    return;
# 	}
#     }

#     my $mc = $r2->find_child('account');

#     return $mc->attrs->{id}
#         if (defined $mc);
	
#     return undef;
# }





######
sub print_usage() {
    print "\n";
    print "usage: $0 [-n] [-d] [-e] [-h] [-r] -l <ldap host> -b <basedn>\n".
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
    print "\t-r skip deleting archives\n";
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
