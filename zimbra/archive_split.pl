#!/usr/bin/perl -w
#

use strict;

my $total_size = 0;

while (<>) {
  my ($archive,$size) = (split /\s+/, $_)[0,2];
  my $n = (split /\@/, $archive)[0];

  my $length = () = split //, $n, -1;
  # my $length = split //, $n;

  my $d = (split //, $n)[$length-2];

  if ($d =~ /^\d+$/) {
      if ( ($d % 2) == 1) {
	  #    print " y\n"
	  $total_size += $size;
	  # my $acct = `zmprov sa zimbraarchiveaccount=$archive`;
	  my $acct = `ldapsearch -x -w pass -D uid=zimbra,cn=admins,cn=zimbra -LLLb "" -h mldap01.domain.org zimbraarchiveaccount=$archive mail|grep mail:|head -1|awk '{print \$2}'`;
	  chomp $acct;
	  print $acct, " ", $archive, " $size\n";
	  # print $archive, " $size\n";
      }	  # else {
      #    print " n\n";
      #  }
  } else {
      # do nothing
  } 
} 

# print "total_size: $total_size\n";
