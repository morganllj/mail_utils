#!/usr/bin/perl -w
#
# usage: cat 72custom-schema.ldif | ./sort_schema_attrs.pl

use strict;

my $l = <>;
$l =s/\n\s//g;

my (@lines, @objectclasses);

while (split (/\n/, $l)) {
    if (/^#/) {
    } elsif (/^attributetypes/i) {
	($n) = /NAME \'([^\']+)\'/;
    } elsif (/objectclasses/i) {
    } else {
	print "unrecognized line: /$_/\n";
    }
}

