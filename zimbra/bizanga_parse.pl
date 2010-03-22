#!/usr/bin/perl -w
#
# Morgan Jones (morgan@01.com)
# Corey Chandler (corey.chandler@01.com)
# Artur Jasowicz (artur@01.com)
#
# 2/19/10
# morgan@01.com / corey.chandler@01.com
# original code draft
#
# 3/1/10
# artur@01.com
# rewrote code to use SQLite
#
# 3/14/10
# artur@01.com
# rewrote code to use multiple log files
#
# 3/17/10
# artur@01.com
# logs are now located at
# /opt/zimbra/log/date/hostname/mail.log
# e.g.
# /opt/zimbra/log/2010.03.16/dsmdc-mail-bxga2/mail.log

# Parse Bizanga logs for mail deferrals and/or rejections, categorize
# them by domain.  Notify on a threshhold (x deferrals in y minutes to z
# domain) and gathers statistics over time (including data not worthy of
# notification (x/2 deferrals in y minutes to z domain) so trends can be
# seen over time.

# - Take arguments number of deferrals/refusals (x), timeperiod in (y
#   minutes/hours), (optional) domain z, warn and critical thresholds,
#   probably in terms of 'x.'
# - parse smtpout.xxx and one other log (where is the destination domain
#   of a given message stored?).  Connections are logged by id and that
#   id can be correlated across log files.
# - Show warn or critical if in the last y minutes/hours x number of
#   deferrals/referrals have been recorded for any domain (if no domain
#   is passed) or a specific domain (if a domain is passed)
# - A warn/crit would clear when y minutes/hours 

use strict;
use DBI;
use DBD::SQLite;
use Getopt::Std;

my $File;
my @files;
my $Logfile = '';
my $critical = 1000;
my $warn = 5;
my $timeS = 0;
my $timeE = 0;
my $timeD = 60;
my $domain = '';
my $show_help = 0;
my $query;
my $qh;
my $tstamp;
my $ll;
my $returnVal = 0;
my %mon2num = qw( Jan 01  Feb 02  Mar 03  Apr 04  May 05  Jun 06 Jul 07  Aug 08  Sep 09  Oct 10 Nov 11 Dec 12 );

our %options = ();
getopts("hl:c:w:t:d:",\%options);

$show_help++                if defined $options{h};
$Logfile = $options{l}   if defined $options{l};
$critical = $options{c}     if defined $options{c};
$warn = $options{w}         if defined $options{w};
$timeD = $options{t}        if defined $options{t}; # how many minutes back to go
$domain = "and msg_to like \'\%$options{d}\%\'"       if defined $options{d};

sub printHelpMsg {
    print "-l f - use file f as log file, required\n";
    print "-c n - critical threshold\n";
    print "-w n - warning threshold\n";
    print "-t n - how many minutes back in the log do we go? defaults to 60\n";
    print "-d domain.com - domain name\n";
    print "-h - this help\n";
}

if ( $Logfile eq '' ) {
    print "\nOption -l is required!\n\n";
    $show_help++;
}

if ($show_help) {
    printHelpMsg();
    exit;
}

    
$timeE = `date "+%s"`;
# for testing Mar 14 23:59:59
$timeE = '1268611199';

$timeS = $timeE - ( $timeD * 60 );

`rm -f data.dbl`;
my $dbh = DBI->connect( "dbi:SQLite:data.dbl" ) || die "Cannot connect: $DBI::errstr";
#$dbh->do( "DROP TABLE smtpout" );
#$dbh->do( "DROP TABLE messages" );
#$dbh->do( "CREATE TABLE smtpout ( smtp_tstamp, smtp_result, smtp_id, smtp_dip, smtp_msg )" );
$dbh->do( "CREATE TABLE smtpout ( smtp_tstamp, smtp_id, smtp_result, smtp_state, smtp_dip, smtp_failedto, smtp_msg )" );
$dbh->do( "CREATE TABLE messages ( msg_tstamp INTEGER, msg_id VARCHAR(24), msg_action VARCHAR(16), msg_wf VARCHAR(16), msg_ip VARCHAR(16), msg_from VARCHAR(64), msg_to VARCHAR(64) )" );

# First process smtpout logs
#my $smtp_date = '';
my $smtp_month = '';
my $smtp_day = '';
my $monthnum = '';
my $smtp_time = '';
my $smtp_state = '';
my $smtp_failedto = '';
my $smtp_id = '';
my $smtp_result = '';
my $smtp_dip = '';
my $smtp_msg = '';
#my $msg_date = '';
my $msg_time = '';
my $msg_id = '';
my $msg_action = '';
my $msg_wf = '';
my $msg_smtp = '';
my $msg_ip = '';
my $msg_from = '';
my $msg_to = '';
my $msg_to_grp = '';

my $lc = 0;

# /opt/zimbra/log/2010.03.16/dsmdc-mail-bxga2/mail.log
@files = <$Logfile*>;
foreach $File (@files) {
#print "Processig $File\n";
    # Grab last line in log that begins with a month name
    $ll = `tail $File | egrep '^[A-Z][a-z]{2} ' | tail -1`;
    chomp($ll);
#print "log line $ll\n";
    ($smtp_month, $smtp_day, $smtp_time, undef ) = split (/ /, $ll, 4);
    $monthnum = $mon2num{ $smtp_month };
    $query = "SELECT strftime('%s', \'2010-$monthnum-$smtp_day $smtp_time\')";
#print "query: $query\n";
    $qh = $dbh->prepare($query);
    $qh->execute();
    $qh->bind_columns(\$tstamp);
    $qh->fetch();
#print "tstamp: $tstamp\n\n";
    next if ($tstamp < $timeS);

    open LOGFILE, "< $File" or die "Could not open $File!\n";

    while (<LOGFILE>) {
       chomp;

       $lc++;

       if (/IMP: smtpout/) {
           # smtpout log line
           # skip if state SENT
           next if (m/state="Sent"/);
           # skip local destinations. we're processing outbound only
           next if (m/dip=10.4.20./);
           # skip messages that were delivered
           next if (m/smtp=DATAEND:250/);
           next if (m/smtp=OPEN/);
           next if (m/msg="2.1.5 OK"/);
           next if (m/state="Queued"/);
           next if (m/state="Failed"/);

           if (/state="Aborted"/) {
#Mar 14 01:12:02 dsmdc-mail-bxga2/dsmdc-mail-bxga2 IMP: smtpout id=svC01d00g0s5ysV01vC0si state="Failed" dip=97.64.187.40 dport=25
#Mar 14 01:12:02 dsmdc-mail-bxga2/dsmdc-mail-bxga2 IMP: smtpout id=svC01d00g0s5ysV01vC0si state="Aborted" dip=97.64.187.40 dport=25 failedto="rowalla@mail.mchsi.com"
               ($smtp_month, $smtp_day, $smtp_time, undef, undef, undef, $smtp_id, $smtp_state, $smtp_dip, undef, $smtp_failedto ) = split (/ /, $_, 11);
               $smtp_result = "=NULL";
               $smtp_msg = "=NULL";
           } elsif (/state="Queued"/) {
#Mar 14 01:12:03 dsmdc-mail-bxga2/dsmdc-mail-bxga2 IMP: smtpout id=svC31d0012N2Aw501vC3tb state="Failed" dip=0.0.0.0 dport=0
#Mar 14 01:12:03 dsmdc-mail-bxga2/dsmdc-mail-bxga2 IMP: smtpout id=svC31d0012N2Aw501vC3tb state="Queued" dip=255.255.255.255 dport=0 time=60 retry=0
               ($smtp_month, $smtp_day, $smtp_time, undef, undef, undef, $smtp_id, $smtp_state, $smtp_dip, undef ) = split (/ /, $_, 10);
               $smtp_result = "=NULL";
               $smtp_msg = "=NULL";
               $smtp_failedto = "=NULL";
           } elsif (/smtp=DATAEND/) {
#20100222 01:18:56.382 smtpout sid=kvH81d01A0sjiKD01 smtp=DATAEND:552 id=kvJa1d01y4ZSsAs01vJvTP dip=97.64.187.40 dport=25 type=smtp msg="5.7.0 Number of 'Received:' DATA headers exceeds maximum permitted"
#Mar 14 23:58:05 dsmdc-mail-bxga2/dsmdc-mail-bxga2 IMP: smtpout sid=tGHY1d0013pE49m01 smtp=DATAEND:452 id=t89q1d00L3MmMeR018AaBQ dip=10.4.20.177 dport=7025 type=lmtp msg="4.2.2 Over quota"
               ($smtp_month, $smtp_day, $smtp_time, undef, undef, undef, undef, $smtp_result, $smtp_id, $smtp_dip, undef, undef, $smtp_msg ) = split (/ /, $_, 13);
               $smtp_state = "=NULL";
               $smtp_failedto = "=NULL";
           } elsif (/smtp=MAIL/) {
#Mar 14 23:06:06 dsmdc-mail-bxga2/dsmdc-mail-bxga2 IMP: smtpout sid=tFwN1d00m0sjiKD01 smtp=MAIL:452 id=tG651d00U20Mb3j01G651P dip=97.64.187.40 dport=25 type=smtp msg="4.1.0 <tools@scullyjones.com> requested action aborted: try again later - POL110"
               ($smtp_month, $smtp_day, $smtp_time, undef, undef, undef, undef, $smtp_result, $smtp_id, $smtp_dip, undef, undef, $smtp_msg ) = split (/ /, $_, 13);
               $smtp_state = "=NULL";
               $smtp_failedto = "=NULL";
           } elsif (/smtp=RCPT/) {
               ($smtp_month, $smtp_day, $smtp_time, undef, undef, undef, undef, $smtp_result, $smtp_id, $smtp_dip, undef, undef, $smtp_msg ) = split (/ /, $_, 13);
               $smtp_state = "=NULL";
               $smtp_failedto = "=NULL";
           } else {
               # default
               ($smtp_month, $smtp_day, $smtp_time, undef ) = split (/ /, $_, 4);
               $smtp_result = "=NULL";
               $smtp_id = "=NULL";
               $smtp_dip = "=NULL";
               $smtp_msg = "=NULL";
               $smtp_state = "=NULL";
               $smtp_failedto = "=NULL";
               # also print processed log line for debugging because we should not end up here
               print "$_\n";
           }
           $monthnum = $mon2num{ $smtp_month };
           $query = "SELECT strftime('%s', \'2010-$monthnum-$smtp_day $smtp_time\')";
#print "query: $query\n";
           $qh = $dbh->prepare($query);
           $qh->execute();
           $qh->bind_columns(\$tstamp);
           $qh->fetch();
#print "tstamp: $tstamp\n";
           # skip lines that fall outside time scope
           next if ($tstamp < $timeS);
           last if ($tstamp > $timeE);
           (undef, $smtp_id) = split(/=/, $smtp_id);
           $smtp_id =~ s/(.*)/\'$1\'/;
           (undef, $smtp_result) = split(/=/, $smtp_result);
           $smtp_result =~ s/(.*)/\'$1\'/;
           (undef, $smtp_state) = split(/=/, $smtp_state);
           $smtp_state =~ s/"//g;
           $smtp_state =~ s/(.*)/\'$1\'/;
           (undef, $smtp_dip) = split(/=/, $smtp_dip);
           $smtp_dip =~ s/(.*)/\'$1\'/;
           (undef, $smtp_failedto) = split(/=/, $smtp_failedto);
           $smtp_failedto =~ s/"//g;
           $smtp_failedto =~ s/'//g;
           $smtp_failedto =~ s/(.*)/\'$1\'/;
           (undef, $smtp_msg) = split(/=/, $smtp_msg);
           $smtp_msg =~ s/'//g;
           $smtp_msg =~ s/(.*)/\'$1\'/;
# $dbh->do( "CREATE TABLE smtpout ( smtp_tstamp, smtp_id, smtp_result, smtp_state, smtp_dip, smtp_failedto, smtp_msg )" );
#print "smtp tstamp $tstamp id $smtp_id result $smtp_result state $smtp_state dip $smtp_dip failedto $smtp_failedto msg $smtp_msg\n;
#print "lc $lc INSERT INTO smtpout VALUES ( $tstamp, $smtp_id, $smtp_result, $smtp_state, $smtp_dip, $smtp_failedto, $smtp_msg ) \n";
#exit;
           $dbh->do( "INSERT INTO smtpout VALUES ( $tstamp, $smtp_id, $smtp_result, $smtp_state, $smtp_dip, $smtp_failedto, $smtp_msg ) " );
       } elsif (/IMP: messages/) {
           # messages log line
           # which ones of the below should we just skip instead of dumping to DB to speed up processing?
           #        next if (m/action=ROUTE/);


           if (/action=ROUTE/) {
               ( $smtp_month, $smtp_day, $msg_time, undef, undef, undef, $msg_id, $msg_action, $msg_wf, $msg_ip, $msg_from, $msg_to_grp, undef ) = split (/ /, $_, 13);
               $msg_smtp = "=NULL";
           } elsif (/action=REJECT-CLOSE.*smtp=BANNER/) {
#20100222 00:00:12.325 messages sid=ku011d01T03FYvz01 ip=95.130.132.2 action=REJECT-CLOSE wf=smtp:1:6 smtp=BANNER:554 filters="RBL mediacom zen: 0.10"
#Mar 14 08:24:25 dsmdc-mail-bxga2/dsmdc-mail-bxga2 IMP: messages sid=t1QR1d014307Tg401 ip=84.75.36.139 action=REJECT-CLOSE wf=smtp:1:6 smtp=BANNER:554 filters="RBL mediacom zen: 0.10"
               ( $smtp_month, $smtp_day, $msg_time, undef, undef, undef, $msg_id, $msg_ip, $msg_action, $msg_wf, $msg_smtp, undef ) = split (/ /, $_, 12);
               $msg_from = "=\@NULL";
               $msg_to_grp = "=\@NULL";
           } elsif (/action=REJECT-CLOSE.*smtp=MAILFROM/) {
#20100222 00:00:12.347 messages id=ktzt1d00p0Gdmb401tztjm action=REJECT-CLOSE wf=smtp:4:2 smtp=MAILFROM:550 ip=216.145.216.12 from="thecruiseconsortium=11663@adknowledgemailer.com" to="" filters="RBL mediacom zen: 0.00, RBL mediacom cloudmark: 0.00, SPF[2]"
#Mar 16 00:11:24 dsmdc-mail-bxga2/dsmdc-mail-bxga2 IMP: messages id=thBP1d00h2L9F0d01hBQWt action=REJECT-CLOSE wf=smtp:4:2 smtp=MAILFROM:550 ip=213.8.68.108 from="pointierus@steelgroup.net" to="" filters="RBL mediacom zen: 0.00, RBL mediacom cloudmark: 0.00, SPF[2]"
               ( $smtp_month, $smtp_day, $msg_time, undef, undef, undef, $msg_id, $msg_action, $msg_wf, $msg_smtp, $msg_ip, $msg_from, $msg_to_grp, undef ) = split (/ /, $_, 14);
           } elsif (/action=REJECT/) {
#Mar 16 00:31:55 dsmdc-mail-bxga2/dsmdc-mail-bxga2 IMP: messages id=thWX1d00w037mzQ01hXvjQ action=REJECT wf=smtp:4:1 smtp=MAILFROM:550 ip=12.234.106.2 from="be0900@ebullici.com" to="" filters="RBL mediacom zen: 0.00, RBL mediacom cloudmark: 0.00"
#Mar 14 23:00:00 dsmdc-mail-bxga2/dsmdc-mail-bxga2 IMP: messages id=tFzo1d00V2iTESV01FztlM action=REJECT wf=smtp:5:0 smtp=RCPTTO:550 ip=85.234.125.125 from="jayershe@anyevent.co.uk" to="petefx@mchsi.com" filters=""
               ( $smtp_month, $smtp_day, $msg_time, undef, undef, undef, $msg_id, $msg_action, $msg_wf, $msg_smtp, $msg_ip, $msg_from, $msg_to_grp, undef ) = split (/ /, $_, 14);
           } elsif (/action=FAILURE-CLOSE/) {
#20100222 00:00:12.546 messages sid=ku0C1d00h463cNN01 ip=190.88.19.190 action=FAILURE-CLOSE wf=smtp:1:2 smtp=BANNER:421
               ( $smtp_month, $smtp_day, $msg_time, undef, undef, undef, $msg_id, $msg_ip, $msg_action, $msg_wf, $msg_smtp, undef ) = split (/ /, $_, 12);
               $msg_from = "=\@NULL";
               $msg_to_grp = "=\@NULL";
           } elsif (/action=FAILURE/) {
#20100222 00:00:12.347 messages id=ktzN1d01b3r0wye01tzPUA action=FAILURE wf=smtp:4:1 smtp=MAILFROM:452 ip=62.72.116.178 from="abandon@askgnf.com" to="" filters="RBL mediacom zen: 0.00, RBL mediacom cloudmark: 0.00"
#Mar 16 02:40:23 dsmdc-mail-bxga2/dsmdc-mail-bxga2 IMP: messages id=tjgM1d00R1wyRYr01jgMpG action=FAILURE wf=smtp:4:1 smtp=MAILFROM:452 ip=195.4.92.90 from="info12@cenbankng.com" to="" filters="RBL mediacom zen: 0.00, RBL mediacom cloudmark: 0.10"
               ( $smtp_month, $smtp_day, $msg_time, undef, undef, undef, $msg_id, $msg_action, $msg_wf, $msg_smtp, $msg_ip, $msg_from, $msg_to_grp, undef ) = split (/ /, $_, 14);
           } else {
               # default
               ( $smtp_month, $smtp_day, $msg_time, undef, undef, undef, $msg_id, $msg_action, $msg_wf, $msg_ip, $msg_from, $msg_to_grp, undef ) = split (/ /, $_, 13);
               $msg_smtp = "=NULL";
               # also print processed log line for debugging because we should not end up here
               print "$_\n";
           }
           $monthnum = $mon2num{ $smtp_month };
           $query = "SELECT strftime('%s', \'2010-$monthnum-$smtp_day $msg_time\')";
#print "query: $query\n";
           $qh = $dbh->prepare($query);
           $qh->execute();
           $qh->bind_columns(\$tstamp);
           $qh->fetch();
#print "tstamp: $tstamp\n";
           # skip lines that fall outside time scope
           next if ($tstamp < $timeS);
           last if ($tstamp > $timeE);
           (undef, $msg_id) = split(/=/, $msg_id);
           $msg_id =~ s/(.*)/\'$1\'/;
           (undef, $msg_action) = split(/=/, $msg_action);
           $msg_action =~ s/(.*)/\'$1\'/;
           (undef, $msg_wf) = split(/=/, $msg_wf);
           $msg_wf =~ s/(.*)/\'$1\'/;
           (undef, $msg_smtp) = split(/=/, $msg_smtp);
           $msg_smtp =~ s/(.*)/\'$1\'/;
           (undef, $msg_ip) = split(/=/, $msg_ip);
           $msg_ip =~ s/(.*)/\'$1\'/;
#print "from $msg_from\n";
           if ( $msg_from !~ /@/ ) {
              $msg_from = "=\@NULL";
           }
           (undef, $msg_from) = split(/@/, $msg_from);
           $msg_from =~ s/(.*)/\'$1\'/;
           $msg_from =~ s/"//;
           if ( $msg_to_grp !~ /@/ ) {
              $msg_to_grp = "=\@NULL";
           }
    # handle multiple recipients listed in to= section
           (undef, $msg_to_grp) = split(/=/, $msg_to_grp, 2);
           foreach $msg_to (split (/,/, $msg_to_grp )) {
               (undef, $msg_to) = split(/@/, $msg_to);
               $msg_to =~ s/(.*)/\'$1\'/;
               $msg_to =~ s/"//;
#print "tstamp $tstamp id $msg_id action $msg_action wf $msg_wf ip $msg_ip from $msg_from to $msg_to\n";
#print "INSERT INTO messages VALUES ( $tstamp, $msg_id, $msg_action, $msg_wf, $msg_ip, $msg_from, $msg_to ) \n";
               $dbh->do( "INSERT INTO messages VALUES ( $tstamp, $msg_id, $msg_action, $msg_wf, $msg_ip, $msg_from, $msg_to ) " );
           }
       }       # if (/IMP: smtpout/)
    }          # while (<LOGFILE>)
    close LOGFILE;
} # foreach $File (@files)

print "processed $lc lines of logs\n";

$query = "SELECT count(msg_to) as cnt, msg_to FROM smtpout, messages WHERE smtpout.smtp_id = messages.msg_id $domain GROUP BY msg_to ORDER BY cnt";
#print "domain $domain\nquery $query\n";
my $res = $dbh->selectall_arrayref( $query );
foreach( @$res ) {
  if ( $_->[0] >= $warn ) {
    $returnVal = 1;
    print "$_->[0], $_->[1]\n";
  }
}

$query = "select count(*) as cnt, msg_ip, msg_action from messages group by msg_ip, msg_action order by cnt desc";
#print "domain $domain\nquery $query\n";
$res = $dbh->selectall_arrayref( $query );
foreach( @$res ) {
  if ( $_->[0] >= $critical ) {
    $returnVal = 2;
    print "$_->[0], $_->[1], $_->[2]\n";
  }
}

$qh->finish();
$dbh->disconnect;

exit $returnVal;
