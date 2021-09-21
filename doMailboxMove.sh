#!/bin/sh
#

for i in `zmprov gqu mail07.domain.org |cut -d@ -f1|egrep '.*[789]$'|head -30|tail -20`; do echo $i;  zxsuite --progress hsm doMailboxMove mail08.domain.org accounts $i@domain.org.archive stages data,account checkDigest false;zxsuite hsm doPurgeMailboxes all ignore_retention true; zxsuite hsm runBulkDelete; done | tee -a /tmp/210919_mv.out
