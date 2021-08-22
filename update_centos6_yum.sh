#! /bin/bash

echo "https://vault.centos.org/6.10/" >> /var/cache/yum/base/mirrorlist.txt
echo "https://vault.centos.org/6.10/" >> /var/cache/yum/extras/mirrorlist.txt
echo "https://vault.centos.org/6.10/" >> /var/cache/yum/updates/mirrorlist.txt

sed -i -e 's|^#*baseurl.*$|baseurl=http://vault.centos.org/6.10/centosplus/$basearch/|g' -e 's/^mirrorlist/#mirrorlist/g' /etc/yum.repos.d/Cent*-Base.repo
