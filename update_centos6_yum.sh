#! /bin/bash

dir1=/var/cache/yum/x86_64/6
dir2=/var/cache/yum

if [ -d $dir1 ]; then
  dir=$dir1
else
  dir=$dir2
fi 

for i in base extras updates; do 
  echo ${dir}/$i/mirrorlist.txt
  echo "https://vault.centos.org/6.10/" >> /var/cache/yum/x86_64/6/$i/mirrorlist.txt
done

sed -i -e 's|^#*baseurl.*$|baseurl=http://vault.centos.org/6.10/centosplus/$basearch/|g' -e 's/^mirrorlist/#mirrorlist/g' /etc/yum.repos.d/Cent*-Base.repo
