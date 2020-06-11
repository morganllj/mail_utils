#!/bin/sh
#
# specific to one site, put here as a placeholder

while [ 1 ]; do for i in {1..12} ; do echo -n "mx$i"; ssh mx${i}-mgmt.domain.net "workqueue status" 2>&1 |grep Messages|perl -p -e 's/Messages:\s+/ /'; done; done
