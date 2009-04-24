#!/bin/sh
#
# Morgan Jones (morgan@morganjones.org)
# $Id$

bin_path=/usr/local/sbin
log_path=/home/ldap2zimbra
log=${log_path}/ldap2zimbra_`date +%y%m%d.%H:%M:%S`
mail_to=ldap-admin@domain.org

# ${bin_path}/ldap2zimbra.pl > ${log} 2>&1
l2z_cmd="${bin_path}/ldap2zimbra.pl -e $*"
$l2z_cmd > ${log} 2>&1
mail -s "ldap2zimbra output" ${mail_to} < ${log}
