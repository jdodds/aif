#!/bin/bash
RUNTIME_DIR=/tmp/aif
LOG_DIR=/var/log/aif
source /usr/lib/libui.sh
cat - <<EOF
This script will help you reporting issues and/or seeking help
What we do, is upload all files in $RUNTIME_DIR and $LOG_DIR to a pastebin
Usually these files contain no sensitive information, but if you run a custom
installation procedure/library, make your checks first.
These are the files in question:
EOF
ls -lh $RUNTIME_DIR/* 2>/dev/null
ls -lh $LOG_DIR/* 2>/dev/null
if ! ping -c 1 sprunge.us >/dev/null
then
	msg="Please setup your networking using one of
* dhcpcd eth0 # or whatever your interface is
* aif -p partial-configure-network

If your networking works fine and you think sprunge.us is down, please upload the files to another pastebin"
	show_warning "Connection error" "Cannot ping sprunge.us (pastebin server). $msg"
	die_error "cannot reach pastebin"
fi
report="Uploaded data:"
if ask_yesno "Send these files?"
then
	shopt -s nullglob
	for i in $RUNTIME_DIR/* $LOG_DIR/*
	do
		bin=$(cat $i | curl -sF 'sprunge=<-' http://sprunge.us)
		bin=${bin/ /} # for some reason there is a space in the beginning
		report="$report\n$i $bin"
	done
	shopt -u nullglob
fi

echo "It can also be useful to upload a list of currently mounted filesystems:"
df -hT
if ask_yesno "Is this ok?"
then
	bin=$(df -hT | curl -sF 'sprunge=<-' http://sprunge.us)
	bin=${bin/ /}
	report="$report\ndf -hT $bin"
fi
echo -e "$report"
echo "For your convenience, I will paste the report online"
echo "So you just need to give the following url:"
echo -e "$report" | curl -sF 'sprunge=<-' http://sprunge.us
