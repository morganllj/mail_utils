#!/bin/sh
#

domain="domain.org"
# hosts="dmldap01 \
# dmta01 \
# dmail01 dmail02"

hosts="mldap01 mldap02 \
mta01 mta02 mta03 \
mail01 mail02 mail03 mail04 mail05 mail06 mail07"

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
 
