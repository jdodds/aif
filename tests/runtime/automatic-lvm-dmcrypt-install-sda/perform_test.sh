#!/bin/sh


free -m | grep 'Swap:.*20.*' || echo 'SWAP CHECK FAILED'

lvdisplay | grep -A 5 'LV Name.*/dev/mapper/cryptpool-cryptroot' | grep available            || echo 'LV ROOT CHECK FAILED'
lvdisplay | grep -A 7 'LV Name.*/dev/mapper/cryptpool-cryptroot' | grep 'LV Size.*800.00 MB' || echo 'LV ROOT CHECK FAILED'

mount | grep '/dev/mapper/cryptpool-cryptroot on / type xfs (rw)' || echo 'ROOT FS CHECK FAILED'
mount | grep '/dev/mapper/cryptpool-crypthome on /home type xfs (rw)' || echo 'HOME FS CHECK FAILED'


for i in /etc/ / /root/ /home/ /var/
do
	[ -f "$i/test_file" ] || echo "TEST FAILED. NO FILE $i/test_file"
done

[ -x /usr/bin/ssh ] || echo 'PACKAGE INSTALLATION CHECK SSH FAILED'
[ -f /sbin/mkfs.reiserfs ] && echo 'PACKAGE INSTALLATION CHECK REISERFS FAILED'
ping -c 2 archlinux.org || echo 'PING CHECK FAILED'
