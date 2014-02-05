#!/usr/bin/perl -w
#
use strict;
use Data::Dumper;
use Getopt::Std;

# if -v /path shows an account that has been moved to another host,
# you need to purge that users file: zmpurgeoldmbox -a account

# if (defined $ARGV[0]) {
#     $account = $ARGV[0];
# } else {
#     print "usage: $0 <account>";
#     exit 1;
# }
my %opts;
getopts('a:v:', \%opts);

my $account;
my $volume;
if (exists $opts{a} && !exists $opts{v}) {
    $account = $opts{a};
} elsif (exists $opts{v} && !exists $opts{a}) {
    $volume = $opts{v};
} else {
    print "usage: $0 -a account | -v volume\n";
    print "\t-a and -v are mutually exclusive.\n";
    exit 1;
}


my %vols;
for (split /\n/, `echo "select id,path from volume;" | mysql zimbra`) {
    my ($id,$path) = split /\s+/;
    next if ($id eq "id");
    $vols{$id} = $path;
}


if (defined $account) {
    my $mailboxId = `zmprov getMailboxInfo $account|grep mailboxId|awk '{print \$2}'`;
    if (!defined $mailboxId) {
	die "no such account $account?\n";
    }
    my $mboxgroup = $mailboxId % 100;

    # zmprov getMailboxInfo returns a number regardless of the user's store.  Make sure the user is on this store:
    my $verify_store = `echo "select id,comment from mailbox where id=$mailboxId" | mysql zimbra`;
    my @verify_store = split /\n/, $verify_store;

    if ($#verify_store > 1) {
	print "too many values were returned for id=$mailboxId from zimbra.mailbox database:\n";
	print $verify_store . "\n";
	exit 1;
    } elsif ($#verify_store == 1) {
	my $verify_account = (split /\s+/, $verify_store[1])[1];
	#    print "comparing /$account/ and /$verify_account/\n";
	if ($account ne $verify_account) {
	    die "$account doesn't appear to be on this host\n";
	}
    }

    for (split /\n/,
	 `echo "select id,mailbox_id,volume_id,mod_content,subject from mail_item where mailbox_id=$mailboxId and type!=1;" | mysql mboxgroup$mboxgroup`) {



	my ($id, $mailbox_id, $volume_id, $mod_content, $subject) = split /\s+/,$_,5;
	next if ($id eq "id");

	my $path;
	if ($volume_id ne "NULL") {
	    my $num1 = $mailbox_id >> 12;
	    my $num2 = $id >> 12;

	    $path = $vols{$volume_id} . "/" . $num1 . "/" . $mailbox_id . "/msg/" . $num2 . "/" . $id . "-" . $mod_content . ".msg";
	    print "$path,";
	} else {
	    print "NULL,";
	}



	print "$id,$mailbox_id,$volume_id,$mod_content,";

	if (defined $path && -f $path) {
	    print "Y,";
	} else {
	    print "N,";
	}

	print "$subject\n";
    }

} else {

    my $volume_id;
    for my $path_id (keys %vols) {
	if ($volume eq $vols{$path_id}) {
	    $volume_id = $path_id;
	}
    }
    if (!defined $volume_id) {
	print "can't find volume $volume within available volumes: \n", Dumper %vols;
	exit 1;
    }

    my %user2path;
    my %id2email;

    for (my $i=1; $i<=100; $i++) {
	for (split /\n/, 
#	     `echo "select id,mailbox_id,mod_content,subject from mail_item where volume_id=$volume_id" | mysql mboxgroup$i`) {
	     `echo "select id,mailbox_id,volume_id,mod_content,subject from mail_item where volume_id=$volume_id" | mysql mboxgroup$i`) {

	    my ($id, $mailbox_id, $volume_id, $mod_content, $subject) = split /\s+/,$_,5;
	    next if ($id eq "id");

	    my $path;
	    if ($volume_id ne "NULL") {
		my $num1 = $mailbox_id >> 12;
		my $num2 = $id >> 12;

		$path = $vols{$volume_id} . "/" . $num1 . "/" . $mailbox_id . "/msg/" . $num2 . "/" . $id . "-" . $mod_content . ".msg";

	    }

	    if (exists $id2email{$mailbox_id}) {
		my $associated_user = $id2email{$mailbox_id};
		push @{$user2path{$associated_user}}, $path;
		print "$associated_user $path\n";
	    } else {
		my $find_username = `echo "select id,comment from mailbox where id=$mailbox_id" | mysql zimbra`;
		my @find_username = split /\n/, $find_username;


		if ($#find_username > 1) {
		    print "too many values were returned for id=$mailbox_id from zimbra.mailbox database:\n";
		    print $find_username . "\n";
		} elsif ($#find_username == 1) {
		    my $associated_user = (split /\s+/, $find_username[1])[1];
		    print "$associated_user $path\n";
		    push @{$user2path{$associated_user}}, $path;
		    $id2email{$mailbox_id} = $associated_user;
		} else {
		    print "no user is associated with $path. This shouldn't happen?\n";
		    exit 1;
		}
	    }
	}
    }

    print "\n";

    for my $user (sort keys %user2path) {
	print "$user\n";
    }
    

    
    
}

