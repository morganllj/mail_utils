#! /bin/bash

repos=~/centos_repos

ro=0
while getopts nr: opt
do
    case ${opt} in
	n) ro=1
	   ;;
	r) repos=$OPTARG
	   ;;
    esac
done

dir1=/var/cache/yum
dir2=/var/cache/yum/x86_64/6
suf=base/mirrorlist.txt

# check that the repos are in place.
#   If they are not the script will expect to find them in ~/centos_repos
if [ ! -f /etc/yum.repos.d/Cent*-Base.repo ]; then
    if [ ! -f ${repos}/Cent*-Base.repo ]; then
        echo "Cent*-Base.repo not in /etc/yum.repos.d or in ~/centos_repos, exiting!"
	exit 1
    else
	#echo "copying repos to /etc/yum.repos.d"
	echo cp ${repos}/* /etc/yum.repos.d
	if [ $ro -ne 1 ]; then
            cp ${repos}/* /etc/yum.repos.d
	fi
    fi
fi

# /var/cache/yum/*/mirrorlist.txt is preferred.
#   otherwise look in /var/cache/yum/x86_64/6
if [ -f ${dir1}/${suf} ]; then
  dir=$dir1
elif [ -f ${dir2}/${suf} ]; then
  dir=$dir2
else
  echo "neither ${dir1}/${suf} nor ${dir2}/${suf} exist!"
  exit 1
fi

for i in base extras updates; do
    if [ ! `grep vault.centos ${dir}/$i/mirrorlist.txt` ]; then
	echo "echo https://vault.centos.org/6.10/ >> ${dir}/$i/mirrorlist.txt"
	if [ $ro -ne 1 ]; then
	    echo "https://vault.centos.org/6.10/" >> ${dir}/$i/mirrorlist.txt
	fi
    fi
done

# update /etc/yum.repos.d repos
# this is safe to run over and over as it won't make the same change twice
    echo sed -i -e 's|^#*baseurl.*$|baseurl=http://vault.centos.org/6.10/centosplus/$basearch/|g' -e 's/^mirrorlist/#mirrorlist/g' /etc/yum.repos.d/Cent*-Base.repo
if [ $ro -ne 1 ]; then
    sed -i -e 's|^#*baseurl.*$|baseurl=http://vault.centos.org/6.10/centosplus/$basearch/|g' -e 's/^mirrorlist/#mirrorlist/g' /etc/yum.repos.d/Cent*-Base.repo
fi
