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

# def check_qids(q,a,r,ft,l):
#     qid  = q
#     in_addr = a
#     r_obj = r
#     in_fmto = ft
#     in_line = l

#     if in_addr is not None:
#         # the user passed both from and to: look for the complementing from/to and print it if so
#         if qid in qids.keys():
#             matched = 0
#             for v in qids[qid]:
#                  mo = re.search(r_obj, in_line)
#                  qid = mo.group(1)
#                  fmto = mo.group(2)
#                  addr = mo.group(3)
#                  if addr.lower() == in_addr.lower() and fmto.lower() == in_fmto.lower():
#                      matched = 1
#             if matched:
#                 # cycle through, print, and delete from qids
#                 for v in qids[qid]:
#                     print (v)
#                     del qids[qid]
#                 # and print the current line
#                 print (in_line)
#                 # print all future occurrences of this qid
#                 #qids_to_print.append(qid)
#                 add_to_qids_to_print(qid)
#                 # tell the caller we printed
#                 return 1
#     else:
#         # the user only passed from or to, print everything we have for the qid so far
#         if qid in qids.keys():
#             for v in qids[qid]:
#                 print (v)
#                 del qids[k]
#         print ("check_qids, else: "+in_line)

# #        qids_to_print.append(qid)
#         add_to_qids_to_print(qid)
#         return 1
#     return 0

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
        
print ("file: "+file)
if to is not None:
    print ("to: "+to)
if fm is not None:
    print ("from: "+fm)

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

#        print ("\n"+qid, fmto, addr)

        if qid not in qids.keys():
            qids[qid] = []
        qids[qid].append(line)
        
        if ((fmto.lower() == "from" and fm is not None and fm.lower() == addr.lower()) or
            (fmto.lower() == "to" and to is not None and to.lower() == addr.lower())):
            if ((fmto.lower() == "from" and to is not None) or
                (fmto.lower() == "to"   and fm is not None)):

                # duplicated from below!
                if in_qids_to_print(qid):
                    for l in qids[qid]:
                        print (l)
                    del qids[qid]
                else: # not in qids_to_print, decide if this one is both from and to the right addrs
                    matched = 0
                    for l in qids[qid]:
                        mo2 = re.search(r_obj, line)
                        if mo2:
                            fmto2 = mo2.group(2)
                            addr2 = mo2.group(3)
                            if ((fmto.lower() == "from" and fmto2.lower() == "to") or 
                                (fmto.lower() == "to" and fmto2.lower() == "from")):
                                matched = 1
                    if matched:
                        # duplicate!
                        for l in qids[qid]:
                            print (l)
                        del qids[qid]

            else:
                add_to_qids_to_print(qid)
                for l in qids[qid]:
                    print (l)
                del qids[qid]
        else:
            # there's no match but if the qid is one we need to print, print it
            if in_qids_to_print(qid):
                for l in qids[qid]:
                    print (l)
                del qids[qid]
                
        

