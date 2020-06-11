#!/usr/bin/python
#

import subprocess
import re

#call ("ls -1", shell=True)
#stream=subprocess.Popen("ls -1", shell=True)

#print help(subprocess)

# output=subprocess.Popen("zmlocalconfig -s", shell=True, stdout=subprocess.PIPE)
# out,err = output.communicate();

# for l in out.split("\n"):
#     if re.match(r"\w+\s*=\s*\w", l): 
#         k,v = re.compile("\s+=\s+").split(l)
#         p = "/"+k+"/ /"+v+"/"
#         if k == "zimbra_mysql_user":
#             mysql_user = v
#         elif k == "zimbra_mysql_password":
#             mysql_pass = v

# print mysql_user, mysql_pass


output=subprocess.Popen("mysql -e "select comment from mailbox", shell=True, stdout=subprocess.PIPE)
out,err = output.communicate();

for l in out.split("\n"):
    if re.match(r"\w+\s*=\s*\w", l): 
        k,v = re.compile("\s+=\s+").split(l)
        p = "/"+k+"/ /"+v+"/"
        if k == "zimbra_mysql_user":
            mysql_user = v
        elif k == "zimbra_mysql_password":
            mysql_pass = v

print mysql_user, mysql_pass
