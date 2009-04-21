#!/bin/sh
#
# Though designed to be general purpose this is currently set up for
# Zimbra's ldap.  It wouldn't be hard to generalize or customize for a
# different ldap.

# directory containing utilities this script will use.. notably
# mbox_migrate.pl
mig_dir="/home/morgan/zimbra_migration"

# location of mbox files.  Usually /var/mail
var_mail="/var/mail2/morgan_combined"

# zimbra ldap admin password
z_admin_pass="pass"
# password all user accounts are set to
common_user_pass="pass"

if [ ! -z "$1" ]; then
    echo "1: $1";
fi


echo "starting migration at `date`"
echo
if [ -z "$1" ]; then
    echo "migrating $1 from ${var_mail}"
else
    echo "migrating from ${var_mail}"
fi

for l in `echo $1|perl -e "while (<>) {print join (' ', split /,/);}"`; do
    echo ${l}

    for path in `ls -1 ${var_mail}/${l}*`; do
        # lookup the user's store to bypass the proxy.
        #   This may not be strictly necessary anymore..

	user=`basename $path`;

        host=`/opt/csw/bin/ldapsearch -xLL -w "${z_admin_pass}" -h dmldap01.domain.org -D cn=config -Lb dc=domain,dc=org  uid=$user zimbramailhost|grep -i zimbramailhost|awk '{print $2}'`

        echo
        echo ${mig_dir}/mbox_migrate.pl  -m $path -h $host -u $user -w "${common_user_pass}" 
        ${mig_dir}/mbox_migrate.pl  -m $path -h $host -u $user -w "${common_user_pass}" 
    done
done

echo
echo -n "finished migration at `date`"
