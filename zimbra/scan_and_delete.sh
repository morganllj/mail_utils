#!/bin/bash -x
#
#

#zmprov --ldap gaa > /tmp/acccountsList.txt
#echo wsgalloway >/tmp/acccountsList.txt

#KILL_TEXT="king for"
#KILL_TEXT=Undelivered
#KILL_TEXT=Delivery
#KILL_TEXT="Subject: Another Screw Up"
#KILL_TEXT="Subject: Warning: could not send message"
#KILL_TEXT="From: Mail Delivery Subsystem" 
#KILL_TEXT="From: Admin Help Desk"
#KILL_TEXT="Subject: You Won 800,000 Euro"
#KILL_TEXT="Subject: Your Mailbox Has Exceeded It Storage Limit"
#KILL_TEXT="Subject: Backup on "
#KILL_TEXT="Subject: Think this is Spam"
#KILL_TEXT="Subject: E-mail On-Line Winner"
#KILL_TEXT="Subject: Account Verification"
#KILL_TEXT="Subject: Unauthorized Access"
KILL_TEXT="Subject: Title III updates"
#KILL_TEXT="From: BILLY DAVIS"

for acct in `cat /tmp/acccountsList.txt` ; do
THEACCOUNT=$acct

#KILL_TEXT=king for

#THEDATE=$(date --date='30 days ago' +%m/%d/%y)
#THEFOLDER="Inbox"

# (before:$THEDATE)
touch /tmp/deleteOldMessagesList.txt
#for i in `zmmailbox -z -m $THEACCOUNT search -l 30 "in:Inbox" | grep $KILL_TEXT | sed -e "s/^\s\s*//" | sed -e "s/\s\s*/ /g" | cut -d" " -f2`
for i in `zmmailbox -z -m $THEACCOUNT search -l 55 -t message "$KILL_TEXT" | sed -e "s/^\s\s*//" | sed -e "s/\s\s*/ /g" | cut -d" " -f2`
  do
  	if [[ $i =~ [-]{1} ]]
	then
		MESSAGEID=${i#-}
#    	zmmailbox -z -m $THEACCOUNT dm ${i#-}
	    echo "deleteMessage $MESSAGEID" >> /tmp/deleteOldMessagesList.txt
	else
#    	zmmailbox -z -m $THEACCOUNT dm ${i#-}
	    echo "deleteConversation $i" >> /tmp/deleteOldMessagesList.txt
	fi
done

#rm -f /tmp/deleteOldMessagesList.txt

done
#rm -f /tmp/acccountsList.txt
