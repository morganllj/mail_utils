#!/usr/bin/perl -w
#

use Getopt::Std;

my %opts;
getopt ('n', \%opts);

print "-n used, no changes will be made\n\n"
  if (exists $opts{n});

my $archive_path = qw:/usr/local/mailman/archives:;
my $mbox_purge = qw:/usr/local/sbin/mbox-purge.pl:;
my $arch = qw:/usr/local/mailman/bin/arch:;
print "archive_path: $archive_path\n";

my $t = time();

# 86400 seconds in a day
my $days_ago = time() - (86400 * 30);

my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = 
  localtime ($days_ago);

$year +=1900;
$mon++;
$mon = "0" . $mon
  if ($mon < 10);
$mday = "0" . $mday
  if ($mday < 10);


#my $archives = `ls /var/mail_log/archives/*/*mbox/*mbox`;
#chomp $archives;
my @archives = split /\n/, `ls $archive_path/*/*mbox/*mbox`;
for my $a (@archives) {
    print "\n$mbox_purge --before $year-$mon-$mday $a\n";
    unless (exists $opts{n}) {
	die "problem with mbox-purge, aborting."
	  if (system "$mbox_purge --before $year-$mon-$mday $a\n");
    }

    # the mbox is deleted if there are no messages in it
    if (-e $a) {
	my @l = split /\//, $a;
	$listname = $l[-1];
      
	$listname =~ s/.mbox$//;
	print "$arch --wipe $listname\n";
	unless (exists $opts{n}) {

	    die "problem with $arch, aborting."
	      if (system "$arch --wipe $listname");
	}
    }
}

