#!/bin/bash
# Note that $var_UI_TYPE may not be set here. especially if being loaded in the "early bootstrap" phase

source /usr/lib/lib-ui.sh

# mandatory to call me when you want to use me. call me again after setting $var_UI_TYPE
ui_init ()
{
	lib-ui-sh-init $RUNTIME_DIR $var_UI_TYPE

	# get keymap/font (maybe configured by aif allready in another process or even in another shell)
	# otherwise, take default keymap and consolefont as configured in /etc/rc.conf. can be overridden
	# Note that the vars in /etc/rc.conf can also be empty!
	[ -e $RUNTIME_DIR/aif-keymap      ] && var_KEYMAP=`     cat $RUNTIME_DIR/aif-keymap`
	[ -e $RUNTIME_DIR/aif-consolefont ] && var_CONSOLEFONT=`cat $RUNTIME_DIR/aif-consolefont`
	[ -z "$var_KEYMAP"      ] && source /etc/rc.conf && var_KEYMAP=$KEYMAP
	[ -z "$var_CONSOLEFONT" ] && source /etc/rc.conf && var_CONSOLEFONT=$CONSOLEFONT
}

# taken from setup
printk()
{
	case $1 in
		"on")  echo 4 >/proc/sys/kernel/printk ;;
		"off") echo 0 >/proc/sys/kernel/printk ;;
	esac
}


# TODO: pass disks as argument to decouple backend logic
# Get a list of available disks for use in the "Available disks" dialogs.
# Something like:
#   /dev/sda: 640133 MiB (640 GiB)
#   /dev/sdb: 640135 MiB (640 GiB)
_getavaildisks()
{
	for i in $(finddisks)
	do
		get_blockdevice_size $i MiB
		echo "$i: $BLOCKDEVICE_SIZE MiB ($(($BLOCKDEVICE_SIZE/2**10)) GiB)\n"
	done
}


set_keymap ()
{
	KBDDIR="/usr/share/kbd"

	KEYMAPS=
	for i in $(find $KBDDIR/keymaps -name "*.gz" | sort); do
		KEYMAPS="$KEYMAPS ${i##$KBDDIR/keymaps/} -"
	done
	ask_option "${var_KEYMAP:-no}" "Select A Keymap" '' optional $KEYMAPS
	if [ -n "$ANSWER_OPTION" ]
	then
		loadkeys -q $KBDDIR/keymaps/$ANSWER_OPTION
		var_KEYMAP=$ANSWER_OPTION
		echo "$var_KEYMAP" > $RUNTIME_DIR/aif-keymap
	fi

	FONTS=
	# skip .cp.gz and partialfonts files for now see bug #6112, #6111
	for i in $(find $KBDDIR/consolefonts -maxdepth 1 ! -name '*.cp.gz' -name "*.gz"  | sed 's|^.*/||g' | sort); do
		FONTS="$FONTS $i -"
	done
	ask_option "${var_CONSOLEFONT:-no}" "Select A Console Font" '' optional $FONTS
	if [ -n "$ANSWER_OPTION" ]
	then
		var_CONSOLEFONT=$ANSWER_OPTION
		for i in 1 2 3 4
		do
			if [ -d /dev/vc ]; then
				setfont $KBDDIR/consolefonts/$var_CONSOLEFONT -C /dev/vc/$i
			else
				setfont $KBDDIR/consolefonts/$var_CONSOLEFONT -C /dev/tty$i
			fi
		done
		echo "$var_CONSOLEFONT" > $RUNTIME_DIR/aif-consolefont
	fi
}
