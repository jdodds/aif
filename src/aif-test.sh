#!/bin/bash

# make sure you install aif onto the target system so you can use its testing libraries

echo "Aif-test: a 'unit-testing' tool for AIF"
echo "          for a list of available tests: ls -l /usr/share/aif/tests/runtime"
[ "$1" != runtime ] && echo "\$1: type of test to execute (runtime. no support for buildtime yet)" >&2 && exit 1
[ -z "$2" ]         && echo "\$2: name of test to execute" >&2 && exit 1

test_dir="/usr/share/aif/tests/$1/$2"

[ ! -d "$test_dir" ] && echo "No such test found: $test_dir" >&2 && exit 2

echo "Running test $test_dir.  THIS WILL PROBABLY ERASE DATA ON ONE OR MORE OF YOUR HARD DISKS. TO ABORT PRESS CTRL-C WITHIN 10 SECONDS"
sleep 10

# this script should install the system
$test_dir/install.sh || fail=1

# this script does any additional things such as touching files that we should recognize later
$test_dir/setup_test.sh || fail=1

# this script will do the actual testing (network check, recognize filesystems and files, ..)
cp $test_dir/perform_test.sh /mnt/etc/rc.d/perform_test || fail=1

# make sure the test will run on the target system
sed -i 's#^DAEMONS=(\(.*\))#DAEMONS=(\1 perform_test)#' /mnt/etc/rc.conf || fail=1

# and that /etc/issue won't blank the screen
sed -i 's/^H//' /mnt/etc/issue

[ "$fail" == '1' ] && echo "Something failed. will not reboot" >&2 && exit 3

reboot
