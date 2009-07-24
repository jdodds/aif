#!/bin/bash

source /usr/share/aif/tests/lib/framework-runtime

aiftest swap 48
aiftest lvm-lv cryptpool cryptroot '800.00 MB'
aiftest mount '/dev/sda3 on / type ext4 (rw)'
aiftest mount '/dev/sda4 on /home type ext3 (rw)'
for i in /etc/ / /root/ /home/ /var/
do
	aiftest file "$i"test_file
done
aiftest file /home/important-userdata
aiftest ping 2 archlinux.org

aiftest-done
