#!/usr/bin/sh
#

mig_dir="/home/morgan/zimbra_migration"
if [ -z "$1" ]; then
    var_mail="/var/mail2/morgans_s"
else
    var_mail="/var/mail2/${1}"
fi

z_admin_pass="pass"
common_user_pass="pass"


echo "starting migration at `date`"
echo
echo "migrating from ${var_mail}"

for user in `ls -1 ${var_mail}`; do 
    # lookup the user's store to bypass the proxy.
    #   This may not be strictly necessary anymore..
    host=`/opt/csw/bin/ldapsearch -xLL -w "${z_admin_pass}" -h dmldap01.domain.org -D cn=config -Lb dc=domain,dc=org  uid=$user zimbramailhost|grep -i zimbramailhost|awk '{print $2}'`

    echo
    echo ${mig_dir}/mbox_migrate.pl  -m ${var_mail}/$user -h $host -u $user -w "${common_user_pass}" 
    ${mig_dir}/mbox_migrate.pl  -m ${var_mail}/$user -h $host -u $user -w "${common_user_pass}" 

done

echo
echo -n "finished migration at `date`"
