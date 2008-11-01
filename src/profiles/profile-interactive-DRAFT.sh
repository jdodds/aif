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

partition() {
    if [ "$S_MKFSAUTO" = "1" ]; then
        DIALOG --msgbox "You have already prepared your filesystems with Auto-prepare" 0 0
        return 0
    fi

    _umountall

    # Select disk to partition
    DISCS=$(finddisks _)
    DISCS="$DISCS OTHER - DONE +"
    DIALOG --msgbox "Available Disks:\n\n$(_getavaildisks)\n" 0 0
    DISC=""
    while true; do
        # Prompt the user with a list of known disks
        DIALOG --menu "Select the disk you want to partition (select DONE when finished)" 14 55 7 $DISCS 2>$ANSWER || return 1
        DISC=$(cat $ANSWER)
        if [ "$DISC" = "OTHER" ]; then
            DIALOG --inputbox "Enter the full path to the device you wish to partition" 8 65 "/dev/sda" 2>$ANSWER || return 1
            DISC=$(cat $ANSWER)
        fi
        # Leave our loop if the user is done partitioning
        [ "$DISC" = "DONE" ] && break
        # Partition disc
        DIALOG --msgbox "Now you'll be put into the cfdisk program where you can partition your hard drive. You should make a swap partition and as many data partitions as you will need.  NOTE: cfdisk may ttell you to reboot after creating partitions.  If you need to reboot, just re-enter this install program, skip this step and go on to step 2." 18 70 
        cfdisk $DISC
    done
    S_PART=1
}


configure_system()
{
    ## PREPROCESSING ##
    # only done on first invocation of configure_system
    if [ $S_CONFIG -eq 0 ]; then

        # /etc/pacman.d/mirrorlist
        # add installer-selected mirror to the top of the mirrorlist
        if [ "$MODE" = "ftp" -a "${SYNC_URL}" != "" ]; then
            awk "BEGIN { printf(\"# Mirror used during installation\nServer = "${SYNC_URL}"\n\n\") } 1 " "${TARGET_DIR}/etc/pacman.d/mirrorlist"
        fi

        # /etc/rc.conf
        # insert timezone and utc info
        sed -i -e "s/^TIMEZONE=.*/TIMEZONE=\"$TIMEZONE\"/g" \
               -e "s/^HARDWARECLOCK=.*/HARDWARECLOCK=\"$HARDWARECLOCK\"/g" \
               ${TARGET_DIR}/etc/rc.conf
    fi

    ## END PREPROCESS ##

    [ "$EDITOR" ] || geteditor
    FILE=""

    # main menu loop
    while true; do
        if [ -n "$FILE" ]; then
            DEFAULT="--default-item $FILE"
        else
            DEFAULT=""
        fi

        DIALOG $DEFAULT --menu "Configuration" 17 70 10 \
            "/etc/rc.conf"              "System Config" \
            "/etc/fstab"                "Filesystem Mountpoints" \
            "/etc/mkinitcpio.conf"      "Initramfs Config" \
            "/etc/modprobe.conf"        "Kernel Modules" \
            "/etc/resolv.conf"          "DNS Servers" \
            "/etc/hosts"                "Network Hosts" \
            "/etc/hosts.deny"           "Denied Network Services" \
            "/etc/hosts.allow"          "Allowed Network Services" \
            "/etc/locale.gen"           "Glibc Locales" \
            "/etc/pacman.d/mirrorlist"  "Pacman Mirror List" \
            "Root-Password"             "Set the root password" \
            "Return"        "Return to Main Menu" 2>$ANSWER || FILE="Return"
        FILE="$(cat $ANSWER)"
 if [ "$FILE" = "Return" -o -z "$FILE" ]; then       # exit
            break
        elif [ "$FILE" = "Root-Password" ]; then            # non-file
            while true; do
                chroot ${TARGET_DIR} passwd root && break
            done
        else                                                #regular file
            $EDITOR ${TARGET_DIR}${FILE}
        fi
    done  

    ## POSTPROCESSING ##

    # /etc/initcpio.conf
    #
    run_mkinitcpio

    # /etc/locale.gen
    #
    chroot ${TARGET_DIR} locale-gen

    ## END POSTPROCESSING ##

    S_CONFIG=1
}


prepare_harddrive()
{
    S_MKFSAUTO=0
    S_MKFS=0
    DONE=0
    NEXTITEM=""
    while [ "$DONE" = "0" ]; do
        if [ -n "$NEXTITEM" ]; then
            DEFAULT="--default-item $NEXTITEM"
        else
            DEFAULT=""
        fi
        DIALOG $DEFAULT --menu "Prepare Hard Drive" 12 60 5 \
            "1" "Auto-Prepare (erases the ENTIRE hard drive)" \
            "2" "Partition Hard Drives" \
            "3" "Set Filesystem Mountpoints" \
            "4" "Return to Main Menu" 2>$ANSWER
        NEXTITEM="$(cat $ANSWER)"
        case $(cat $ANSWER) in
            "1")
                autoprepare ;;
            "2")
                partition ;;
            "3")
                PARTFINISH=""
                mountpoints ;;
            *)
                DONE=1 ;;
        esac
    done
    NEXTITEM="1"
}


# set_clock()
# prompts user to set hardware clock and timezone
#
# params: none
# returns: 1 on failure
set_clock()   
{
    # utc or local?
    DIALOG --menu "Is your hardware clock in UTC or local time?" 10 50 2 \
        "UTC" " " \
        "local" " " \
        2>$ANSWER || return 1
    HARDWARECLOCK=$(cat $ANSWER)

    # timezone?
    tzselect > $ANSWER || return 1
    TIMEZONE=$(cat $ANSWER)

    # set system clock from hwclock - stolen from rc.sysinit
    local HWCLOCK_PARAMS=""
    if [ "$HARDWARECLOCK" = "UTC" ]; then
        HWCLOCK_PARAMS="$HWCLOCK_PARAMS --utc"
    else
        HWCLOCK_PARAMS="$HWCLOCK_PARAMS --localtime"
    fi  
    if [ "$TIMEZONE" != "" -a -e "/usr/share/zoneinfo/$TIMEZONE" ]; then
        /bin/rm -f /etc/localtime
        /bin/cp "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
    fi
    /sbin/hwclock --hctosys $HWCLOCK_PARAMS --noadjfile

    # display and ask to set date/time
    dialog --calendar "Set the date.\nUse <TAB> to navigate and arrow keys to change values." 0 0 0 0 0 2> $ANSWER || return 1
    local _date="$(cat $ANSWER)"
    dialog --timebox "Set the time.\nUse <TAB> to navigate and up/down to change values." 0 0 2> $ANSWER || return 1
    local _time="$(cat $ANSWER)"
    echo "date: $_date time: $_time" >$LOG

    # save the time
    # DD/MM/YYYY hh:mm:ss -> YYYY-MM-DD hh:mm:ss
    local _datetime="$(echo "$_date" "$_time" | sed 's#\(..\)/\(..\)/\(....\) \(..\):\(..\):\(..\)#\3-\2-\1 \4:\5:\6#g')"
    echo "setting date to: $_datetime" >$LOG
    date -s "$_datetime" 2>&1 >$LOG
    /sbin/hwclock --systohc $HWCLOCK_PARAMS --noadjfile

    S_CLOCK=1
}

[ $S_SELECT -eq 0 ] && install_pkg && S_INSTALL=1 # user must first select, then install
# automagic time!
# any automatic configuration should go here
notify "Writing base configuration..."        
auto_fstab
auto_network
auto_locale 
        
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
    
    