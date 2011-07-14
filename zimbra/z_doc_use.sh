#!/bin/sh
# z_doc_use.sh
# 7/14/11
# Morgan Jones (morgan@morganjones.org)
# get a count of Document and Briefcase use in Zimbra.  Tested on 6.0.x
#
# run as zimbra!

folders="/Briefcase /Notebook"

for u in `zmprov -l gaa|grep -v archive` ; do 
    echo -n "$u "
    for folder in $folders; do
	i=0
	for n in `zmmailbox -z -m $u gf $folder | \
	    grep -i itemcount | cut -d: -f 2 | cut -d, -f1` ; do 
	    i=`expr $i + $n`; 
	done; 
	echo -n "$i "
    done
    echo
done
