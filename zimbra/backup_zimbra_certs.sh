#!/bin/sh
#
# Morgan Jones (morgan@morganjones.org)
# $Id$
# Description: login to indicated Zimbra hosts and backup all ssl certs.
#    Designed to be used prior to installing new certs on a Zimbra infrastructure in case you need
#    to revert to the old certs.  Zimbra saves certs in so many different places it can be daunting 
#    and error prone to back them all up.  I suggested that you establish password-less ssh with keys
#    before running this.  Otherwise you will be prompted for a password over and over during the backup.
# Instructions: list all your hosts in the 'hosts' variable, 'domain' will be appended to each of $hosts.
#    This will create a directory for each host in the current directory.  If the directory already 
#    exists it will complain and not save anything in it.
#


### site-specific settings
domain="morganjones.org"
hosts="ldap01 ldap02 \
mta01 mta02 mta03 \
store01 store02 store03 store04 store05 store06 store07"


### You shouldn't need to change anything below here.
zimbra_home="/opt/zimbra"
files="\
ssl/zimbra/commercial/commercial.key ssl/zimbra/commercial/commercial.crt ssl/zimbra/commercial/commercial_ca.key \
conf/smtpd.crt conf/smtpd.key \
conf/slapd.crt conf/slapd.key \
conf/nginx.crt conf/nginx.key \
ssl/zimbra/jetty.pkcs12 \
mailboxd/etc/keystore \
/opt/zimbra/conf/ca"

svr_keys="zimbraSSLCertificate zimbraSSLPrivateKey"

for host in $hosts; do
    host=${host}"."${domain}
    echo working on ${host}
    if [ ! -d $host ]; then
        mkdir $host
        for f in $files; do
            /bin/echo -n "${f}: "
            exists=`ssh $host "sudo ls ${zimbra_home}/$f 2>&1 |egrep -v 'No such' || echo"`
            echo $exists
            if [ x"$exists" != "x" ]; then
                ssh $host "cd $zimbra_home && sudo tar cf - $f" | (cd $host && tar ixf -)
            fi
        done
    else
        echo directory $host already exists.. skipping
    fi
    echo
done
 
