#!/bin/sh
#
# Delete orphaned Comms Express address books
# Morgan Jones (morgan@morganjones.org)
# 3/11/09
# $Id$

pass='pass';
binddn="cn=Directory\\ Manager"
base="o=msu_ag"
addr_base="o=piserverdb"

# for each top level entry in the address book
for user in `ldapsearch -D "$binddn" -w $pass -Lb $addr_base \
    objectclass=pipstoreroot pipstoreowner|egrep '^pipstoreowner'|\
    awk '{print $2}'`; do 

    # look for a mail user that mactches
    rslt=`ldapsearch -b $base -D "$binddn" -w $pass  \
        "(&(objectclass=inetmailuser)(uid=${user}))" dn |grep -v version`

    # if a user isn't found
    if [ -z "$rslt" ]; then

        # get and delete any associated entries
        for dn in `ldapsearch -r -D "$binddn" -w $pass -b \
            piPStoreOwner=$user,o=ext.domain.org,o=PiServerDb objectclass=\* \
            dn|tail -r`; do

            echo ldapdelete -v -D "$binddn" -w pass $dn
            ldapdelete -v -D "$binddn" -w $pass $dn
        done
    fi
done
