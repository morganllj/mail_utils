#!/bin/sh
#

if [ `whoami` != "root" ]; then
    echo "run as root!"
    exit
fi

ogc_num=15

u=$1
echo $u

echo "starting at `date`"
echo; echo "working on $u: "
archive=`sudo su - zimbra -c "zmprov ga $u zimbraarchiveaccount|grep -i archive"|awk '{print $2}'`
last_date=`sudo su - zimbra -c "/usr/local/bin/last_message_date.pl -m $archive"`
echo $last_date

dir=/var/mail_log/discover/xmbox_ogc${ogc_num}_$u
if [ -d $dir ]; then
    echo "$dir exists! remove it first!"
    exit
fi
mkdir $dir

cmd="/usr/local/zmmboxsearchx-20100625/bin/zmmboxsearchx --query in:/Inbox --limit 0 --dir $dir --account $archive"
echo $cmd
$cmd
cmd2="/usr/local/zmmboxsearchx-20100625/bin/zmmboxsearchx --query "before:${last_date}" --limit 0 --dir $dir --account $u"
echo $cmd2
$cmd2

echo
echo "finished at `date`"
