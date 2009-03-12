#!/bin/sh
#
# Delete orphaned Comms Express address books
# Morgan Jones (morgan@morganjones.org)
# 3/11/09
# $Id$

pass='Dpw34Sf.'
binddn="cn=Directory Manager"
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
        echo "$user"

        # get and delete any associated entries
        for dn in `ldapsearch -r -D "$binddn" -w $pass -b \
            piPStoreOwner=$user,o=ext.domain.org,o=PiServerDb objectclass=\* \
            dn|tail -r`; do

            echo ldapdelete -v -D "$binddn" -w 'pas' $dn
        done
    fi
done
