#!/usr/bin/perl -w
#

use strict;
use Getopt::Std;

sub print_usage();

my $opts;
getopt('i:o:', \%$opts);

print "starting $0 at  " . `date`;

my $input_file = $opts->{i} || print_usage();
my $output_file = $opts->{o} || print_usage();

open (USER_IN, $input_file) || die "can't open $input_file";
open (USER_OUT, ">$output_file") || die "can't open $output_file for writing";

my $homedir_prefix = "/archive";

while (<USER_IN>) {
    chomp;

#    print "working on /$_/\n";
    
    my ($user, $homedir) = (split(/:/))[0,5];

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
        if (defined($chunk1) && $chunk1 =~ /^from/i) {
            my @pieces = split(/\//, $txtFile);
            for (split (/\//, $_homedir)) {
                shift @pieces;
            }
            print USER_OUT "$_user ", join ("/", @pieces) . "\n";
        }
        close (IN);
    }
    
}


sub get_txt_files {
    my $dirName = shift;
    my $_level = shift;
    
    return if ($dirName =~ /\/\.\.$/);
    return if ($dirName =~ /\/\.$/);
    return if ($_level++ > 1);

    my @_txtFiles;

#    print "\topening $dirName\n";
    unless (opendir(DIR, $dirName)) {
        print "can't open $dirName";
        return;
    }
    my @files = readdir (DIR);
    for my $file (@files) {
        my $fqFile = $dirName . "/" . $file;

        my $fileForFile = $fqFile;
        # $fileForFile =~ s/\s{1,1}/\\ /;
        my $savedFile = $fileForFile;
        $fileForFile =~ s/([^\/a-zA-Z0-9\._\-.]{1,1})/\\$1/g;
	
        my $fileOut = `file $fileForFile`;
        chomp $fileOut;

        my $fileType = (split(/:\s*/, $fileOut))[1];

        
        if (!defined $fileType) {
            print "no type$fileForFile fileOut: $fileOut\n";
        } elsif ($fileType =~ /ascii/ ||
            $fileType =~ /English/) {
            push @_txtFiles, $fqFile;
        } elsif ($fileType =~ /directory/i) {
            push @_txtFiles, get_txt_files($fqFile,$_level); 
        
        }
    }

    return @_txtFiles;
}

sub print_usage() {

    print "\nusage: $0 -i <NIS dump file> -o <output file>\n\n";
    exit;
}
