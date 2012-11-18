#!/usr/bin/perl -w
#
# to harvest refusals out of log1's bizanga logs:
# cat /opt/zimbra/log/????.??.??/*imta-01/mail.log /opt/zimbra/log/????.??.??/*bxga2/mail.log  |~/parse-syslog_simplified.pl >/var/tmp/30_days_refusals.out

use strict;
my $count=0;
my %rcpt;

while (<>) {
    $count++;
    
    if (/smtp=RCPTTO:550/) {
#        my ($ip,$from,$to) = ($_ =~ /ip=(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}) from=\"(.*?)\" to=\"(.*\@.*)\" filters=/);
        my ($from,$to) = ($_ =~ /from=\"(.*?)\" to=\"(.*\@.*)\" filters=/);
        next 
            unless ($to =~ /^[a-z0-9\@\-\.]+$/i);
        $rcpt{lc $to}++;
    }
}
print " $count records processed\n";

foreach my $from (sort keys %rcpt) {
    print "$from: $rcpt{$from}\n";
}











__END__

# original script:
#!/usr/bin/perl -w

use strict;
use Getopt::Std;
#use Date::Calc qw(Today Now Today_and_Now Add_Delta_Days Delta_Days);

my $root = "/opt/zimbra/log/";
my @servers = qw(dsmdc-mail-imta-01 dsmdc-mail-bxga dsmdc-mail-bxga2);
# our ($opt_d);
my ($year,$month,$day);
my $processday;
my $filename;
my $server;
my $count;
# my ($ip,$from,$to);
my %rcpt;

getopt('d:');

#if ($opt_d) {
#   ($year,$month,$day) = split (/\-/,$opt_d);
#} else {
#   ($year, $month, $day) = Today;
#   ($year,$month,$day) = Add_Delta_Days($year,$month,$day,-1);
#}
#$processday = sprintf("%4d.%2d.%2d",$year,$month,$day);
$processday = $opt_d;
foreach $server (@servers) {
   $filename = $root . $processday . "/" . $server . "/" . "mail.log";
   next if (!(-e $filename));
   print "opening $filename...";
   open(IN,"grep \"IMP: messages\" $filename|") || die "no such file $filename\n";
   $count = 0;
   while (<IN>) {
      $count++;

      if (/smtp=RCPTTO:550/) {
         ($ip,$from,$to) = ($_ =~ /ip=(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}) from=\"(.*?)\" to=\"(.*\@.*)\" filters=/);
         $rcpt{$to}++;
      }
   }
   close IN;
   print " $count records processed\n";
}
open(OUT,">bad_rcpts-$processday.dat");
foreach $from (keys %rcpt) {
   printf (OUT "%s|%d\n",$from,$rcpt{$from});
}
close OUT;
exit 0;
