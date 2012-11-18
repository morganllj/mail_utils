#!/usr/bin/perl -w

use strict;
use Getopt::Std;

my %opts;
getopts('dn', \%opts);

print "-n used, no modifications will be made.\n"
  if (exists $opts{n});
print "-d used, debugging will be printed.\n"
  if (exists $opts{d});

my @hosts=qw/mail01 mail02 mail03 mail04 mail05/;
#my @hosts=qw/mail01/;
my @logs=qw/nginx.log/;
my $dest="/var/mail_log/nginx";
my $src="/opt/zimbra/log";

my %mon2num = qw(
  jan 01  feb 02  mar 03  apr 04  may 05  jun 06
  jul 07  aug 08  sep 09  oct 10 nov 11 dec 12
);

for my $host (@hosts) {
    for my $log (@logs) {
	print "\n${host}:\n"
	  if (exists $opts{d});
	my $out=`ssh ${host}-mgmt.oit.domain.net "cd ${src} && ls -ltrah ${log}*"`;
	for my $line (split /\n/, $out) {
	    print "/$line/\n"
	      if (exists $opts{d});
	    my @line = split (/\s+/, $line);
	    my $mon = $mon2num{lc $line[5]};
	    my $day = $line[6];
	    my $year = `date +'%y'`;
	    my $hour = (split /:/, $line[7])[0];
	    my $min = (split /:/, $line[7])[1];
	    my $remote_file = $line[8];

	    chomp $year;
	    my $dest_log = $log . "." . $host ;

	    # if the log is gzipped it is an archived and thus unchanging--add
	    # the time to the filename to reduce the changes that a
	    # file created with the same date will overwrite.  This
	    # could mean we end up with duplicates but that's better
	    # than losing files.
	    if ($line =~ /gz$/) {
		$dest_log .= "." . ${year} . ${mon} . ${day} . "." . $hour . $min . ".gz";
	    }

	    my $rsync = "rsync -aHe ssh ${host}-mgmt.oit.domain.net:${src}/$remote_file ${dest}/${dest_log}";
	    print $rsync . "\n"
	      if (exists $opts{d});
	    system "$rsync"
	      unless (exists $opts{n});
	}
    }
}

