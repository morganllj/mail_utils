#!/usr/bin/perl -w
#
#
# for use deleting messages in mailboxes:
# ~morgan/maillog_grep.pl camcfadden  maillog|grep to=|cut -d '<' -f2 | cut -d '>' -f1|grep -v zgate |grep domain.org|sort -u | tee  /var/tmp/please_review.txt
# ~morgan/maillog_grep.pl camcfadden  /var/mail_log/maillog|grep to=|cut -d '<' -f2 | cut -d '>' -f1|grep -v zgate |grep domain.org|grep -v archive | sort -u | tee  /var/tmp/please_review.txt

use strict;
use Getopt::Std;
use Data::Dumper;

sub print_usage();

$,=$\="\n";

my $argv_neg2 = $ARGV[-2];
my $argv_neg1 = $ARGV[-1];
my $argv_count = $#ARGV;

my $found=0;

my $in;

my $value;

my %opts;
getopt('is', \%opts);

if ($argv_count > 0 && ($argv_neg2 !~ /^\-/ || exists $opts{s})) {
    open ($in, $argv_neg1) || die "can't open $argv_neg1";
    $value = $argv_neg2 if ($argv_neg2 !~ /^\-/);
} else {
    $in = "STDIN";
    $value = $argv_neg1;
}


my %conns;
my %conns_summary;
my %matching_conns;
my $conn_from;
my $search;
my $saved_conn;

while (<$in>) {
    chomp;

    my $conn;
#    next unless (($conn) = /conn=(\d+)\s+/);
#    next unless (($conn) = /postfix\/[^\]]+\]: ([^:]+):/);

    next if (/Sender address triggers FILTER smtp-amavis/);

# Dec  2 06:30:57 mta05 postfix/smtp[28017]: D032012005D: to=<nmurta@domain.org>, relay=127.0.0.1[127.0.0.1]:10026, delay=0.31, delays=0.02/0/0/0.29, dsn=2.0.0, status=sent (250 2.0.0 from MTA(smtp:[127.0.0.1]:10030): 250 2.0.0 Ok: queued as 1293412044E)
# Dec  2 06:30:57 mta05 postfix/qmgr[18075]: 6FFDF12005D: from=<v-loebil_bgedmglacb_cgfdlgfn_cgfdlgfn_a@bounce.mkt3534.com>, size=27990, nrcpt=1 (queue active)
    next unless (($conn) = /postfix\/[^\]]+\]: ([^:]+):/);

    push @{$conns{$conn}}, $_;

    if (!defined $value) {
	# if no value was passed from the command line all connections match
	$matching_conns{$conn} = 1;
    } elsif (exists $opts{i}) {
	# case insensitive
	$matching_conns{$conn} = 1
	  if (/$value/i);
    } else {
	# case sensitive
	$matching_conns{$conn} = 1
	  if (/$value/);
    }

    if (exists $matching_conns{$conn}) {
	# if (exists $opts{s}) {
	#     for (@{$conns{$conn}}) {
	# 	if (/connection from (\d+\.\d+\.\d+\.\d+) /) {
	# 	    push @{$conns_summary{$conn}}, $1
	# 	}

	# 	if ((/(SRCH) base="[^"]*" scope=\d+ filter="([^"]+)"/) ||
	# 	    (/(MOD) dn="([^"]+)"/) ||
	# 	    (/(BIND) dn="([^"]+)"/)) {
	# 	    if (!exists $conns_summary{$conn}) {
	# 		push @{$conns_summary{$conn}}, "no_connection_info";
	# 	    }
	# 	    push @{$conns_summary{$conn}}, $1 . $2
	# 	}

	#     }
	# } 
	# if (!exists $opts{s} || (exists $opts{s} && defined $value)) {
	#     # the idea is we don't want to print if we're generating a summary of all log entries
	    print @{$conns{$conn}};
	# }

	delete $conns{$conn}
    }
}




# if (exists $opts{s}) {
#     print "\n***Summary:\n";
#     $,="";

#     my %summary;
    
#     for my $c (keys %conns_summary) {
# 	my $ip = shift @{$conns_summary{$c}};
# 	push @{$summary{$ip}}, @{$conns_summary{$c}}
#     }

#     for my $ip (keys %summary) {
# 	my %unique_summary_values;
# 	for my $summary_value (@{$summary{$ip}}) {
# 	    $unique_summary_values{$summary_value} = 1;
# 	}
# 	@{$summary{$ip}} = sort keys %unique_summary_values;
#     }

#     for my $ip (keys %summary) {
# 	if (defined $summary{$ip}) {
# 	    print $ip, " ", join (' ', @{$summary{$ip}});
# 	} else {
# 	    print $ip . "\n";
# 	}
#     }

# }







sub print_usage() {
    print "\nusage: $0 [-i] PATTERN [file]\n";
    print "or: $0 -s\n";
    print "\n";
    exit;
}

