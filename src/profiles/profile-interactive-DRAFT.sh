#!/bin/sh

TARGET_DIR="/mnt"
EDITOR=


# clock
HARDWARECLOCK=
TIMEZONE=

# partitions
PART_ROOT=

# default filesystem specs (the + is bootable flag)
# <mountpoint>:<partsize>:<fstype>[:+]
DEFAULTFS="/boot:32:ext2:+ swap:256:swap /:7500:ext3 /home:*:ext3"

# install stages
S_SRC=0         # choose install medium
S_NET=0         # network configuration
S_CLOCK=0       # clock and timezone
S_PART=0        # partitioning
S_MKFS=0        # formatting
S_MKFSAUTO=0    # auto fs part/formatting TODO: kill this
S_SELECT=0      # package selection
S_INSTALL=0     # package installation
S_CONFIG=0      # configuration editing
S_GRUB=0        # TODO: kill this - if using grub
S_BOOT=""       # bootloader installed (set to loader name instead of 1)


DIALOG --infobox "Generating GRUB device map...\nThis could take a while.\n\n Please be patient." 0 0
get_grub_map


mainmenu()  
{
    if [ -n "$NEXTITEM" ]; then
        DEFAULT="--default-item $NEXTITEM"
    else
        DEFAULT=""
    fi
    DIALOG $DEFAULT --title " MAIN MENU " \
        --menu "Use the UP and DOWN arrows to navigate menus.  Use TAB to switch between buttons and ENTER to select." 16 55 8 \
        "0" "Select Source" \
        "1" "Set Clock" \
        "2" "Prepare Hard Drive" \
        "3" "Select Packages" \
        "4" "Install Packages" \
        "5" "Configure System" \
        "6" "Install Bootloader" \
        "7" "Exit Install" 2>$ANSWER
    NEXTITEM="$(cat $ANSWER)"
    case $(cat $ANSWER) in
        "0")
            select_source ;;
        "1")
            set_clock ;;
        "2")
            prepare_harddrive ;;
        "3")
            select_packages ;;
        "4")
            installpkg ;;
        "5")
            configure_system ;;
        "6")
            install_bootloader ;;
        "7")
            echo ""
            echo "If the install finished successfully, you can now type 'reboot'"
            echo "to restart the system."
            echo ""
            exit 0 ;;
        *)
            DIALOG --yesno "Abort Installation?" 6 40 && exit 0
            ;;
    esac
}


#####################
## begin execution ##

DIALOG --msgbox "Welcome to the Arch Linux Installation program. The install \
process is fairly straightforward, and you should run through the options in \
the order they are presented. If you are unfamiliar with partitioning/making \
filesystems, you may want to consult some documentation before continuing. \
You can view all output from commands by viewing your VC7 console (ALT-F7). \
ALT-F1 will bring you back here." 14 65

while true; do
    mainmenu
    done
    
    exit 0
    
    