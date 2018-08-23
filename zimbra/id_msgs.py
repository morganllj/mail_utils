#!/usr/bin/python

import fileinput

for line in fileinput.input():
    line = line.rstrip()
    print line
    s = line.split("/")
    print len(s)
    if len(s) == 9:
        print len(s)
        volid, acctid, message, h  = s[4:7]
        print volid, " ", acctid, " ", h
    elif len(s)==7:
        # do nothing
        pass
    else:
        print "malformed line: ", line
        
