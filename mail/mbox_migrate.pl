#!/usr/bin/perl -w
## Because of complex dependencies I often build my own version of perl:
#!/home/mjones/perl_for_migration/bin/perl
#
# mbox_migrate.pl
# Original:
# http://wiki.zimbra.com/index.php?title=User_Migration#Migrating_from_MBOX_files
# updated by Morgan Jones (morgan@morganjones.org)
# Id: $Id$
#
# Description: migrate text 'mbox' files into an imap server.  See
# usage: capable of operating in bulk on one or many users.
#
# TODO: any file named 'mbox' is automatically converted to INBOX.
# This should probably be an option on the command line.
#   While the push /usr/local/lib/perl5.. in the BEGIN?
# 
BEGIN {
    push @INC, "/usr/local/lib/perl5/5.8.0";
    push @INC, "/usr/local/lib/perl5/site_perl/5.8.0";
}

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
sub migrate($$$$$);
sub get_imap_dir($$);

my $opts;

getopts('nm:u:w:h:f:p:r:', \%$opts);

my $p = $opts->{w} || print_usage();
my $h = $opts->{h} || print_usage();
my $remote_user = $opts->{r} || undef;


print "starting at ", `date`;

if (!exists $opts->{f}) {
    my $m = $opts->{m} || print_usage();
    my $u = $opts->{u} || print_usage();
    my $pre = $opts->{p};

    migrate($m, $u, $p, $h, $pre);
} else {
    open (IN, $opts->{f}) || die "can't open $opts->{f}";
    while (<IN>) {
        chomp;

        my ($u, $pre, $m) = /\s*([^\s]+)\s+([^\s]+)\s+(.*)/;

        if (defined $u && defined $m) {
            
            print "migrating $m for $u\n";
            migrate($m, $u, $p, $h, $pre);
        } else {
            print "skipping malformed line in $opts->{f}: /$_/\n";
        }
    }
}

print "finished at ", `date`;





sub migrate ($$$$$) {
    my ($mbox, $user, $pass, $host, $prefix) = @_;
    
    my $mbox_path = $prefix . "/". $mbox;

    print "\n\nopening: $mbox_path\n";

    my $folder = Email::Folder->new($mbox_path) || die "can't open $mbox\n";

    if ($mbox eq "mbox") {
        $mbox = "Inbox";
        print "**migrating into 'Inbox'\n";
    }

    my $count=0;

    my @messages;
   
    # 'messages()' has a 'croak' in it that will cause the script to
    # exit prematurely on minor errors like folders that don't exist,
    # etc.
    eval {
        @messages=$folder->messages;
     };
     if ($@) {
         warn $@;
         return;
     }

    my $total=@messages;

    $user = $remote_user
        if (defined $remote_user);

    my $imap;
    unless ($opts->{n}) {
        $imap = Mail::IMAPClient->new (
            Server => $host,
            Port => "143",
            User   => $user,
            Password => $pass
        ) or die "can't connect to imap server $host or problem ".
            "authenticating as $user: $@";
    }

    my %folders;

    foreach (@messages) {

        $count++;
        my $parser = new MIME::Parser;
        # $parser->output_under("/home/morgan/zimbra_migration/tmp");
        $parser->output_to_core(1);
        $parser->decode_headers(0);
        $parser->ignore_errors(1);
        #    print "entry: /",$_->as_string,"/\n";
    
        #    print "*** parse_data", `date`;
        my $entity = $parser->parse_data($_->as_string);
        #    print "*** done parse_data", `date`;



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
        my $rfc2060_date = undef; # it's okay to pass undef to append_string()
        if (defined $date) {
            #$rfc2060_date = $imap->Rfc2060_date($since_epoch);
            $rfc2060_date = Rfc2060_date($date);
        }

        my $imap_path = $mbox;
        $imap_path =~ s/\//\./;

        unless ($opts->{n}) {

            if (!exists($folders{$imap_path})) {
                $imap->create($imap_path);
                $folders{$imap_path} = 1;
            }

            # try to append with date, append without date otherwise,
            # then complain
            unless ($imap->append_string($imap_path, $entity->as_string(), $flags, 
                                         $rfc2060_date)) {
                $imap->append_string($imap_path, $entity->as_string(), $flags) ||
                    warn "MESSAGE SKIPPED: $@\n";
            }
        }
    
    }
}





# sub get_imap_dir($$) {
#     my ($prefix, $in) = @_;

#     my @p_pieces = split /\//, $prefix;
#     my @in_pieces = split /\//, $in;

#     my $c = 0;

#     for (@p_pieces) {
#         if (($p_pieces[$c] == "\%s") || (lc $p_pieces[$c])) {
#             shift @in_pieces;
#             $c++;
#         }
#     }

#     return join '.', @in_pieces;
# }



sub print_usage() {
    print "\n";
    print "$0 [-n] (-m <mbox> -u <username>|-f <user to mbox mapping>)\n".
        "\t-h <imap host> -w <password> -p <mailbox prefix>\n".
        "\t[-r remote username]\n";
    print "\n";
    print "\t-f is mutually exclusive with -m, -h and -u\n";
    print "\t if -f is used, -w must the password for all users in the file\n";
    print "\n";
    print "\t-n print what I'm going to do, don't make changes.  Optional.\n";
    print "\t-m <mbox> mbox file, generally /var/mail/user or /var/spool/mail/user\n";
    print "\t-u <username> username to use to auth to imap\n";
    print "\t-f <user to mbox mapping> \"<user> <mbox path>\" separated by CRs\n";
    print "\t-h <imap host> imap server hostname\n";
    print "\t-w <password> password to use to auth to imap\n";
    print "\t-p <mailbox prefix> prefix to user's mailbox\n".
          "\t   (usually /home/%s for their homedir)\n";
    print "\t-r <remote username> remote user to login to imap with.\n".
          "\t   This will be used for *all* folders\n";
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

    # print "d: /$d/\n";
    $_ = $d;
    # my $tz = (split /\s+/, $d)[-1];
    my ($tz) = /([-+]{1}[0-9]{4})/;

#    print "tz: /$tz/\n";

    if (!defined $tz || $tz !~ /[-+]{1}[0-9]{4}/) {
        $tz = "-0000";
    }

    # dd-Mon-yyyy hh:mm:ss +0000
    return sprintf "%2d-%s-%4d %2d:%2d:%2d %s", 
           $mday, $mnt[$mon], $year, $hour, $min, $sec, $tz;
}
