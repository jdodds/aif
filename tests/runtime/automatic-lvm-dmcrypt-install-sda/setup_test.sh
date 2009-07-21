#!/bin/sh

for i in /etc/ / /root/ /home/ /var/
do
	touch /mnt${i}test_file
done
