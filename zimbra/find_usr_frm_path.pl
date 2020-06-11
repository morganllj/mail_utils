#!/usr/local/bin/perl -w
#


for my $i in `echo "show databases;" | mysql|grep mboxgroup`; do echo $i; echo "select id from mail_item where index_id=377463;" |mysql $i; done
