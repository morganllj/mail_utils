#!/usr/local/bin/perl -w

# imsbackups.pl 
# Author: Andy Jatras
#         with modifications by Morgan Jones (morgan@morganjones.org)
# Id:     $Id$
#
# Uses backup-groups.conf and reformats output to proper format for imsbackup
# then calls Y imsbackups in parallel and then pipes into the DATA_COMPRESSION.
 
# Discovered the output compressed file were being corrupted. The file remove
# operation has been taken out of the foreach loop as well as the file rename
# operation so that only the IMSBACKUPS piped DATA_COMPRESSION operation is
# the only system operation in the parallel foreach loop.  

use strict;
# use Parallel::ForkManager;
use Parallel::Forker;
use Sys::Hostname::FQDN qw(short);
use Getopt::Std;

my $host = short();
my $base = "/usr/iplanet-$host/msg61/msg-$host";
my $backupgroups = "$base/config/backup-groups.conf";
# my $backupdir = "/var/backup-${host}";
my $backupdir_reg = "/var/backup-${host}";
my $backupdir_tmp = "/var/backup-${host}tmp";
# my $DATA_COMPRESSION = "/usr/bin/gzip";
# my $DATA_COMPRESSION = "/usr/bin/bzip2";
my $DATA_COMPRESSION = "/usr/bin/bzip2 -vc";
my $IMSBACKUPS = "/usr/iplanet-$host/msg61/sbin/imsbackup";
my $PARALLEL = 5; # default
my $PARTITON = "/primary";
my @DATA = "";
# my $lastfull = "$backupdir/last-full.txt";
my $lastfull = "$backupdir_reg/last-full.txt";
my $lastfulldate;
my $opts = "";

our ($opt_f, $opt_i, $opt_p, $opt_h, $opt_n);

getopts('fihnp:');

sub usage()
{
    print STDERR << "EOF";

    usage: $0 [-fip] [-h]

      -f        : Full backup
      -i        : Incremental backup
      -p        : Parallel
      -n        : print but do not do anything 
      -h        : Display this help

    example: $0 -f -p5 ( Full backup with Parallelism set to 5 )

    example: $0 -i -p3 ( Incremental backup with Parallelism set to 3 )

EOF
exit;
}

if (($opt_h) || (($opt_i) && ($opt_f))) {
    usage();
}

if ($opt_f) {
    # system ("/usr/bin/date '+%Y%m%d' > $backupdir/last-full.txt");
    $opt_n || system ("/usr/bin/date '+%Y%m%d' > $backupdir_reg/last-full.txt");
}

if ($opt_i) {
    open(LAST, "$lastfull") || die "Could not open $lastfull\n";
    chomp($lastfulldate = <LAST>);
    $opts = "-d $lastfulldate";
    close LAST;
}

if ($opt_p) {
    $PARALLEL = $opt_p;
}

open(GROUPS,"$backupgroups") || die "Could not open $backupgroups\n";
chomp(@DATA = <GROUPS>);
close GROUPS;

# First remove all of the previous backups.
print ("/usr/bin/rm $backupdir_reg/users_*\n");
$opt_n || system ("/usr/bin/rm $backupdir_reg/users_*");
print ("/usr/bin/rm $backupdir_tmp/users_*\n");
$opt_n || system ("/usr/bin/rm $backupdir_tmp/users_*");

# my $pm = new Parallel::ForkManager($PARALLEL);
my $fork = new Parallel::Forker;
$fork->max_proc($PARALLEL);

# Output first to a .noback file which is in the NBU exclude list and then mv
# file after it finishes - this is so NBU will not backup any files that are
# in progress if the imsbackups run longer than expected.

foreach (@DATA) {

#     my $pid = $pm->start and next; 
      my $group_briefly = (split(/=/))[0];

    $fork->schedule (
        run_on_start => sub {

            my $group = $group_briefly;
            my $backupdir;
            if ($group =~ /users_[ACEGIKMOQSUWY]/i) {
                $backupdir = $backupdir_reg; 
            } else {
                $backupdir = $backupdir_tmp; 
            }

            # print ("$IMSBACKUPS $opts -f - $PARTITON/$group | $DATA_COMPRESSION > $backupdir/$group.bz2.noback\n");
            # system ("$IMSBACKUPS $opts -f - $PARTITON/$group | $DATA_COMPRESSION > $backupdir/$group.bz2.noback");
            print ("$IMSBACKUPS $opts -f - $PARTITON/$group > $backupdir/$group.noback at ",`date`);
            $opt_n || system ("$IMSBACKUPS $opts -f - $PARTITON/$group > $backupdir/$group.noback");
            if ($? == -1) {
                print "imsbackup $group failed to execute: $! at ",`date`;
            } elsif ($? & 127) {
                printf "imsbackup $group child died with signal %d, %s coredump at ",
                ($? & 127),  ($? & 128) ? 'with' : 'without';
                print `date`;
            } else {
                printf "imsbackup $group child exited with value %d at ", $? >> 8;
                print `date`;
            }
 

#             print("mv $backupdir/$group.bz2.noback $backupdir/$group.bz2\n");
#             system("mv $backupdir/$group.bz2.noback $backupdir/$group.bz2");
            print("mv $backupdir/$group.noback $backupdir/$group at ", `date`);
            $opt_n || system("mv $backupdir/$group.noback $backupdir/$group ");
            if ($? == -1) {
                print "mv $group failed to execute: $! at ",`date`;
            } elsif ($? & 127) {
                printf "mv $group child died with signal %d, %s coredump at ",
                ($? & 127),  ($? & 128) ? 'with' : 'without';
                print `date`;
            } else {
                printf "mv $group child exited with value %d at ", $? >> 8;
                print `date`;
            }
            print "\n";
        }
    )
    ->ready();


#     $pm->finish; 
#        }   
}

$fork->wait_all();
