#!/usr/bin/perl -w
#

# on each mta:
# cd /var/log
# (zcat `ls -tr maillog*gz` && cat maillog) | ~/get_auth_tls.pl > /var/tmp/user_auth_raw_mta01.out
#
# centrally:
# cat user_auth_raw_mta0[123].out|grep TLS|cut -d, -f1|sort -fu > users_authing.txt
# cat user_auth_raw_mta0[123].out |grep -v TLS|egrep -v '170.235.1|127.0.0.1'|awk '{print $3}'|cut -d@ -f1|sort -fu  > users_not_authing.txt


# [root@mta03 log]# egrep '652E21E003B|D50DE1E0096' maillog|grep 'Jul 14'
# Jul 14 18:16:53 mta03 postfix/smtpd[15876]: 652E21E003B: client=unknown[10.32.32.133]
# Jul 14 18:16:53 mta03 postfix/cleanup[15441]: 652E21E003B: message-id=<56783F2F-5890-466F-971E-31106184FA7E@domain.org>
# Jul 14 18:16:53 mta03 postfix/qmgr[20236]: 652E21E003B: from=<morgan@domain.org>, size=562, nrcpt=1 (queue active)
# Jul 14 18:16:53 mta03 postfix/smtpd[10577]: D50DE1E0096: client=localhost.localdomain[127.0.0.1]
# Jul 14 18:16:53 mta03 postfix/cleanup[15441]: D50DE1E0096: message-id=<56783F2F-5890-466F-971E-31106184FA7E@domain.org>
# Jul 14 18:16:53 mta03 postfix/qmgr[20236]: D50DE1E0096: from=<morgan@domain.org>, size=1024, nrcpt=1 (queue active)
# Jul 14 18:16:53 mta03 postfix/smtp[15442]: 652E21E003B: to=<morgan@morganjones.org>, relay=127.0.0.1[127.0.0.1]:10024, delay=0.54, delays=0.17/0/0/0.37, dsn=2.0.0, status=sent (250 2.0.0 Ok: queued as D50DE1E0096)
# Jul 14 18:16:53 mta03 postfix/qmgr[20236]: 652E21E003B: removed
# Jul 14 18:16:53 mta03 postfix/smtp[11210]: D50DE1E0096: to=<morgan@morganjones.org>, relay=relay.domain.org[170.235.1.83]:25, delay=0.1, delays=0.03/0.01/0.01/0.06, dsn=2.0.0, status=sent (250 Ok: queued as E83A41446E04)
# Jul 14 18:16:53 mta03 postfix/qmgr[20236]: D50DE1E0096: removed
# [root@mta03 log]# 


use strict;

my %tlsIPs;
#my %noAuthIPs;
my %noAuthIDs;

while (<>) {
    chomp;

    if (/setting up TLS [^\[]+\[(\d+\.\d+\.\d+\.\d+)\]/) {

        my $ip = $1;
        my $short = $_;

        my $h = (split /\s+/)[3];
        my $d = (split /\s+/)[4];
        $d =~ s/\[/\\[/;
        $d =~ s/\]/\\]/;

        $short =~ s/\s$h//;
        $short =~ s/\s$d//;
        $short =~ s/\ssetting up//;
        $short =~ s/\sfrom//;
        $short =~ s/\sconnection//;

        $tlsIPs{$ip} = $short;
    } elsif (/client=[^\[]+\[(\d+\.\d+\.\d+\.\d+)\],\s+sasl_method=[^\,]+,\s+sasl_username=(.*)/) {
        my $ip = $1;
        my $user = $2;

        my $short = $_;

        my $h = (split /\s+/)[3];
        my $d = (split /\s+/)[4];
        $d =~ s/\[/\\[/;
        $d =~ s/\]/\\]/;

        $short =~ s/\s$h//;
        $short =~ s/\s$d//;
        $short =~ s/client=//;
        $short =~ s/sasl_method=[^\s]+\s//;
        $short =~ s/sasl_username=//;
        
        print "$user, $ip ";

        if (exists $tlsIPs{$ip}) {
            print "with TLS: ";
        } else {
            print "without TLS: "
        }

        print " /$short/";
        print " /$tlsIPs{$ip}/"
            if (exists $tlsIPs{$ip}); 
        print "\n"
#     } elsif (/client=/) {  # implies !sasl_method
     } elsif (/client=[^\[]+\[(\d+\.\d+\.\d+\.\d+)\]/) {  # implies !sasl_method
         my $ip = $1;

         my $id = (split (/\s+/))[5];
         $id =~ s/:$//;

         $noAuthIDs{$id} = $ip;
    } elsif (/from=<([^>]+)>/) {
        my $from = $1;

        my $id = (split (/\s+/))[5];

        $id =~ s/:$//;

        print "no auth: $from, $noAuthIDs{$id} /$_/\n"
             if (($from =~ /\@domain.org/ || $from =~ /\@domain.org/) &&
                     exists $noAuthIDs{$id});
    }

}


#sub shorted_log_line {
    
#}
