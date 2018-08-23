#!/usr/bin/python
#

import sys
import re

auth_failed = {}
auth_failed_count = {}

for line in sys.stdin:
    line = line.rstrip()

    oip = re.search('name=([^;]+);.*oip=(\d+\.\d+\.\d+\.\d+)', line)
    if oip:
        imap = re.search('imap', line, re.IGNORECASE)
        pop = re.search('pop3server', line, re.IGNORECASE)
        if imap or pop:
            continue


        email = oip.group(1).lower()
        ip = oip.group(2)

        authfailed = re.search('authentication failed for \[([^\]]+)\]', line)
        if authfailed:
            print "/"+line+"/"
            user = authfailed.group(1).lower()
            print "user: /"+user+"/"
            print "ip: /"+ip+"/"

            if ip in auth_failed:
                if ip in auth_failed[ip]:
                    auth_failed[ip][user] += 1
                else:
                    auth_failed[ip][user] = 1
            else:
                auth_failed[ip] = {}
                auth_failed[ip][user] = 1

            if ip in auth_failed_count:
                auth_failed_count[ip] += 1
            else:
                auth_failed_count[ip] = 1


            print auth_failed_count
            print

