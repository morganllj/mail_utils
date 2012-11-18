#!/bin/sh
#

if [ `whoami` != "root" ]; then
    echo "run as root!"
fi

users=""

echo "starting at `date`"
echo

rm -rf /var/tmp/xmbox_ogc14_*

echo "checking for directories in /var/tmp..."
for u in $users; do
    dir=/var/tmp/xmbox_ogc${ogc_num}_$u
    if [ -d $dir ]; then
	echo "$dir exists! remove it first!"
	exit
    fi
done

echo -n "finding ogc number: "
ogc_num=`su - zimbra -c "zmprov -l gaa|egrep '^_ogc'"|awk -F_ '{print $2}'|sed 's/ogc//'|sort -un|tail -1`
ogc_num=`expr $ogc_num + 1`
echo "ogc number: $ogc_num"

for u in $users; do
    echo; echo "working on $u: "
    archive=`sudo su - zimbra -c "zmprov ga $u zimbraarchiveaccount|grep -i archive"|awk '{print $2}'`
#    echo -n "$archive "
    last_date=`sudo su - zimbra -c "/usr/local/bin/last_message_date.pl -m $u"`
#    echo $last_date

    dir=/var/tmp/xmbox_ogc${ogc_num}_$u
    mkdir $dir

    cmd="/usr/local/zmmboxsearchx-20100625/bin/zmmboxsearchx --query in:/Inbox --limit 0 --dir $dir --account $archive"
    $cmd
    cmd2="/usr/local/zmmboxsearchx-20100625/bin/zmmboxsearchx --query "after:${last_date}" --limit 0 --dir $dir --account $u"
    $cmd2
done

echo
echo "finished at `date`"
