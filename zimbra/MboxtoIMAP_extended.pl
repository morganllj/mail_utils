#!/usr/bin/perl -w

use Socket;
use FileHandle;
use Fcntl;
use Getopt::Std;


######################################################################
#  Original    Program name  MboxtoIMAP.pl                           #
#  Originially Written by Rick Sanders                               #
#  Date           15 April 2003                                      #
#                                                                    #
#  Updated May, 2007
#  By: Morgan Jones (morgan@morganjones.org)
#  Id: $Id$
#                                                                    #
#  Description                                                       #
#                                                                    #
#  MboxtoIMAP.pl is used to copy the contents of Unix                #
#  mailfiles to IMAP mailboxes.  It parses the mailfiles             #
#  into separate messages which are inserted into the                #
#  corresponging IMAP mailbox.                                       #
#                                                                    #
#  See the Usage() for available options.                            #
#                                                                    #
######################################################################

&init();  # gather & validate command line parameters.
#init();  # gather & validate command line parameters.

&connectToHost($imapHost, 'IMAP');
&login($imapUser,$imapPwd, 'IMAP');    



my $user;
my $type;
my $opts;
my $added;


# Four scenarios:
#    one user, one mailbox, transfer into that user's imap mailbox
#    one user, multiple mail files, transfer multiple mailboxes
#    one user (as proxy), transfer 1 mailbox per user
#    one user (as proxy), transfer multiple mailboxes per user
    


# one user, one mail file.  Use the name of the file to identify the
# name of the mailbox to transfer into

if (-f $mfdir) {

    my @pi = split (/\//, $mfdir);

    

    my $p = $pi[0..$#pi-1];
    my $f = $pi[$#pi];

    mailfile_into_imap($p, $f);
}

# one user, multiple mail files, all mail goes into that user's inbox
if (-d $mfdir) {
@mailfiles = &getMailfiles($mfdir);

$msgs=$errors=0;
foreach $mailfile ( @mailfiles ) {
    @terms = split(/\//, $mailfile);
    $mbx = $terms[$#terms];
    $mbxs++;
    print STDOUT "Copying mbx $mbx\n";
    
    mailfile_into_imap($mfdir, $mailfile);
}
die "$mfdir is neither a file or a directory";
}


&logout( 'IMAP' );

Log("\n\nSummary:\n");
Log("   Mailboxes  $mbxs");
Log("   Total Msgs $added");


exit;


sub mailfile_into_imap {
    my ($path, $file) = @_;

    #@msgs = &readMbox( "$mfdir/$mailfile" );
    @msgs = &readMbox( "$path/$file" );
    foreach $msg ( @msgs ) {
	
	@msgid = grep( /^Message-ID:/i, @$msg );
	($label,$msgid) = split(/:/, $msgid[0]);
	chomp $msgid;
	&trim( *msgid );
	
	my $message;
	foreach $_ ( @$msg ) { $message .= $_; }
	if ( &insertMsg($mbx, \$message, $flags, $date, 'IMAP') ) {
	    $added++;
	    print STDOUT "   Added $msgid\n" if $debug;
	}
    }
}


sub init {

    #usage() if (!getopts('m:L:i:d'));
    usage() if (!getopts('m:L:i:d', \%$opts));

   $mfdir    = $opts->{m}  || usage();
   $logfile  = $opts->{L};
   $debug = 1 if $opts->{d};
   ($imapHost,$imapUser,$imapPwd) = split(/\//, $opts->{i}); #|| usage();

   if ( $logfile ) {
      if ( ! open (LOG, ">> $logfile") ) {
        print "Can't open logfile $logfile: $!\n";
        $logfile = '';
      }
   }
   Log("Starting");

}


sub getMailfiles {

   my $dir = shift;
   my @mailfiles;

   opendir D, $dir;
   @filelist = readdir( D );
   closedir D;

   foreach $fn ( @filelist ) {
      next if $fn =~ /\.|\.\./;
      push( @mailfiles, $fn );
   }

   Log("No mailfiles were found in $dir") if $#mailfiles == -1;

   @mailfiles = sort { lc($a) cmp lc($b) } @mailfiles;

   return @mailfiles;
}



sub usage {
    
    print "\n";
    print "Usage: $0 -m <path> \n\t\t-i <server/username/password> [-L <logfile>] [-d]\n";
    print "\n";
    print "-m <path> path may be a directory or file.\n";
    print "\tIf it's a file and the same as the user name the mail\n".
	"\twill be imported into INBOX on the IMAP server.\n";
    print "\n";

   exit 0;
}

sub readMbox {

my $file  = shift;
my @mail  = ();
my $mail  = [];
my $blank = 1;
local *FH;
local $_;

    open(FH,"< $file") or die "Can't open $file";

    while(<FH>) {
        if($blank && /\AFrom .*\d{4}/) {
            push(@mail, $mail) if scalar(@{$mail});
            $mail = [ $_ ];
            $blank = 0;
        }
        else {
            $blank = m#\A\Z#o ? 1 : 0;
            push(@{$mail}, $_);
        }
    }

    push(@mail, $mail) if scalar(@{$mail});
    close(FH);

    return wantarray ? @mail : \@mail;
}

sub Log {

my $line = shift;
my $msg;

   my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime (time);
   $msg = sprintf ("%.2d-%.2d-%.4d.%.2d:%.2d:%.2d %s",
                  $mon + 1, $mday, $year + 1900, $hour, $min, $sec, $line);

   if ( $logfile ) {
      print LOG "$msg\n";
   } else {
      print "$line\n";
   }

}

#  connectToHost
#
#  Make an IMAP4 connection to a host
# 
sub connectToHost {

my $host = shift;
my $conn = shift;

   &Log("Connecting to $host") if $debug;

   $sockaddr = 'S n a4 x8';
   my ($name, $aliases, $proto) = getprotobyname('tcp');
   $port = 7143;

   if ($host eq "") {
	&Log ("no remote host defined");
	close LOG; 
	exit (1);
   }

   my $type;
   my $len;
   ($name, $aliases, $type, $len, $serverAddr) = gethostbyname ($host);
   if (!$serverAddr) {
	&Log ("$host: unknown host");
	close LOG; 
	exit (1);
   }

   #  Connect to the IMAP4 server
   #

   $server = pack ($sockaddr, &AF_INET, $port, $serverAddr);
   if (! socket($conn, &PF_INET, &SOCK_STREAM, $proto) ) {
	&Log ("socket: $!");    
	close LOG;
	exit (1);
   }

   if ( ! connect( $conn, $server ) ) {
	&Log ("connect: $!");
	#return 0;
	exit (1);
   }


#   select( $conn ); $| = 1;

   while (1) {
	&readResponse ( $conn );
	if ( $response =~ /^\* OK/i ) {
	   last;
	}
	else {
 	   &Log ("Can't connect to host on port $port: $response");
	   return 0;
	}
   }
   &Log ("connected to $host") if $debug;

#   select( $conn ); $| = 1;
   return 1;
}

#
#  login in at the source host with the user's name and password
#
sub login {

$user = shift;
my $pwd  = shift;
my $conn = shift;

   &Log("Logging in as $user") if $debug;
   $rsn = 1;

   &sendCommand ($conn, "$rsn LOGIN $user $pwd");

   while (1) {
       print "top of while\n";
	&readResponse ( $conn );
	if ($response =~ /^$rsn OK/i) {
		last;
	}
	elsif ($response =~ /NO/) {
		&Log ("unexpected LOGIN response: $response");
		return 0;
	}
   }
   &Log("Logged in as $user") if $debug;

   return 1;
}


#  logout
#
#  log out from the host
#
sub logout {

my $conn = shift;

   ++$lsn;
   undef @response;
   &sendCommand ($conn, "$lsn LOGOUT");
   while ( 1 ) {
	&readResponse ($conn);
	print "response: $response\n";
	if ( $response =~ /^$lsn OK/i ) {
		last;
	}
	elsif ( $response !~ /^\*/ ) {
		&Log ("unexpected LOGOUT response: $response");
		last;
	}
   }
   close $conn;
   return;
}

#  readResponse
#
#  This subroutine reads and formats an IMAP protocol response from an
#  IMAP server on a specified connection.
#

sub readResponse
{
    local($fd) = shift @_;

    $response = <$fd>;
    chop $response;
    $response =~ s/\r//g;
    push (@response,$response);
    if ($debug) { &Log ("<< $response",2); }
}

#
#  sendCommand
#
#  This subroutine formats and sends an IMAP protocol command to an
#  IMAP server on a specified connection.
#

sub sendCommand
{
    local($fd) = shift @_;
    local($cmd) = shift @_;

    print $fd "$cmd\r\n";

    #if ($showIMAP) { &Log (">> $cmd",2); }
    &Log (">> $cmd",2) if $debug;
}

sub insertMsg {

my $mbx = shift;
my $message = shift;
my $flags = shift;
my $date  = shift;
my $conn  = shift;
my ($lsn,$lenx);

   &Log("   Inserting message") if $debug;
   $lenx = length($$message);

   if ( $debug ) {
      &Log("$$message");
   }

   #  Create the mailbox unless we have already done so
   ++$lsn;
   if ($destMbxs{"$mbx"} eq '') {
	&sendCommand (IMAP, "$lsn CREATE \"$mbx\"");
	while ( 1 ) {
	   &readResponse (IMAP);
	   if ( $response =~ /^$rsn OK/i ) {
		last;
	   }
	   elsif ( $response !~ /^\*/ ) {
		if (!($response =~ /already exists|reserved mailbox name/i)) {
			&Log ("WARNING: $response");
		}
		last;
	   }
       }
   } 
   $destMbxs{"$mbx"} = '1';

   ++$lsn;
   $flags =~ s/\\Recent//i;

   # &sendCommand (IMAP, "$lsn APPEND \"$mbx\" ($flags) \"$date\" \{$lenx\}");
   &sendCommand (IMAP, "$lsn APPEND \"$mbx\" \{$lenx\}");
   &readResponse (IMAP);
   if ( $response !~ /^\+/ ) {
       &Log ("unexpected APPEND response: $response");
       # next;
       push(@errors,"Error appending message to $mbx for $user");
       return 0;
   }

   if ( $opts->{x}) {
      print IMAP "$$message\n";
   } else {
      print IMAP "$$message\r\n";
   }

   undef @response;
   while ( 1 ) {
       &readResponse (IMAP);
       if ( $response =~ /^$lsn OK/i ) {
	   last;
       }
       elsif ( $response !~ /^\*/ ) {
	   &Log ("unexpected APPEND response: $response");
	   # next;
	   return 0;
       }
   }

   return 1;
}

#  getMsgList
#
#  Get a list of the user's messages in the indicated mailbox on
#  the IMAP host
#
sub getMsgList {

    my $mailbox = shift;
    my $msgs    = shift;
    my $conn    = shift;
    my $seen;
    my $empty;
    my $msgnum;
    
   &Log("Getting list of msgs in $mailbox") if $debug;
#   &trim( *mailbox );
   trim ($mailbox);
   &sendCommand ($conn, "$rsn EXAMINE \"$mailbox\"");
   undef @response;
   $empty=0;
   while ( 1 ) {
	&readResponse ( $conn );
	if ( $response =~ / 0 EXISTS/i ) { $empty=1; }
	if ( $response =~ /^$rsn OK/i ) {
		# print STDERR "response $response\n";
		last;
	}
	elsif ( $response !~ /^\*/ ) {
		&Log ("unexpected response: $response");
		# print STDERR "Error: $response\n";
		return 0;
	}
   }

   &sendCommand ( $conn, "$rsn FETCH 1:* (uid flags internaldate body[header.fields (Message-Id)])");
   undef @response;
   while ( 1 ) {
	&readResponse ( $conn );
	if ( $response =~ /^$rsn OK/i ) {
		# print STDERR "response $response\n";
		last;
	}
#	elsif ( $XDXDXD ) {
	else {
		&Log ("unexpected response: $response");
		&Log ("Unable to get list of messages in this mailbox");
		push(@errors,"Error getting list of ${user}'s msgs");
		return 0;
	}
   }

   #  Get a list of the msgs in the mailbox
   #
   undef @msgs;
   undef $flags;
   for $i (0 .. $#response) {
	$seen=0;
	$_ = $response[$i];

	last if /OK FETCH complete/;

	if ( $response[$i] =~ /FETCH \(UID / ) {
	   $response[$i] =~ /\* ([^FETCH \(UID]*)/;
	   $msgnum = $1;
	}

	if ($response[$i] =~ /FLAGS/) {
	    #  Get the list of flags
	    $response[$i] =~ /FLAGS \(([^\)]*)/;
	    $flags = $1;
   	    $flags =~ s/\\Recent//i;
	}
        if ( $response[$i] =~ /INTERNALDATE ([^\)]*)/ ) {
	    ### $response[$i] =~ /INTERNALDATE (.+) ([^BODY]*)/i; 
	    $response[$i] =~ /INTERNALDATE (.+) BODY/i; 
            $date = $1;
            $date =~ s/"//g;
	}
	if ( $response[$i] =~ /^Message-Id:/i ) {
	    ($label,$msgid) = split(/: /, $response[$i]);
	    push (@$msgs,$msgid);
	}
   }
}

#  trim
#
#  remove leading and trailing spaces from a string
sub trim {

#local (*string) = @_;
    my $string = shift;

   $string =~ s/^\s+//;
   $string =~ s/\s+$//;

   return;
}


