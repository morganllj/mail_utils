#!/usr/bin/perl -w
#

while (<>) {
    if (/dsn=/i) {
        my ($err) = /\,\s*dsn=([^\,]+)\,/;
        my ($rcpt) = /\s*to=<([^>]+)>/;
        print "$err, $rcpt\n";
    }
}
