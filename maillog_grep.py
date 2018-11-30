#!/usr/bin/env python3
#

import sys
import getopt
import re

file=None


def print_usage():
    print ("usage: "+sys.argv[0]+" -f <filename>")
    exit()

opts, args = getopt.getopt(sys.argv[1:], "f:")

for opt, arg in opts:
    if opt in ('-f'):
        file = arg

if file is None:
    print_usage()

r_obj = re.compile(r'mta\d\d postfix[^:]+: ([^:]+): (from|to)=<([^>]+)>')

q_ids = {}

for line in open(file):
    line = line.rstrip()
    mo = re.search(r_obj, line)
    if mo:
#        print ("matched: /"+line+"/")
#        print (mo.group(1) + " " + mo.group(2) + " " + mo.group(3))
        if mo.group(1) not in q_ids.keys():
            q_ids[mo.group(1)] = {}
        q_ids[mo.group(1)][mo.group(2)] = mo.group(3)


print (q_ids)
