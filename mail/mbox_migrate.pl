#!/usr/local/bin/perl -w
#
# mbox_migrate.pl
# Original:
# http://wiki.zimbra.com/index.php?title=User_Migration#Migrating_from_MBOX_files
# updated by Morgan Jones (morgan@morganjones.org)
#
# Id: $Id$
# 
use strict;
use Email::Folder;
use MIME::Parser;
use Net::SMTP;
use Mail::IMAPClient;
use Getopt::Std;
# use Time::Local;
use HTTP::Date;

sub print_usage();
sub Rfc2060_date($);

my $opts;

getopts('nm:u:w:h:', \%$opts);

my $mbox = $opts->{m} || print_usage();
my $user = $opts->{u} || print_usage();
my $pass = $opts->{w} || print_usage();
my $host = $opts->{h} || print_usage();

print "\n\nopening $mbox\n";

my $folder = Email::Folder->new($mbox) || die "can't open $mbox\n";

my $count=0;
my @messages=$folder->messages;
my $total=@messages;

print "connecting to $host as $user/$pass\n";

my $imap;
unless ($opts->{n}) {
    $imap = Mail::IMAPClient->new (
        Server => $host,
        User   => $user,
        Password => $pass
    ) or die "can't connect to imap server $host: $@";
}

foreach (@messages){
    $count++;
    my $parser = new MIME::Parser;
    $parser->output_under("/tmp");
    $parser->decode_headers(0);
    $parser->ignore_errors(1);
#    print "entry: /",$_->as_string,"/\n";
    my $entity = $parser->parse_data($_->as_string);
    my $header = $entity->head;
    my $sender = $entity->head->get('From');

    # Wed, 02 Jul 2003 14:12:58 +0700
    my $date   = $entity->head->get('Date');

    my $status = $entity->head->get("status");
    my $subject = $entity->head->get("subject");
    $subject = '' if !defined $subject;
    chomp $subject;
    next if $subject =~ m/FOLDER INTERNAL/;
    $entity->head($header);
    $entity->sync_headers;

    if (!defined $status) { 
	$status = '-'; 
    } else {
	chomp $status;
    }

    unless ($status =~ /^[RUODN-]+$/) {
        print "WARNING: unexpected status ($status) for " . 
            #$entity->head->get("subject") . "\n";
            "$subject\n";
    }

    print "[$user][$count/$total][$status] " . $subject . "\n";

    my $flags = "\\Seen" if $status =~ /^[RO]+$/;
    my $rfc2060_date = undef;  # it's okay to pass undef to append_string()
    if (defined $date) {
        #$rfc2060_date = $imap->Rfc2060_date($since_epoch);
        $rfc2060_date = Rfc2060_date($date);
    }
#    print "rfc2060 date: /$rfc2060_date/\n";

    unless ($opts->{n}) {
       # try to append with date, append without date otherwise, then complain
       unless ($imap->append_string("INBOX", $entity->as_string(), $flags, 
                $rfc2060_date)) {
           print "in unless\n";
           $imap->append_string("INBOX", $entity->as_string(), $flags) ||
	    warn "MESSAGE SKIPPED: $@\n";
       }
    }
    
}



sub print_usage() {
    print "\n";
    print "$0 [-n] -m <mbox> -h <imap host> -u <username> -w <password>\n";
    print "\n";
    print "\t-n print what I'm going to do, don't make changes.  Optional.\n";
    print "\t-m <mbox> mbox file, generally /var/mail/user or /var/spool/mail/user\n";
    print "\t-h <imap host> imap server hostname\n";
    print "\t-u <username> username to use to auth to imap\n";
    print "\t-w <password> password to use to auth to imap\n";
    print "\n";

    exit 0;
}


sub Rfc2060_date($) {
    my $d = shift;

    my @mnt  =      qw{ Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec};

    my $since_epoch = str2time($d);

    return undef if (!defined $since_epoch);

    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) =
         localtime($since_epoch);
    $year += 1900;

    my $tz = (split /\s+/, $d)[-1];

    if ($tz !~ /[-+]{1}[0-9]{4}/) {
        $tz = "-0000";
    }

    # dd-Mon-yyyy hh:mm:ss +0000
    return sprintf "%2d-%s-%4d %2d:%2d:%2d %s", 
           $mday, $mnt[$mon-1], $year, $hour, $min, $sec, $tz;
}
