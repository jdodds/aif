#!/bin/bash
# Note that $var_UI_TYPE may not be set here. especially if being loaded in the "early bootstrap" phase

source /usr/lib/libui.sh

# mandatory to call me when you want to use me. call me again after setting $var_UI_TYPE
ui_init ()
{
	cats="MAIN PROCEDURE UI UI-INTERACTIVE FS MISC NETWORK PACMAN SOFTWARE"
	if [ "$LOG_TO_FILE" = '1' ]; then
		logs="$LOG $LOGFILE"
	else
		logs=$LOG
	fi
	if [ "$DEBUG" = '1' ]; then
		libui_sh_init "${var_UI_TYPE:-cli}" "$RUNTIME_DIR" "$logs" "$cats"
	else
		libui_sh_init "${var_UI_TYPE:-cli}" "$RUNTIME_DIR" "$logs"
	fi

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


# Get a list of available partionable blockdevices for use in ask_option
# populates array $BLOCKFRIENDLY with elements like:
#   '/dev/sda' '/dev/sda 640133 MiB (640 GiB)'
listblockfriendly()
{
	BLOCKFRIENDLY=()
	for i in $(finddisks)
	do
		get_blockdevice_size $i MiB
		size_GiB=$(($BLOCKDEVICE_SIZE/2**10))
		BLOCKFRIENDLY+=($i "$i ${BLOCKDEVICE_SIZE} MiB ($size_GiB GiB)")
	done
}

# captitalize first character
function capitalize () {
	sed 's/\([a-z]\)\([a-zA-Z0-9]*\)/\u\1\2/g';
}

set_keymap ()
{
	KBDDIR="/usr/share/kbd"

	KEYMAPS=()
	local keymap
	for keymap in $(find $KBDDIR/keymaps -name "*.gz" | sort); do
		KEYMAPS+=("${keymap##$KBDDIR/keymaps/}" -)
	done
	ask_option "${var_KEYMAP:-no}" "Select a keymap" '' optional "${KEYMAPS[@]}"
	if [ -n "$ANSWER_OPTION" ]
	then
		loadkeys -q $KBDDIR/keymaps/$ANSWER_OPTION
		var_KEYMAP=$ANSWER_OPTION
		echo "$var_KEYMAP" > $RUNTIME_DIR/aif-keymap
	fi

	FONTS=()
	local font
	for font in $(find $KBDDIR/consolefonts -maxdepth 1 -name "*.gz"  | sed 's|^.*/||g' | sort); do
		FONTS+=("$font" -)
	done
	ask_option "${var_CONSOLEFONT:-no}" "Select a console font" '' optional "${FONTS[@]}"
	if [ -n "$ANSWER_OPTION" ]
	then
		var_CONSOLEFONT=$ANSWER_OPTION
		local i
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

# $1 "topic"
# shift 1; "$@" list of failed things
warn_failed () {
	local topic=$1
	shift
	if [ -n "$1" ]
	then
		local list_failed=
		while [ -n "$1" ]
		do
			[ -n "$list_failed" ] && list_failed="$list_failed, "
			list_failed="${list_failed}$1"
			shift
		done
		show_warning "Preconfigure failed" "Beware: the following steps failed: $list_failed. Please report this. Continue at your own risk"
	fi
	return 0
}

# $1 basedir. default: empty
ask_mkinitcpio_preset () {
	local basedir=$1
	presets=($(for i in $(ls -1 $basedir/etc/mkinitcpio.d/*.preset | grep -v example\.preset); do basename $i .preset; echo '-'; done))
	num_presets=$((${#presets[@]}/2))
	if [[ $num_presets -lt 1 ]]; then
		die_error "Not a single mkinitcpio preset found in $basedir/etc/mkinitcpio.d/ ? No kernel installed? WTF?"
	elif [[ $num_presets -eq 1 ]]; then
		# this is the most likely case: the user just installed 1 kernel..
		echo ${presets[0]}
	else
		ask_option 'no' "Build initcpio for which preset/kernel?" '' '' "${presets[@]}"
		echo $ANSWER_OPTION
	fi
	return 0
}

# $1 default option, or 'no' for none
# $1 name of the filesystem (or partition/device) to ask for
ask_mountpoint () {
	local default=$1
	local part=$2
	local opts=(/ 'root' /boot 'files for booting' /home 'home directories' /var 'variable files' /tmp 'temporary files' custom 'enter a custom mountpoint')
	ask_option $default "Select the mountpoint" "Select a mountpoint for $part" required "${opts[@]}" || return 1
	if [ "$ANSWER_OPTION" == custom ]; then
		[ "$default" == 'no' ] && default=
		ask_string "Enter the custom mountpoint for $part" "$default" || return 1
		echo $ANSWER_STRING
	else
		echo $ANSWER_OPTION
	fi
}
