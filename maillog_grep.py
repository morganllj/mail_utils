#!/usr/bin/env python3
#

import sys
import getopt
import re

fm=to=file=None


def print_usage():
    print ("usage: "+sys.argv[0]+" (-f <from>|-t <to>) -m <maillog>")
    exit()

def add_to_qids_to_print(q):
    qid = q

    matched = 0
    for v in qids_to_print:
        if v == qid:
            matched = 1
    if not matched:
        qids_to_print.append(qid)

def in_qids_to_print(q):
    qid = q
    
    matched = 0
    for v in qids_to_print:
        if v == qid:
            matched = 1
    if matched:
        return 1
    return 0


####### main
opts, args = getopt.getopt(sys.argv[1:], "f:t:m:")

for opt, arg in opts:
    if opt in ('-m'):
        file = arg
    elif opt in ('-f'):
        fm = arg
    elif opt in ('-t'):
        to = arg
    else:
        print_usage()

if file is None:
    print_usage()

if fm is None and to is None:
   print_usage()

# this is too specific if I want all log lines, it will get just froms and tos which might be enough.
r_obj = re.compile(r'mta\d\d postfix[^:]+: ([^:]+): (from|to)=<([^>]+)>')
qids = {}
qids_to_print = []

for line in open(file):
    line = line.rstrip()

    printed = 0
    mo = re.search(r_obj, line)
    if mo:
        qid = mo.group(1)
        fmto = mo.group(2)
        addr = mo.group(3)

        # all lines go in qids, qid as index
        if qid not in qids.keys():
            qids[qid] = []
        qids[qid].append(line)
        
        if ((fmto.lower() == "from" and fm is not None and fm.lower() == addr.lower()) or
            (fmto.lower() == "to" and to is not None and to.lower() == addr.lower())):
            # The current line matches either from or two provided on the cli
            
            if ((fmto.lower() == "from" and to is not None) or
                (fmto.lower() == "to"   and fm is not None)):
                # both a front and to were provided on the cli
                # cycle through qids[qid], if both a from and to match print what's there add qid to qids_to_print
                for l in qids[qid]:
                     mo2 = re.search(r_obj, l)
                     if mo2:
                         fmto2 = mo2.group(2)
                         addr2 = mo2.group(3)
                         if ((fmto.lower() == "from" and fmto2.lower() == "to"   and to.lower() == addr2.lower()) or
                             (fmto.lower() == "to"   and fmto2.lower() == "from" and fm.lower() == addr2.lower())):
                            # we have a matching from/to combo: print it!
                            add_to_qids_to_print(qid)
            else:
                # only a from or to was specified on the cli: print it!
                add_to_qids_to_print(qid)

        # catch-all: if qid is in qids_to_print, print everything we have for it and remove it from qids
        if in_qids_to_print(qid):
            for l in qids[qid]:
                print (l)
            del qids[qid]
                
        

