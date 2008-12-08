#!/usr/bin/perl -w
#
# search the contents of @attrs out of ldap in the order presented
# and print them as a csv list
# Morgan Jones (morgan@morganjones.org)
# $Id$


use strict;

my @attrs = qw/givenname sn uid l/;

my $srch_cmd = "ldapsearch -h mcsd-dir -w pass -D cn=manager -b dc=domain,dc=org '(&(objectclass=inetmailuser)(employeetype=*))' " . join (" ", @attrs);

open (IN, $srch_cmd."|");


$/="";
while (<IN>) {
    # print "/$_/\n";
    s/dn:\s*([^\n]+)\n//;

    for my $a (@attrs) {
        /$a:\s*([^\n]+)\n/;
        print $1
            if (defined $1);
        print ","
            unless ($a eq $attrs[$#attrs]);
    }
    print "\n";
}

