#!/bin/sh

# DIALOG()
# an el-cheapo dialog wrapper
#
# parameters: see dialog(1)
# returns: whatever dialog did
DIALOG() {
	dialog --backtitle "$TITLE" --aspect 15 "$@"
	return $?
}

printk()
{
	case $1 in
		"on")  echo 4 >/proc/sys/kernel/printk ;;
		"off") echo 0 >/proc/sys/kernel/printk ;;
	esac
}

getdest() {
	[ "$DESTDIR" ] && return 0
	DIALOG --inputbox "Enter the destination directory where your target system is mounted" 8 65 "/tmp/install" 2>$ANSWER || return 1
	DESTDIR=$(cat $ANSWER)
}

geteditor() {
	if ! [ $(which vi) ]; then
		DIALOG --menu "Select a Text Editor to Use" 10 35 3 \
			"1" "nano (easier)" 2>$ANSWER
	else
		DIALOG --menu "Select a Text Editor to Use" 10 35 3 \
			"1" "nano (easier)" \
			"2" "vi" 2>$ANSWER
	fi
	case $(cat $ANSWER) in
		"1") EDITOR="nano" ;;
		"2") EDITOR="vi" ;;
		*)   EDITOR="nano" ;;
	esac 
}

mainmenu() {
	if [ -n "$NEXTITEM" ]; then
		DEFAULT="--default-item $NEXTITEM"
	else
		DEFAULT=""
	fi
	dialog $DEFAULT --backtitle "$TITLE" --title " MAIN MENU " \
	--menu "Use the UP and DOWN arrows to navigate menus.  Use TAB to switch between buttons and ENTER to select." 17 55 13 \
	"0" "Keyboard And Console Setting" \
	"1" "Set Clock" \
	"2" "Prepare Hard Drive" \
	"3" "Select Source" \
	"4" "Select Packages" \
	"5" "Install Packages" \
	"6" "Configure System" \
	"7" "Install Bootloader" \
	"8" "Exit Install" 2>$ANSWER
	NEXTITEM="$(cat $ANSWER)"
	case $(cat $ANSWER) in
		"0")
			set_keyboard ;;
		"1")
			set_clock ;;
		"2")
			prepare_harddrive ;;
		"3")
			select_source ;;
		"4")
			selectpkg ;;
		"5")
			installpkg ;;
		"6")
			configure_system ;;
		"7")
			install_bootloader ;;
		"8")
			if [ "$S_SRC" = "1" -a "$MODE" = "cd" ]; then
				umount /src >/dev/null 2>&1
			fi
			[ -e /tmp/.setup-running ] && rm /tmp/.setup-running
			clear
			echo ""
			echo "If the install finished successfully, you can now type 'reboot'"
			echo "to restart the system."
			echo ""
			exit 0 ;;
		*)
			DIALOG --yesno "Abort Installation?" 6 40 &&[ -e /tmp/.setup-running ] && rm /tmp/.setup-running && clear && exit 0
			;;
	esac
}
