#!/bin/bash

source /usr/share/aif/tests/lib/framework-runtime

aiftest swap 19
aiftest lvm-lv cryptpool cryptroot '800.00 MB'
aiftest mount '/dev/mapper/cryptpool-cryptroot on / type xfs (rw)'
aiftest mount '/dev/mapper/cryptpool-crypthome on /home type xfs (rw)'
for i in /etc/ / /root/ /home/ /var/
do
	aiftest file "$i"test_file
done
aiftest file /usr/bin/ssh
aiftest nofile /sbin/mkfs.reiserfs
aiftest nopackage sudo
aiftest ping 2 archlinux.org

aiftest-done
