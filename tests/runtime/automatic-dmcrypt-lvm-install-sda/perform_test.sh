#!/bin/bash

source /usr/share/aif/tests/lib/framework-runtime

aiftest swap 19
aiftest lvm-lv mypool root '800.00 MB'
aiftest mount '/dev/mapper/mypool-rootcrypt on / type xfs (rw)'
for i in /etc/ / /root/ /home/ /var/
do
	aiftest file "$i"test_file
done
aiftest file /usr/bin/ssh
aiftest nofile /sbin/mkfs.reiserfs
aiftest nopackage sudo
aiftest ping 2 archlinux.org

aiftest-done
