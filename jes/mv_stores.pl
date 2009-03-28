#!/usr/bin/perl -w
#

use strict;

my @domain_from =    "ext.domain.org";
my @hosted_domains = qw/srdc.domain.org cett.dc=domain,dc=org dafvm.dc=domain,dc=org/;

for my $d (@hosted_domains) {
    print "\n$d:\n";

    for my $u (`/usr/bin/ldapsearch -D "cn=directory manager" -w 'pass' -Lb o=$d,o=msu_ag objectclass=inetmailuser uid|egrep '^uid'|cut -d ' ' -f 2`) {
        chomp $u;
        print "$u\n";
        my $mboxutil = `/opt/SUNWmsgsr/sbin/mboxutil -l`;
        my @m = grep (/user\/($u\@[^\/]+|$u)\/INBOX/, split(/\n/, $mboxutil));
        print join ("\n", @m), "\n";;

        # if both user and user@$d exist mboxtuil -d then mboxutil -r user user@
        # if just user exists mboxutil -r the user to '@'
        # if just user@ do nothing
        # print "u: /$u/ d: /$d/\n";
        if ((my ($usra) = grep /(user\/[^\@]+\@$d\/INBOX)/, @m) &&
            (my ($usr) =  grep /(user\/$u\/INBOX)/, @m)) {
            $_ = $usra;
            ($usra) = /(user\/[^\@]+\@$d\/INBOX)/;
            $_ = $usr;
            ($usr)  = /(user\/$u\/INBOX)/;
            my $d_cmd = "/opt/SUNWmsgsr/sbin/mboxutil -d $usra";
            print "$d_cmd\n";
            system "$d_cmd";
            my $r_cmd =  "/opt/SUNWmsgsr/sbin/mboxutil -r $usr $usra\n";
            print "$r_cmd\n";
            system "$r_cmd";
        } elsif (($usr) = grep /(user\/$u\/INBOX)/, @m) {
            $_ = $usr;
            ($usr) = /(user\/$u\/INBOX)/;
            my $usra = $usr;
            ($usra) =~ s/$u/$u\@$d/;
            my $r_cmd = "/opt/SUNWmsgsr/sbin/mboxutil -r $usr $usra"; 
            print "$r_cmd\n";
            system "$r_cmd";
        }
        print "\n";
    }
} 
