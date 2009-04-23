#!/usr/bin/perl -w
#

use strict;
use Getopt::Std;

sub print_usage();
$| = 1;

my $opts;
getopts('m:n:u:', \%$opts);

my $folder_list = $opts->{m} || print_usage();
my $nis_dump = $opts->{n} || print_usage();
my $user_list = $opts->{u} || print_usage();

my $homedir_prefix = "/archive";
my $imsimport = "/opt/SUNWmsgsr/sbin/imsimport";

print "starting at " . `date`;
print "\n";

print "importing NIS dump file from $nis_dump...";
open (NIS_IN, "$nis_dump") || die "unable to open $nis_dump";

my $homedir_map;
while (<NIS_IN>) {
    my ($username, $homedir) = (split /:/)[0,5];
    $homedir = "/archive" . $homedir;
    # print "adding $username, $homedir\n";
    $homedir_map->{$username} = $homedir; 
}
close (NIS_IN);
print "done\n";

print "reading users to import from $user_list...";
open (USERS_IN, $user_list) || die "unable to open $user_list";

my $users_on_this_store;
while (<USERS_IN>) {
    chomp;

    # print "working on user /$_/\n";
    $users_on_this_store->{$_} = 1; 
}
print "done\n";

print "\nbeginning import..\n";
open (FOLDER_LIST_IN, $folder_list) || die "unable to open $folder_list";
while (<FOLDER_LIST_IN>) {
    my ($username, @rest) = split /\s+/;
    my $relative_maildir = join ' ', @rest;
    if (!exists $users_on_this_store->{lc $username}) {
        next;
    }
    # print "working on $username, $relative_maildir\n"; 
    if (exists $homedir_map->{$username}) {
        my $import_path = $homedir_map->{$username} . "/" . $relative_maildir; 
        # $import_path =~ s/([^\/a-zA-Z0-9\._\-.]{1,1})/\\$1/g;
        # print "working on $username, $import_path\n"; 
        print "$imsimport -d $relative_maildir -u $username -s $import_path\n";
        `$imsimport -d "$relative_maildir" -u $username -s "$import_path"`;
        if ($? != 0) {
            print "error importing $username $import_path\n";
            next;
        }
    } else {
        print "$username exists in $homedir_prefix but not in Oswego's NIS\n";
        next;
    }

}
close (FOLDER_LIST_IN);
print "finished at " . `date` . "\n";

sub print_usage() {

    print "\n\nusage: $0 -m <mail folder list> -n <nis dump>\n ".
          "\t-u <user_list>\n\n";
    print "\t-m <mail folder list> output from findMailFolders.pl -o switch\n";
    print "\t-n <nis dump> dump of Oswego's NIS maps\n";
    print "\t-u <user_list> <cr> separated list of users to import\n";
    exit;
}
