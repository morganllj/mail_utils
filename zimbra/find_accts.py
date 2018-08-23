#!/usr/bin/env python
#

import fileinput
import mysql.connector

cnx = mysql.connector.connect(user="zimbra", password="pass",
                                  host="localhost", database="zimbra",
                                  port="7306")
query = ("SELECT comment FROM zimbra.mailbox"
             "WHERE id = %s")
cursor = cnx.cursor()

for filename in fileinput.input():
    print "working on ", filename
    id = filename.split('/')[5]
    print "id: ", id
    cursor.execute(query, (id))
#    for (address) in cursor:
#        print id, " ", address
