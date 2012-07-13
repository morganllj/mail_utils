#!/bin/sh
#
# Morgan Jones (morgan@morganjones.org)
# $Id$

# base_path=ldap2zimbra-dmail01
base_path=`echo $0 | awk -F/ '{for (i=1;i<NF;i++){printf $i "/"}}' | sed 's/\/$//'`
log_path=${base_path}/log
log=${log_path}/ldap2zimbra_`date +%y%m%d.%H:%M:%S`

l2z_cmd="${base_path}/ldap2zimbra.pl $*"
echo "** output logged to ${log}"
echo
echo $l2z_cmd
$l2z_cmd 2>&1 | tee $log

