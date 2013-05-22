#!/usr/bin/perl -w
#
# $Id$
# Morgan Jones (morgan@morganjones.org)
#
# Given an /etc/passwd format input search out files that look like
# mbox format for input into a mail system with a different storage
# format.
#
# TODO: check $_level in get_text_files()

use strict;
use Getopt::Std;

sub print_usage();

my $opts;
getopt('i:o:u:f:', \%$opts);

my $input_file = $opts->{i} || print_usage();
my $output_file = $opts->{o} || print_usage();
# my $users_to_migrate = $opts->{u};

print "starting $0 at  " . `date`;

if (exists $opts->{u} && exists $opts->{f}) {
    print "-f and -u are mutually exclusive\n";
    print_usage();
}


my %users_to_migrate;

if (exists $opts->{u}) {
    for my $u (split /\s*,\s*/, $opts->{u}) {
        $users_to_migrate{$u} = 1;
    }
} elsif (exists $opts->{f}) {
    open (IN, $opts->{f}) || die "unable to open $opts->{f}\n";
    while (<IN>) {
        chomp;
        $users_to_migrate{lc $_} = 1;
    }
    close (IN);
}

if (%users_to_migrate) {
    print "migrating: ", join (' ', keys %users_to_migrate), "\n";
}

open (USER_IN, $input_file) || die "can't open $input_file";
open (USER_OUT, ">$output_file") || die "can't open $output_file for writing";

#my $homedir_prefix = "/archive";
my $homedir_prefix = "";

while (<USER_IN>) {
    chomp;
        
    my ($user, $homedir) = (split(/:/))[0,5];

    next
        if (%users_to_migrate && ! exists $users_to_migrate{lc $user});

    $homedir = $homedir_prefix . $homedir;

    print "\nworking on $user $homedir\n";
    
    process_user($user, $homedir);
}
close (USER_IN);

print "finished $0 at  " . `date`;

sub process_user {
    my $_user = shift;
    my $_homedir = shift;

    my $level = 0;  # limit recursion

    for my $txtFile (get_txt_files($_homedir, $level)) {
        unless (open (IN, $txtFile)) {
            print "there was a problem opening $txtFile";
            next;
        }
        local $/ = "";
        
        my $chunk1 = <IN>;
   #    my $chunk2 = <IN>;
        # if ($chunk1 =~ /^from/i && $chunk2 =~ /^from/) {
        if (defined($chunk1) && $chunk1 =~ /^From /) {
            my @pieces = split(/\//, $txtFile);
            for (split (/\//, $_homedir)) {
                shift @pieces;
            }
            print USER_OUT "$_user ", $_homedir, ' ', join ("/", @pieces) . "\n";
        }
        close (IN);
    }
    
}


sub get_txt_files {
    my $dirName = shift;
    my $_level = shift;
    
    return if ($dirName =~ /\/\.\.$/);
    return if ($dirName =~ /\/\.$/);
    return if ($_level++ > 4);

    my @_txtFiles;

#    print "\topening $dirName\n";
    unless (opendir(DIR, $dirName)) {
        warn "can't open $dirName\n";
        return;
    }
    my @files = readdir (DIR);
    for my $file (@files) {
        my $fqFile = $dirName . "/" . $file;

        my $fileForFile = $fqFile;
        # $fileForFile =~ s/\s{1,1}/\\ /;
        my $savedFile = $fileForFile;
        $fileForFile =~ s/([^\/a-zA-Z0-9\._\-.]{1,1})/\\$1/g;
	
        my $fileOut = `file -h $fileForFile`;
        chomp $fileOut;

        my $fileType = (split(/:\s*/, $fileOut))[1];

        
        if (!defined $fileType) {
            print "no type$fileForFile fileOut: $fileOut\n";
        } elsif ($fileType =~ /ascii/ ||
            $fileType =~ /English/ || $fileType =~ /commands/) {  # if a file is 700 file -h will show it as 'commands text'
            push @_txtFiles, $fqFile;
        } elsif ($fileType =~ /directory/i) {
            push @_txtFiles, get_txt_files($fqFile,$_level); 
        
        }
    }

    return @_txtFiles;
}

sub print_usage() {

    print "\nusage: $0 (-u <users to migrate>|-f <file>)\n".
        "\t-i <getent output file> -o <output file>\n";
    print "\n";
    print "\t-f is mutually exclusive with -u\n";
    print "\n";
    print "\t[-u <users to migrate>] comma separated list of users\n";
    print "\t[-f <file>] a file containing a <cr> separated list of users to migrate\n\n";
    exit;
}
