#!/usr/bin/perl -w
#

use strict;
use Getopt::Std;
use Data::Dumper;

sub move_and_purge($);
sub print_usage();

my @script_dir = split /\//, $0;
my $script_dir;
my $start = 1;
$start = 0 if ($script_dir[0]);
$script_dir = join '/', @script_dir[$start..$#script_dir-1];
$script_dir = '/' . $script_dir if ($0=~/^\//);


my %opts;
getopts('oec:a:d:n', \%opts);

if (!exists $opts{d} || (!exists $opts{c} && !exists $opts{a})) {
    print "you must specify either -c or -a and -d\n";
    print_usage();
}


if (exists $opts{n}) {
    print "-n used, no changes will be made\n";
}
my $count;

print "-e specified, only even records will be moved\n"
  if (exists $opts{e} && !exists $opts{a});
print "-o specified, only odd records will be moved\n"
  if (exists $opts{o} && !exists $opts{a});

if (exists $opts{c} && ! exists $opts{a}) {
    $count = $opts{c};
    print "working on $count records...\n";
} 

if (exists $opts{e} && exists $opts{o}) {
    print "-e and -o are mutually exclusive\n";
    print_usage();
} elsif ((exists $opts{e} || exists $opts{o}) && exists ($opts{a})) {
    print "-e | -o and -a are mutually exclusive\n";
    print_usage();
}

my $dest = $opts{d};

my $account_to_move;
if (exists $opts{a}) {
    $account_to_move = $opts{a};
    print "\naccount chosen by name: $account_to_move\n";

    move_and_purge($account_to_move);
    exit;
}

my $total_size = 0;

my $in;
open ($in, 'zmprov gqu `zmhostname`|');

while (<$in>) {
    last if ($count<=0);

    my ($account,$size) = (split /\s+/, $_)[0,2];
    my $n = (split /\@/, $account)[0];

    my $length = () = split //, $n, -1;
    my $d = (split //, $n)[$length-2];

    if (($d !~ /^\d+$/) && (exists $opts{o} or exists $opts{e})) {
	print "-e or -o specified and $account does not end in a number, it will be skipped.\n";
	next;
    }

    my $move_user = 0;
	if (
	    (($d =~ /^\d+$/) &&
	     ((exists $opts{o} && ($d % 2) == 1) ||
	      (exists $opts{e} && ($d % 2) == 0))) ||
	     (!exists $opts{o} && !exists $opts{e})) {
	    $move_user = 1;
	}

    if ($move_user) {
	$total_size += $size;
	
	# if ($account =~ /archive$/) {
	# 	my $acct = `ldapsearch -x -w pass -D uid=zimbra,cn=admins,cn=zimbra -LLLb "" -h mldap01.domain.org zimbraarchiveaccount=$account mail|grep mail:|head -1|awk '{print \$2}'`;
	# 	chomp $acct;
	# 	print "\n", $acct, " ", $account, " $size\n";
	# } else {
	print "\n", $account, " $size\n";
	# }
	
	move_and_purge($account);
	
	$count--;
    }
} 



sub move_and_purge($) {
    my $account = shift;

    if (! -f $script_dir . "/find_zimbra_db_files.pl") {
	print "can't find find_zimbra_db_files.pl in $script_dir, please make sure it's in the same directory as $0\n";
	exit;
    }

    my $output_file = "/var/tmp/${account}_files.csv";

    print "dumping file list for ${account} " . `date`;
    if (!exists $opts{n}) {
	die "dumping db file list for $account failed."
	  if (system ($script_dir . "/find_zimbra_db_files.pl -a $account > $output_file") != 0)
    }

    print "dumped ${account}'s file list, now moving " . `date`;
    if (!exists $opts{n}) {
	if (system ("zmmboxmove -a $account --from `zmhostname` --to $dest --sync") != 0) {
	    die "zmmboxmove failed for $account";
	}
    }

    print "files moved, purging mailbox " . `date`;
    if (!exists $opts{n}) {
	if (system ("zmpurgeoldmbox -a $account") != 0) {
	    die "purging $account mailbox failed failed";
	}
    }

    print "checking that files were purged " . `date`;

    if (!exists $opts{n}) {
	my $file_check_in;
	open ($file_check_in, $output_file) || die "unable to open $output_file for reading";
	my $files_exist  = 0;
	while (<$file_check_in>) {
	    my $file = (split /,/)[0];
	    next if ( $file eq "NULL");
	    if ( -f $file ) {
		print "\texists: $file\n";
		$files_exist = 1;
	    }
	}
	die "not all files were purged for $account, exiting" if ($files_exist);
    }
    
}

# print "total_size: $total_size\n";


sub print_usage() {
    print "\n";
    print "usage: $0 -d <destination host> \n";
    print "\t-c <records to move> | -a <specific account to move> [ -o | -e ] [ -n ]\n";
    print "\n";
    print "\t-d <destination host> host to which to move account(s)\n";
    print "\t-c <record count to move | -a <account to move>\n";
    print "\t\teither move an individual account or take a specified\n";
    print "\t\tnumber off the top of zmprov gqu `zmhostname`\n";
    print "\t-o | -e only move records ending in odd or even numbers\n";
    print "\t-n print but do not make changes\n";
    exit 1;
}
