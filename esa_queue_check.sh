#!/bin/sh
#

while [ 1 ]; do for i in 1 2 3 4 5 6 7 8 9 10 11 12 14 15 16 17; do /bin/echo -n "$i "; ssh mx${i}-mgmt.philasd.net "workqueue status" 2>&1 |grep Messages |awk '{print $2}'; ssh mx${i}-mgmt.philasd.net "status" |grep System|cut -d ':' -f2|perl -p -s -e 's/^\s+//'; done; done
