#!/bin/sh
#

out=/var/mail_log/zmmboxsearch_160826

echo starting at `date` | tee -a ${out}.out

for acct in `zmprov -l gaa|grep -v archive|sort -n`; do
  echo -n acct: $acct " " | tee -a ${out}.out
  zmmboxsearch -m $acct -d ${out} -q "from:acct@comcast.net or to:acct@comcast.net or from:acct1@gmail.com or to:acct1@gmail.com or from:acc2@gmail.com or to:acct2@gmail.com before:8/25/13" -p 10000000 2>&1 | tee -a ${out}.out
done

for acct in `zmprov -l gaa|grep archive|sort -n`; do
  echo -n acct: $acct " " | tee -a ${out}.out
  zmmboxsearch -m $acct -d ${out} -q "from:acct@comcast.net or to:acct@comcast.net or from:acct1@gmail.com or to:acct1@gmail.com or from:acc2@gmail.com or to:acct2@gmail.com" -p 10000000 2>&1 | tee -a ${out}.out
done

echo finished at `date` | tee -a ${out}.out

