#!/bin/sh
#
# site specific, placeholder for now

while [ 1 ]; do; for i in 4 5 6; do echo; echo mta0$i; ssh mta0$i.domain.org "sudo /opt/zimbra/libexec/zmqstat"|egrep 'deferred|active|incoming'; sleep 10; done; done
