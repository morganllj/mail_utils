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

print ("file: "+file)

f = open(file, "r")

if f.mode != 'r':
    print ("unable to open "+file+".  Exiting")

r_obj = re.compile(r'mta\d\d postfix\/smtp')

for line in f.readlines():
    print ("top of for")
    line = line.rstrip()
    mo = re.search(r_obj, line)
    if mo:
        print ("matched: /"+line+"/")

f.close()
