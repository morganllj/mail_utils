#!/usr/bin/perl -w
#
# export_jes_calendar.pl
# Morgan Jones (morgan@morganjones.org)
# $Id$
# parse the output of cscal list and create a .ics calendar for every calendar
#
use strict;
use Getopt::Std;

sub print_usage();


#########
### Site-specific settings
my $cal_bin="/bellatrixdg00/luminis/products/SUNWics5/cal/sbin";
my $cal_cmd="./cscal list";
### end site-specific settings



my $opts;
getopts('hu:o:p:f:d', \%$opts);

$opts->{h} && print_usage();
my $user_list = $opts->{u};
my $pidm_map_file = $opts->{p} || print_usage();
my $ics_out_dir = $opts->{o} || print_usage();

if (exists $opts->{u} && exists $opts->{f}) {
    print "-f and -u are mutually exclusive\n";
    print_usage();
}

my @users2import;
if (exists $opts->{f}) {
    
    open (USRS_IN, $opts->{f}) || die "can't open $opts->{f}";
    while (<USRS_IN>) {
        chomp;
        push @users2import, $_;
    }
} elsif (exists $opts->{u}) {
    @users2import = split /\s+/, $opts->{u};
        #if (exists $opts->{u});
} else {
    print_usage();
}

die "$ics_out_dir does not exist or is not writable"
    unless (-d $ics_out_dir);

print "\nusers to import: ", join (' ', @users2import), "\n";

my %pidm_map;

open (IN, $pidm_map_file) || die "can't open $pidm_map_file";

while (<IN>) {
    chomp;

    my ($pidm, $uid) = split /\,/;
    $uid =~ s/\"//g;
    if (exists $pidm_map{$pidm}) {
        print "$pidm found more than once!?\n";
    } else {
        $pidm_map{$pidm} = $uid;
    }
}

print "running ./cscal list from $cal_bin\n";
open EXEC, "cd $cal_bin && $cal_cmd |";

while (<EXEC>) {
    chomp;

    my ($name, $pidm, $status);
    if (/[^:]+:([^:]+):\s+owner=([^\s]+)\s+status=(.*)/) {
         $name = $1;
         $pidm = $2;
         $status = $3;
    } elsif (/[^:]+:\s+owner=([^\s]+)\s+status=(.*)/) {
         $pidm = $1;
         $status = $2;
    } else {
        print "ignoring unparsable entry: /$_/\n"
            if (exists $opts->{d};
        next;
    }

    if (!exists($pidm_map{$pidm})) {
        print "$pidm not in pidm map: /$_/\n"
            if (exists $opts->{d});
        next;
    }

     next
         if ((exists $opts->{u} || exists $opts->{f}) && ! grep /^$pidm_map{$pidm}/, @users2import);    

    if (!defined $pidm || $pidm =~ /^\s*$/) {
        print "ignoring calender with no owner: /$_/\n";
    }

    print "/$_/\n";

    my $ics_cmd = "./csexport -c $pidm";
    if (defined $name && $name !~ /^\s*$/) {
        $ics_cmd .= ":$name";
    }
    $ics_cmd .= " calendar ${ics_out_dir}/$pidm_map{$pidm}";
    $ics_cmd .= "_$name"
        if (defined $name && $name !~ /^\s*$/);
    $ics_cmd .= ".ics\n";
    
    print "$ics_cmd";
    system "cd $cal_bin && $ics_cmd";
}


sub print_usage() {

    print "\nusage: $0 -p <pidm map> -o <ics output dir>\n".
        "\t[ -u <user_list> || -f <user list file>]\n";
    print "\n";
    print "\t-p <pidm map> csv containing pidm to username map\n";    
    print "\t-o <ics output dir> directory to put exported ics files\n";
    print "\t-u <user_list> whitespace separated list of users to import\n";
    print "\t-f <user list file> <cr> separated  list of users to import\n";
    exit;
}
