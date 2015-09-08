#!/bin/sh
#

p=pass
h=imap.domain.org
au=admin_user

echo starting at `date`
for u in `cat ${1}`; do
    echo; echo ${u}:
    c="imapsync --folder Junk --maxage 4 --delete \
        --prefix1 Junk  --ssl1 --host1 ${h} --authuser1 ${au} --user1 ${u} --password1 ${p}\
        --prefix2 INBOX --ssl2 --host2 ${h} --authuser2 ${au} --user2 ${u} --password2 ${p}"
    echo $c
    $c
done
echo finished at `date`
