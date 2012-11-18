#!/usr/bin/perl -w
# $Id$
#
# Morgan Jones (morgan@morganjones.org)
# 7/18/11
#
# Populate a second server or server environment configured with the
# same domain as the primary server or server environment.

use strict;
use Getopt::Std;
use Data::Dumper;

sub populate_hashes_from_ldap;
sub build_dist_list_str;

$| = 1;

my %opts;

getopts('n', \%opts);

my %primary =   (host=>"production host",
                 pass=>"pass");
my %secondary = (host=>"dev host",
                 pass=>"pass");

my $basedn = "ou=people,dc=domain,dc=org";
my $domain = "domain.org";

my (%p_users, %s_users, %p_lists, %s_lists);

my $srch_base = "ldapsearch -x -w 00pass00 -h 00host00 -D uid=zimbra,cn=admins,cn=zimbra -Lb " . $basedn;
my $srch = $srch_base. " objectclass=* uid objectclass zimbramailforwardingaddress mail";

my $whoami=`whoami`;
chomp $whoami;

if ($whoami ne "zimbra") {
    print "run as zimbra!\n\n";
    exit;
}

my $p = $srch;
$p =~ s/00host00/$primary{host}/;
print "$p\n";
$p =~ s/00pass00/$primary{pass}/;

my ($pl, $pu) = populate_hashes_from_ldap($p);
%p_lists = %$pl;
%p_users = %$pu;

my $s = $srch;
$s =~ s/00host00/$secondary{host}/;
print "$s\n";
$s =~ s/00pass00/$secondary{pass}/;

my ($sl, $su) = populate_hashes_from_ldap($s);
%s_lists = %$sl;
%s_users = %$su;

open ZM, "|zmprov" || die "problem opening pipe to zmprov.."
    unless (exists $opts{n});


## delete users
for my $a (sort keys %s_users) {
    next 
        unless !exists $p_users{$a};
    my $cmd = "da $a\@". $domain;
    print $cmd . "\n";
    print ZM $cmd . "\n"
        unless (exists $opts{n});
            
}

## add/modify users
for my $a (sort keys %p_users) {
    if (!exists $s_users{$a}) {
	 my $cmd = "ca $a\@". $domain ." \"\" zimbramailtransport smtp:smtp." . $domain . ":25";

	 print $cmd . "\n";
	 print ZM $cmd . "\n"
	     unless (exists $opts{n});

	 for my $alias (@{$p_users{$a}}) {
	     create_alias($a, $alias);
	 }
    } else {
	my $p_addr_str = join (' ', sort @{$p_users{$a}});
	my $s_addr_str = join (' ', sort @{$s_users{$a}});

	my %aliases_to_add;
	if ($p_addr_str ne $s_addr_str) {
	    for my $p_alias (@{$p_users{$a}}) {
		$aliases_to_add{$p_alias} = 1;
	    }
	    for my $s_alias (@{$s_users{$a}}) {
		delete $aliases_to_add{$a};
	    }
	}

	for my $alias_to_add (keys %aliases_to_add) {
	    create_alias ($a, $alias_to_add);
	}
    }
}


# TODO: delete individual aliases



## add/modify dist lists
for my $a (sort keys %p_lists) {
#    my $add_mod_str = $a. "\@" . $domain. " zimbraMailForwardingAddress ". 
#      join (' zimbraMailForwardingAddress ', sort @{$p_lists{$a}});

    my $p_str = build_dist_list_str("zimbraMailForwardingAddress", @{$p_lists{$a}});
    next      # don't create empty lists.
        if ($p_str =~ /^\s*$/);

    my $add_mod_str = $a. "\@" . $domain . " zimbraMailForwardingAddress ". 
      $p_str;
    $add_mod_str .= " zimbraHideInGal TRUE zimbraMailStatus disabled"
        if ($a =~ /^all-/);

    my $cmd;
    if (exists ($s_lists{$a})) {
	my $s_str = build_dist_list_str("zimbraMailForwardingAddress", @{$s_lists{$a}});

#	print "comparing $p_str and $s_str\n";
	if ($p_str ne $s_str) {
	    $cmd = "mdl ". $add_mod_str;
	}
    } else {
	$cmd = "cdl ". $add_mod_str;
    }
    if (defined ($cmd)) {
	print $cmd, "\n";
	print ZM $cmd, "\n"
	    unless (exists $opts{n});
    }


    my $p_dist_alias_str = build_dist_list_str("mail", @{$p_lists{$a}});
    my $s_dist_alias_str = build_dist_list_str("mail", @{$s_lists{$a}});

    # dist list aliases
#    print "comparing $p_dist_alias_str and $s_dist_alias_str\n";
    if ($p_dist_alias_str ne $s_dist_alias_str) {
	for my $p_alias (@{$p_lists{$a}}) {
	    my $found = 0;
	    next if ($p_alias =~ /zimbraMailForwardingAddress/i);
	    for my $s_alias (@{$s_lists{$a}}) {
		next if ($s_alias eq $a . "\@" . $domain);
		$found = 1 if ($p_alias eq $s_alias);
	    }
	    # addDistributionListAlias(adla) {list@domain|id} {alias@domain}
	    
	    $p_alias =~ s/mail:\s*//;
	    my $adla_cmd = "adla ". $a . "\@" . $domain . " " . $p_alias;
	    if (!$found) {
		print $adla_cmd, "\n";
		print ZM $adla_cmd, "\n"
		    unless (exists $opts{n});
	    }
	}
    }
    # TODO: remove dist list aliases
}

## delete dist lists
for my $a (sort keys %s_lists) {
    if (!exists ($p_lists{$a})) {
	my $cmd = "ddl $a\@" . $domain;
	print $cmd . "\n";
	print ZM $cmd . "\n"
	  unless (exists $opts{n});
    }    
}

close (ZM);




####
####
# Subroutines

sub create_alias {
    my ($a, $alias) = @_;

    return if (lc $a . "\@" . $domain eq $alias);

    my $cmd = "aaa $a\@" . $domain . "$alias";
    print $cmd . "\n";
    print ZM $cmd . "\n"
        unless (exists $opts{n});
}


sub populate_hashes_from_ldap {
    my $srch = shift;

    $/="";
    my (%lists, %users);

    for (`$srch`) {
	next if (/zimbraAlias/i);
	next unless (/uid:\s([^\n]+)\n/);
	my $u = $1;
	s/\n\s+//g;
	$_ .= "\n";

	if (/zimbraDistributionList/i) {
	    # dist list
	    my @elements;
#	    while (s/zimbraMailForwardingAddress:\s*([^\n]+)\n//) {
	    # TODO: hideingal & zimbramailstatus
	    while (s/(zimbraMailForwardingAddress:\s*[^\n]+)\n//i ||
		   s/(mail:\s*[^\n]+)\n//i) {
		push @elements, $1;
	    }
	    @{$lists{lc $u}} = @elements;
	} else {
	    my @aliases;
	    while (s/mail:\s*([^\n]+)\n//) {
		push @aliases, $1;
	    }
	    @{$users{lc $u}} = @aliases;
	}
    }

    return (\%lists, \%users);
}


sub build_dist_list_str {
    my ($str, @l) = @_;

    my @rl;
    for (sort @l) {
	if (/$str:\s*(.*)/i) {
	    push @rl, $1;
	}
    }
    
    return join " $str ", @rl;
}
