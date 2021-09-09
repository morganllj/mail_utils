#!/bin/sh
#

while [ 1 ]; do for i in 4 5 6; do echo; echo mta0${i}; ssh mta0${i}.philasd.org "sudo su -c /opt/zimbra/libexec/zmqstat"; sleep 3; done; done
