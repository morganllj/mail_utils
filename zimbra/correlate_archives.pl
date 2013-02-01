#!/usr/bin/perl -w
#
# correlate enterprise ldap accounts with their corresponding zimbra archive accounts

use strict;

my $accts = `su - zimbra -c "zmprov sa '(&(!(zimbracosid=249ef618-29d0-465e-86ae-3eb407b65540))(!(zimbracosid=d94f6c22-b802-4bcf-acea-03b81c5f8a8c))(mail=*domain.org.archive))'"`;

  for my $acct (split /\s+/, $accts) {

      print "$acct;";

      my $mail = `su - zimbra -c "zmprov sa zimbraarchiveaccount=$acct"`;
      chomp $mail;

      if ($mail !~ /^\s*$/) {

	  my $uid = (split /@/, $mail)[0];
	  
#	  print "uid: $uid\n";

	  my $srch = `ldapsearch -x -w 'pass' -H ldaps://ldap01.domain.net -D uid=morgan,ou=employees,dc=domain,dc=org -LLLb dc=domain,dc=org uid=$uid givenname sn orgtitledescription orghomeorgcd orghomeorg`;

	  my ($givenname, $sn, $title, $homeorgcd, $homeorg);
	  $givenname = $sn = $title = $homeorgcd = $homeorg = $srch;

#	  print "srch: /$srch/\n";

	  $givenname =~ /givenname:\s+([^\n]+)\n/i;
	  $givenname = $1;

	  $sn =~ /sn:\s+([^\n]+)\n/i;
	  $sn = $1;

	  $title =~ /orgtitledescription:\s+([^\n]+)\n/i;
	  $title = $1;

	  $homeorgcd =~ /orghomeorgcd:\s+([^\n]+)\n/i;
	  $homeorgcd = $1;

	  $homeorg =~ /orghomeorg:\s+([^\n]+)\n/i;
	  $homeorg = $1;

#	  print "$givenname;$sn;$title;$homeorgcd;$homeorg\n";


	  if (defined $givenname) {
	      print "$givenname;";
	  } else {
	      print ";";
	  }

	  if (defined $sn) {
	      print "$sn;";
	  } else {
	      	      print ";";
	  }
	  
	  if (defined $title) {
	      print "$title;";
	  } else {
	      	      print ";";
	  }

	  if (defined $homeorgcd) {
	      	  print "$homeorgcd;";
	  } else {
	      	      print ";";
	  }

	  if (defined $homeorg) {
	      print "$homeorg";
	  } else {
	      	      print ";";
	  } 
	  print "\n";
	  
      } else {
	  print ";;;;\n";
      }


  }
