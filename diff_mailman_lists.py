#!/usr/bin/python3 -u
#

import subprocess
import re
import os

mailman = "/opt/mailman-scripts/sdp_mailman_cf"

cmd1_s = "ls -1 " + mailman + "/list_cfgs"
cmd2_s = "ls -1 " + mailman + "/list_members"

cmd1 = re.split('\s+', cmd1_s)
cmd2 = re.split('\s+', cmd2_s)

p1 = subprocess.Popen(cmd1,
      stdout=subprocess.PIPE,
      stderr=subprocess.PIPE)
stdout,stderr = p1.communicate()
#print (stdout.decode('utf-8'), stderr.decode('utf-8'))

cfgs = re.split('\s+', stdout.decode('utf-8'))

# print (cfgs);

# for c in cfgs:
#     print ("c:", c)

p2 = subprocess.Popen(cmd2,
      stdout = subprocess.PIPE,
      stderr = subprocess.PIPE)
stdout,stderr = p2.communicate()
#print (stdout.decode('utf-8'), stderr.decode('utf-8'))

mdict = {}

mbrs = re.split('\s+', stdout.decode('utf-8'))
for c in cfgs:
    l = re.sub('.cfg', '', c)
    mdict[l] = 1

for m in mbrs:
    l = re.sub('.txt', '', m)
    del mdict[l]
    
#print(mdict)

for m in mdict:
    print (m)

