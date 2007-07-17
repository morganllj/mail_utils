#!/usr/local/bin/perl -w
#

# mbox_migrate.pl
# Original:
# http://wiki.zimbra.com/index.php?title=User_Migration#Migrating_from_MBOX_files
# updated by Morgan Jones (morgan@morganjones.org)
# Id: $Id$
# 


use strict;
use Email::Folder;
use MIME::Parser;
use Net::SMTP;
use Mail::IMAPClient;
use Getopt::Std;

sub print_usage();

my $opts;

getopts('nm:u:w:h:', \%$opts);

# my $mbox = $ARGV[0];
# my $email = $ARGV[1];
# my $server = $ARGV[2];
my $mbox = $opts->{m} || print_usage();
my $user = $opts->{u} || print_usage();
my $pass = $opts->{w} || print_usage();
my $host = $opts->{h} || print_usage();

# $server = 'smtp' if(!defined($server));



# die "Usage: $0 mbox dest_address [smtp server]" if(!defined($mbox) || !-f $mbox);
# die "Usage: $0 mbox dest_address [smtp server]" if(!defined($email) || $email !~ m/\@/);

print "opening $mbox\n";

my $folder = Email::Folder->new($mbox) || die "can't open $mbox\n";
#  ||
# 				die "Usage: $0 mbox dest_address [smtp server]
#         Forward all mail found in mail file mbox to address.
#     ");

my $count=0;
my @messages=$folder->messages;
my $total=@messages;

print "connecting to $host as $user/$pass\n";


my $imap = Mail::IMAPClient->new (
    Server => $host,
    User   => $user,
    Password => $pass
) or die "can't connect to imap server $host: $@";



foreach (@messages){
    $count++;
    my $parser = new MIME::Parser;
    $parser->output_under("/tmp");
    $parser->decode_headers(0);
    $parser->ignore_errors(1);
    my $entity = $parser->parse_data($_->as_string);
    my $header = $entity->head;
    my $sender = $entity->head->get('From');
    next if $header->get("subject") =~ m/FOLDER INTERNAL/;
    $entity->head($header);
    $entity->sync_headers;
    #       print "Message $count / $total\n";
#        print "Sending message with subject: " . $entity->head->get("subject");
    print "[$count/$total] subject: " . $entity->head->get("subject");
    
#        print " to $email via $server\n";



    unless ($opts->{n}) {
	$imap->append("INBOX", $entity->as_string()) || 
	    die "problem appending: $@\n";
    }
    
}



sub print_usage() {
    print "\n";
    print "$0 [-n] -m <mbox> -h <imap host> -u <username> -w <password>\n";
    print "\n";
    print "\t-n print what I'm going to do, don't make changes.  Optional.\n";
    print "\t-m <mbox> mbox file, generally /var/mail/user or /var/spool/mail/user\n";
    print "\t-h <imap host> imap server hostname\n";
    print "\t-m <username> username to use to auth to imap\n";
    print "\t-w <password> password to use to auth to imap\n";
    print "\n";

    exit 0;
}
