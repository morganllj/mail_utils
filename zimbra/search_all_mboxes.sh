#!/bin/sh
#
# search_all_mailboxes.sh -s 'user search str' -a 'archive search str' -o <output>

#OPTS=`getopt -o s:a:o:`

#eval set -- "$OPTS"

while getopts ":s:a:o:" opt; do
    case "$opt" in
	s) usrsrch=$OPTARG;;
        a) arcsrch=$OPTARG;;
        o) out=$OPTARG;;
    esac
done

echo "s: $usrsrch"
echo "a: $arcsrch"
echo "o: $out"

if [ 'x' == "x$usrsrch" ] || [ 'x' == "x$out" ]; then
    echo "usage: $0 -s 'user search str' [ -a 'archive search str' ] -o <output>"
    echo
    exit
fi

if [ ! -d $out ]; then
    echo "please mkdir $out"
    exit;
fi

echo starting at `date` | tee -a ${out}.out

for acct in `zmprov -l gaa|grep -v archive|sort -n`; do
  echo -n acct: $acct " " | tee -a ${out}.out
  zmmboxsearch -m $acct -d ${out} -q "<srch str> before:8/25/13" -p 10000000 2>&1 | tee -a ${out}.out
done

if [ 'x' == "x$arcsrch" ]; then
    for acct in `zmprov -l gaa|grep archive|sort -n`; do
	echo -n acct: $acct " " | tee -a ${out}.out
	zmmboxsearch -m $acct -d ${out} -q "<srch str>" -p 10000000 2>&1 | tee -a ${out}.out
    done
fi

echo finished at `date` | tee -a ${out}.out

