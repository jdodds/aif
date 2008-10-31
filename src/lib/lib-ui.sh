#!/bin/sh

# DIALOG() taken from setup
# an el-cheapo dialog wrapper
#
# parameters: see dialog(1)
# returns: whatever dialog did
DIALOG()
{
	dialog --backtitle "$TITLE" --aspect 15 "$@"
	return $?
}


# taken from setup
printk()
{
    case $1 in
        "on")  echo 4 >/proc/sys/kernel/printk ;;
        "off") echo 0 >/proc/sys/kernel/printk ;;
    esac
}


# geteditor(). taken from original setup code. prepended gui_ because power users just export $EDITOR on the cmdline.
# prompts the user to choose an editor
# sets EDITOR global variable
#
gui_geteditor() {
    DIALOG --menu "Select a Text Editor to Use" 10 35 3 \
        "1" "nano (easier)" \
        "2" "vi" 2>$ANSWER   
    case $(cat $ANSWER) in   
        "1") EDITOR="nano" ;;
        "2") EDITOR="vi" ;;  
        *)   EDITOR="nano" ;;
    esac
}


# Get a list of available disks for use in the "Available disks" dialogs. This
# will print the disks as follows, getting size info from hdparm:
#   /dev/sda: 640133 MBytes (640 GB)
#   /dev/sdb: 640135 MBytes (640 GB)
gui_getavaildisks()
{
    # NOTE: to test as non-root, stick in a 'sudo' before the hdparm call
    for i in $(finddisks); do echo -n "$i: "; hdparm -I $i | grep -F '1000*1000' | sed "s/.*1000:[ \t]*\(.*\)/\1/"; echo "\n"; done
}


# taken from setup code. edited to echo the choice, not perform it
gui_ask_bootloader()
{
    DIALOG --colors --menu "Which bootloader would you like to use?  Grub is the Arch default.\n\n" \
        10 65 2 \
        "GRUB" "Use the GRUB bootloader (default)" \
        "None" "\Zb\Z1Warning\Z0\ZB: you must install your own bootloader!" 2>$ANSWER
	cat $ANSWER
}
        