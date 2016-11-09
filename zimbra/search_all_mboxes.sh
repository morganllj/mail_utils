#!/bin/sh
#
# search_all_mailboxes.sh -s 'user search str' -a 'archive search str' -o <output>

#OPTS=`getopt -o s:a:o:`

#eval set -- "$OPTS"


print_usage() {
    echo "usage: $0 -s 'user search str'|| -a 'archive search str' -o <output>"
    echo -e "\tyou must specify -s, -a or both"
    echo
    exit
}



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

if [ "X" == "x$usrsrch" ] || [ "x" == "x$arcsrch" ]; then
    print_usage
fi

if [ "x" == "x$out" ]; then
    print_usage
fi

if [ ! -d $out ]; then
    echo "please mkdir $out"
    exit;
fi

echo starting at `date` | tee -a ${out}.out

if [ 'x' != "x$usrsrch" ]; then
    for acct in `zmprov -l gaa|grep -v archive|sort -n`; do
	echo -n acct: $acct " " | tee -a ${out}.out
	zmmboxsearch -m $acct -d ${out} -q "$usrsrch" -p 10000000 2>&1 | tee -a ${out}.out
    done
fi

if [ 'x' != "x$arcsrch" ]; then
    for acct in `zmprov -l gaa|grep archive|sort -n`; do
	echo -n acct: $acct " " | tee -a ${out}.out
	zmmboxsearch -m $acct -d ${out} -q "$arcsrch" -p 10000000 2>&1 | tee -a ${out}.out
    done
fi

echo finished at `date` | tee -a ${out}.out



