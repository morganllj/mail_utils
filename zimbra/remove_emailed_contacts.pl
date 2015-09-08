#!/usr/bin/perl -w
#

use strict;

$| = 1;

# too limited:
#for i in `zmprov -l gaa |grep -v archive`; do echo $i ;  zmmailbox -z -m $i gact | perl -n -0000 -e 'if (/Folder: \/Emailed Contacts/ && (/superintendent@/i || /donotreply@/i)) {print "/$_/\n";}'; done| tee /var/tmp/emailed_contacts_purge.out

# the below was used with some shell manipulation:
# ./remove_emailed_contacts.pl | tee /var/tmp/remove_emailed_contacts.out
# strings /var/tmp/remove_emailed_contacts.out|egrep -A1 '  email:.*@domain|  email:.*@domain1'> /var/tmp/contacts_to_delete.out
# IFS=$'\n'; for i in `grep zmmailbox /var/tmp/contacts_to_delete.out`; do echo echo $i; echo $i;  done 2>&1 | tee /var/tmp/delete_contacts.sh
# add '#!/bin/sh' to the top of ./delete_contacts.sh
# ./delete_contacts.sh 2>&1 | tee /var/tmp/delete_contacts.out 


for my $user (`zmprov -l gaa |grep -v archive`) {
    chomp $user;

    my $print_user = 1;

    open GACT, "zmmailbox -z -m $user gact 2>&1|";
    $/="";

    while (<GACT>) {
	if ((/Folder: \/Emailed Contacts/ && (/email: superintendent\@domain/i || /email: donotreply\@domain/i))) {
	    if ($print_user) {
		print $user, "\n";
		$print_user = 0;
	    }
	    print "$_\n";

	    my ($id) = /Id: (\d+)/;
	    
	    print "zmmailbox -z -m $user dct $id\n";

	}

	if (/ERROR/) {
	    if ($print_user) {
		print $user, "\n";
		$print_user = 0;
	    }
	    print "$_\n";

	}
    }
}
