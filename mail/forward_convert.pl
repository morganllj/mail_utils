#!/bin/perl -w
#

use strict;
use File::Basename;
use Getopt::Std;

sub print_usage();

my $opts;

getopt('i:o:', \%$opts);

my $input_file = $opts->{i} || print_usage();
my $output_file = $opts->{o} || print_usage();

my $homedir_prefix = "/archive";

open (IN, $input_file) || die "can't open $input_file";
open (OUT, ">$output_file") || die "can't open $output_file";



while (<IN>) {
    chomp;

    my ($user, $homedir) = (split(/:/))[0,5];
    if ($homedir !~ /^\s*\//) { print "skipping $_\n"; next; }

    $homedir = $homedir_prefix . $homedir;

    my $forwardFile = $homedir . "/.forward";

    if ( ! -f $forwardFile) { next; }
    print "\tforwardFile: /$forwardFile/\n";

    # open and parse the forward file
    open (F_IN, $forwardFile) || die "problem opening $forwardFile";

    my @forwards;
    while (<F_IN>) {
        chomp;

        if (/\,/) { # comma separated aliases
            if (check_for_vacation($_)) {
                print "\tskipping vacation: $_\n";
                next;
            }
            my @subEntries = split (/,\s*/);
            my $parentEntry = $_;
            for (@subEntries) {
                print "checking /$_/\n";
                if (my $ret = check_for_alias($_)) {
                    if ($ret eq $user) {
                        print "adding $user: delivery\n";
                        push @forwards, "ims-ms";
                    } else {
                        print "\tadding $user: $_\n";
                        push @forwards, $_;
                    }
                } else {
                    printError("invalid subentry $_ in $parentEntry");
                }
            }
        } elsif (check_for_alias($_)) {
            print "\tadding $user: $_\n";
            push @forwards, $_;
        } elsif (/^\s*$/) {
            # blank line
            next;
        } else {
            print "\tinvalid forward entry: /$_/\n";
        }
    }
    close (F_IN);

    if ($#forwards > -1) {
        my $user_in_ldap = `/usr/bin/ldapsearch -D "cn=directory manager" -w serverw1 -Lb dc=oswego,dc=edu uid=$user uid`;
        if (!defined $user_in_ldap or !$user_in_ldap) {
            print "$user is not in ldap, skipping"; 
        } else {
            my $dn = $user_in_ldap;
            $dn =~ /dn:\s*([^\n]+)\n/;
            $dn = $1;

            print OUT "dn: $dn\n";
            print OUT "changetype: modify\n";
            print OUT "replace: maildeliveryoption\n";
            print OUT "maildeliveryoption: forward\n";
            
            for (@forwards) {
                print OUT "maildeliveryoption: mailbox\n"
                    if (/ims-ms/);
            }
            print OUT "-\n";
            print OUT "replace: mailforwardingaddress\n";
            for (@forwards) {
                print OUT "mailforwardingaddress: $_\n"
                    unless (/ims-ms/);
            }
            print OUT "\n";
        }
    }
}
close (IN);




sub printError {
    my $in = shift;
    
    print "\terror: $in\n";
}

sub check_for_vacation {
    my $in = shift;
    
    return 1
        if $in =~ (/^\s*\\([^\,]+)\,\s*\"\|\/usr\/bin\/vacation\s+([^\"]+)\"/);
    return undef;
}

sub check_for_alias {
    my $in = shift;

    if ($in =~ /^\\*(\s*[a-zA-Z0-9_\@\.\-]+\s*)$/) {
        return $1;
    }
    return undef;
}

sub print_usage() {

    print "\n\nusage: $0 -i <nis dump> -o <output file>\n\n"; 
    exit;
}
