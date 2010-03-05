#!/bin/sh

# sda1 boot, sda2 will be swap, sda3 /, sda4 which will contain the "existing filesystem of the user" with "important data" on it.
sfdisk -D /dev/sda -uM << EOF
,50,,*
,20,S
,800,
,,
EOF
mke2fs -j /dev/sda4
mkdir /tmp/aif-test-mount
mount /dev/sda4 /tmp/aif-test-mount
touch /tmp/aif-test-mount/important-userdata
umount /tmp/aif-test-mount
aif -p automatic -c /usr/share/aif/tests/runtime/automatic-reuse-fs-sda/profile -d