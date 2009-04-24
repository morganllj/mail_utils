#!/bin/sh
#
# Morgan Jones (morgan@morganjones.org)
# $Id$

bin_path=ldap2zimbra
log_path=ldap2zimbra/log
log=${log_path}/ldap2zimbra_`date +%y%m%d.%H:%M:%S`
mail_to=ldap-admin@domain.org

# l2z_cmd="${bin_path}/ldap2zimbra.pl -e $*"
l2z_cmd="${bin_path}/ldap2zimbra.pl -n -e $*"
# $l2z_cmd > ${log} 2>&1
# mail -s "ldap2zimbra output" ${mail_to} < ${log}
echo "** output logged to ${log}"
echo
echo $l2z_cmd
$l2z_cmd 2>&1 | tee $log

