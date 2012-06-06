#!/usr/bin/perl -w
#
#
# Given a list of email addresses and a string find and delete every instance in those users' mailboxes
#
# delete_email_by_keyword.pl -n  -u morgan,kacless,pichinaga -s "unique subject mon afternoon"

use strict;
use Getopt::Std;

sub print_usage();

if (`whoami` !~ /^root/) {
    print "run as root!\n\n";
    exit;
}

my %opts;

getopts('u:f:s:n', \%opts);

$opts{s} || print_usage();
my $srch_str = $opts{s};

print "-n used, just printing, no changes will be made.\n\n"
    if (exists $opts{n});

my @users;
if ($opts{u}) {
    @users = split /\s*,\s*/, $opts{u}
} elsif ($opts{f}) {
    open (IN, $opts{f}) || die "can't open $opts{f}";

    while (<IN>) {
	chomp;
	push @users, $_;
    }
} else {
    print "no user list..";
    print_usage();
}

print "searching for \"$srch_str\" in mailbox(es) " . join (',', @users), "..\n\n";

for my $u (sort @users) {
    print "\n$u..\n";
    my $rslt = `su - zimbra -c "zmmailbox -z -m $u search -l 1000 -t message \\"$srch_str\\""`;

    for (split /\n/, $rslt) {
	if (/^num:/ && /more: true/) {
	    print "WARNING: this is not a complete result set!\n";
	} elsif (/\d+\.\s*(\d+)/) {
	    my $msg_id=$1;
	    s/mess\s*//;
	    s/\s*\d+\.//;
	    print "$u: $_\n";
	    unless (exists $opts{n}) {
		system "su - zimbra -c \"zmmailbox -z -m $u deletemessage $msg_id\"";
	    }
	}
    }

#    print " result: /$rslt/\n";

}


sub print_usage () {
    print "usage: $0 -u <user1,user2..> | -f <user list file> -s <search string>\n";
    exit;
}



