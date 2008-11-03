#!/bin/sh
#TODO: get backend code out of here!!

interactive_partition() {
    _umountall

    # Select disk to partition
    DISCS=$(finddisks _)
    DISCS="$DISCS OTHER - DONE +"
    _dia_DIALOG --msgbox "Available Disks:\n\n$(_getavaildisks)\n" 0 0
    DISC=""
    while true; do
        # Prompt the user with a list of known disks
        _dia_DIALOG --menu "Select the disk you want to partition (select DONE when finished)" 14 55 7 $DISCS 2>$ANSWER || return 1
        DISC=$(cat $ANSWER)
        if [ "$DISC" = "OTHER" ]; then
            _dia_DIALOG --inputbox "Enter the full path to the device you wish to partition" 8 65 "/dev/sda" 2>$ANSWER || return 1
            DISC=$(cat $ANSWER)
        fi
        # Leave our loop if the user is done partitioning
        [ "$DISC" = "DONE" ] && break
        # Partition disc
        notify "Now you'll be put into the cfdisk program where you can partition your hard drive. You should make a swap partition and as many data partitions as you will need.  NOTE: cfdisk may ttell you to reboot after creating partitions.  If you need to reboot, just re-enter this install program, skip this step and go on to step 2."
        cfdisk $DISC
    done
    return 0
}


interactive_configure_system()
{
    [ "$EDITOR" ] || geteditor
    FILE=""

    # main menu loop
    while true; do
        if [ -n "$FILE" ]; then
            DEFAULT="--default-item $FILE"
        else
            DEFAULT=""
        fi

        _dia_DIALOG $DEFAULT --menu "Configuration" 17 70 10 \
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

}


# set_clock()
# prompts user to set hardware clock and timezone
#
# params: none
# returns: 1 on failure
interactive_set_clock()   
{
    # utc or local?
    _dia_DIALOG --menu "Is your hardware clock in UTC or local time?" 10 50 2 \
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

    return 0
}


interactive_autoprepare()
{
    DISCS=$(finddisks)
    if [ $(echo $DISCS | wc -w) -gt 1 ]; then
        _dia_DIALOG --msgbox "Available Disks:\n\n$(_getavaildisks)\n" 0 0
        _dia_DIALOG --menu "Select the hard drive to use" 14 55 7 $(finddisks _) 2>$ANSWER || return 1
        DISC=$(cat $ANSWER)
    else
        DISC=$DISCS
    fi
    SET_DEFAULTFS=""
    BOOT_PART_SET=""
    SWAP_PART_SET=""
    ROOT_PART_SET=""
    CHOSEN_FS=""
    # get just the disk size in 1000*1000 MB
    DISC_SIZE=$(hdparm -I /dev/sda | grep -F '1000*1000' | sed "s/^.*:[ \t]*\([0-9]*\) MBytes.*$/\1/")
    while [ "$SET_DEFAULTFS" = "" ]; do
        FSOPTS="ext2 ext2 ext3 ext3"
        [ "$(which mkreiserfs 2>/dev/null)" ] && FSOPTS="$FSOPTS reiserfs Reiser3"
        [ "$(which mkfs.xfs 2>/dev/null)" ]   && FSOPTS="$FSOPTS xfs XFS"
        [ "$(which mkfs.jfs 2>/dev/null)" ]   && FSOPTS="$FSOPTS jfs JFS"
        while [ "$BOOT_PART_SET" = "" ]; do
            _dia_DIALOG --inputbox "Enter the size (MB) of your /boot partition.  Minimum value is 16.\n\nDisk space left: $DISC_SIZE MB" 8 65 "32" 2>$ANSWER || return 1
            BOOT_PART_SIZE="$(cat $ANSWER)"
            if [ "$BOOT_PART_SIZE" = "" ]; then
                _dia_DIALOG --msgbox "ERROR: You have entered an invalid size, please enter again." 0 0
            else
                if [ "$BOOT_PART_SIZE" -ge "$DISC_SIZE" -o "$BOOT_PART_SIZE" -lt "16" -o "$SBOOT_PART_SIZE" = "$DISC_SIZE" ]; then
                    _dia_DIALOG --msgbox "ERROR: You have entered a too large size, please enter again." 0 0
                else
                    BOOT_PART_SET=1
                fi
            fi
        done
        DISC_SIZE=$(($DISC_SIZE-$BOOT_PART_SIZE))
        while [ "$SWAP_PART_SET" = "" ]; do
            _dia_DIALOG --inputbox "Enter the size (MB) of your swap partition.  Minimum value is > 0.\n\nDisk space left: $DISC_SIZE MB" 8 65 "256" 2>$ANSWER || return 1
            SWAP_PART_SIZE=$(cat $ANSWER)
            if [ "$SWAP_PART_SIZE" = "" -o  "$SWAP_PART_SIZE" -le "0" ]; then
                _dia_DIALOG --msgbox "ERROR: You have entered an invalid size, please enter again." 0 0
            else
                if [ "$SWAP_PART_SIZE" -ge "$DISC_SIZE" ]; then
                    _dia_DIALOG --msgbox "ERROR: You have entered a too large size, please enter again." 0 0
                else
                    SWAP_PART_SET=1
                fi
            fi
        done
        DISC_SIZE=$(($DISC_SIZE-$SWAP_PART_SIZE))
        while [ "$ROOT_PART_SET" = "" ]; do
            _dia_DIALOG --inputbox "Enter the size (MB) of your / partition.  The /home partition will use the remaining space.\n\nDisk space left:  $DISC_SIZE MB" 8 65 "7500" 2>$ANSWER || return 1
            ROOT_PART_SIZE=$(cat $ANSWER)
            if [ "$ROOT_PART_SIZE" = "" -o "$ROOT_PART_SIZE" -le "0" ]; then
                _dia_DIALOG --msgbox "ERROR: You have entered an invalid size, please enter again." 0 0
            else
                if [ "$ROOT_PART_SIZE" -ge "$DISC_SIZE" ]; then
                    _dia_DIALOG --msgbox "ERROR: You have entered a too large size, please enter again." 0 0
                else
                    _dia_DIALOG --yesno "$(($DISC_SIZE-$ROOT_PART_SIZE)) MB will be used for your /home partition.  Is this OK?" 0 0 && ROOT_PART_SET=1
                fi
            fi
        done
        while [ "$CHOSEN_FS" = "" ]; do
            _dia_DIALOG --menu "Select a filesystem for / and /home:" 13 45 6 $FSOPTS 2>$ANSWER || return 1
            FSTYPE=$(cat $ANSWER)
            _dia_DIALOG --yesno "$FSTYPE will be used for / and /home. Is this OK?" 0 0 && CHOSEN_FS=1
        done
        SET_DEFAULTFS=1
    done

    _dia_DIALOG --defaultno --yesno "$DISC will be COMPLETELY ERASED!  Are you absolutely sure?" 0 0 \
    || return 1

    DEVICE=$DISC
    FSSPECS=$(echo $DEFAULTFS | sed -e "s|/:7500:ext3|/:$ROOT_PART_SIZE:$FSTYPE|g" -e "s|/home:\*:ext3|/home:\*:$FSTYPE|g" -e "s|swap:256|swap:$SWAP_PART_SIZE|g" -e "s|/boot:32|/boot:$BOOT_PART_SIZE|g")
    sfdisk_input=""

    # we assume a /dev/hdX format (or /dev/sdX)
    PART_ROOT="${DEVICE}3"

    if [ "$S_MKFS" = "1" ]; then
        _dia_DIALOG --msgbox "You have already prepared your filesystems manually" 0 0
        return 0
    fi

    # validate DEVICE
    if [ ! -b "$DEVICE" ]; then
      _dia_DIALOG --msgbox "Device '$DEVICE' is not valid" 0 0
      return 1
    fi

    # validate DEST
    if [ ! -d "$TARGET_DIR" ]; then
        _dia_DIALOG --msgbox "Destination directory '$TARGET_DIR' is not valid" 0 0
        return 1
    fi

    # / required
    if [ $(echo $FSSPECS | grep '/:' | wc -l) -ne 1 ]; then
        _dia_DIALOG --msgbox "Need exactly one root partition" 0 0
        return 1
    fi

    rm -f /tmp/.fstab

    _umountall

    # setup input var for sfdisk
    for fsspec in $FSSPECS; do
        fssize=$(echo $fsspec | tr -d ' ' | cut -f2 -d:)
        if [ "$fssize" = "*" ]; then
                fssize_spec=';'
        else
                fssize_spec=",$fssize"
        fi
        fstype=$(echo $fsspec | tr -d ' ' | cut -f3 -d:)
        if [ "$fstype" = "swap" ]; then
                fstype_spec=",S"
        else
                fstype_spec=","
        fi
        bootflag=$(echo $fsspec | tr -d ' ' | cut -f4 -d:)
        if [ "$bootflag" = "+" ]; then
            bootflag_spec=",*"
        else
            bootflag_spec=""
        fi
        sfdisk_input="${sfdisk_input}${fssize_spec}${fstype_spec}${bootflag_spec}\n"
    done
    sfdisk_input=$(printf "$sfdisk_input")

    # invoke sfdisk
    printk off
    _dia_DIALOG --infobox "Partitioning $DEVICE" 0 0
    sfdisk $DEVICE -uM >$LOG 2>&1 <<EOF
$sfdisk_input
EOF
    if [ $? -gt 0 ]; then
        _dia_DIALOG --msgbox "Error partitioning $DEVICE (see $LOG for details)" 0 0
        printk on
        return 1
    fi
    printk on

    # need to mount root first, then do it again for the others
    part=1
    for fsspec in $FSSPECS; do
        mountpoint=$(echo $fsspec | tr -d ' ' | cut -f1 -d:)
        fstype=$(echo $fsspec | tr -d ' ' | cut -f3 -d:)
        if echo $mountpoint | tr -d ' ' | grep '^/$' 2>&1 > /dev/null; then
            _mkfs yes ${DEVICE}${part} "$fstype" "$TARGET_DIR" "$mountpoint" || return 1
        fi
        part=$(($part + 1))
    done

    # make other filesystems
    part=1
    for fsspec in $FSSPECS; do
        mountpoint=$(echo $fsspec | tr -d ' ' | cut -f1 -d:)
        fstype=$(echo $fsspec | tr -d ' ' | cut -f3 -d:)
        if [ $(echo $mountpoint | tr -d ' ' | grep '^/$' | wc -l) -eq 0 ]; then
            _mkfs yes ${DEVICE}${part} "$fstype" "$TARGET_DIR" "$mountpoint" || return 1
        fi
        part=$(($part + 1))
    done

    _dia_DIALOG --msgbox "Auto-prepare was successful" 0 0
    return 0
}


interactive_mountpoints() {
    while [ "$PARTFINISH" != "DONE" ]; do
        : >/tmp/.fstab
        : >/tmp/.parts

        # Determine which filesystems are available
        FSOPTS="ext2 ext2 ext3 ext3"
        [ "$(which mkreiserfs 2>/dev/null)" ] && FSOPTS="$FSOPTS reiserfs Reiser3"
        [ "$(which mkfs.xfs 2>/dev/null)" ]   && FSOPTS="$FSOPTS xfs XFS"
        [ "$(which mkfs.jfs 2>/dev/null)" ]   && FSOPTS="$FSOPTS jfs JFS"
        [ "$(which mkfs.vfat 2>/dev/null)" ]  && FSOPTS="$FSOPTS vfat VFAT"

        # Select mountpoints
        _dia_DIALOG --msgbox "Available Disks:\n\n$(_getavaildisks)\n" 0 0
        PARTS=$(findpartitions _)
        _dia_DIALOG --menu "Select the partition to use as swap" 21 50 13 NONE - $PARTS 2>$ANSWER || return 1
        PART=$(cat $ANSWER)
        PARTS="$(echo $PARTS | sed -e "s#${PART}\ _##g")"
        if [ "$PART" != "NONE" ]; then
            DOMKFS="no"
            _dia_DIALOG --yesno "Would you like to create a filesystem on $PART?\n\n(This will overwrite existing data!)" 0 0 && DOMKFS="yes"
            echo "$PART:swap:swap:$DOMKFS" >>/tmp/.parts
        fi

        _dia_DIALOG --menu "Select the partition to mount as /" 21 50 13 $PARTS 2>$ANSWER || return 1
        PART=$(cat $ANSWER)
        PARTS="$(echo $PARTS | sed -e "s#${PART}\ _##g")"
        PART_ROOT=$PART
        # Select root filesystem type
        _dia_DIALOG --menu "Select a filesystem for $PART" 13 45 6 $FSOPTS 2>$ANSWER || return 1
        FSTYPE=$(cat $ANSWER)
        DOMKFS="no"
        _dia_DIALOG --yesno "Would you like to create a filesystem on $PART?\n\n(This will overwrite existing data!)" 0 0 && DOMKFS="yes"
        echo "$PART:$FSTYPE:/:$DOMKFS" >>/tmp/.parts

        #
        # Additional partitions
        #
        _dia_DIALOG --menu "Select any additional partitions to mount under your new root (select DONE when finished)" 21 50 13 $PARTS DONE _ 2>$ANSWER || return 1
        PART=$(cat $ANSWER)
        while [ "$PART" != "DONE" ]; do
            PARTS="$(echo $PARTS | sed -e "s#${PART}\ _##g")"
            # Select a filesystem type
            _dia_DIALOG --menu "Select a filesystem for $PART" 13 45 6 $FSOPTS 2>$ANSWER || return 1
            FSTYPE=$(cat $ANSWER)
            MP=""
            while [ "${MP}" = "" ]; do
                _dia_DIALOG --inputbox "Enter the mountpoint for $PART" 8 65 "/boot" 2>$ANSWER || return 1
                MP=$(cat $ANSWER)
                if grep ":$MP:" /tmp/.parts; then
                    _dia_DIALOG --msgbox "ERROR: You have defined 2 identical mountpoints! Please select another mountpoint." 8 65
                    MP=""
                fi
            done
            DOMKFS="no"
            _dia_DIALOG --yesno "Would you like to create a filesystem on $PART?\n\n(This will overwrite existing data!)" 0 0 && DOMKFS="yes"
            echo "$PART:$FSTYPE:$MP:$DOMKFS" >>/tmp/.parts
            _dia_DIALOG --menu "Select any additional partitions to mount under your new root" 21 50 13 $PARTS DONE _ 2>$ANSWER || return 1
            PART=$(cat $ANSWER)
        done
        _dia_DIALOG --yesno "Would you like to create and mount the filesytems like this?\n\nSyntax\n------\nDEVICE:TYPE:MOUNTPOINT:FORMAT\n\n$(for i in $(cat /tmp/.parts); do echo "$i\n";done)" 18 0 && PARTFINISH="DONE"
    done

    _umountall

    for line in $(cat /tmp/.parts); do
        PART=$(echo $line | cut -d: -f 1)
        FSTYPE=$(echo $line | cut -d: -f 2)
        MP=$(echo $line | cut -d: -f 3)
        DOMKFS=$(echo $line | cut -d: -f 4)
        umount ${TARGET_DIR}${MP}
        if [ "$DOMKFS" = "yes" ]; then
            if [ "$FSTYPE" = "swap" ]; then
                _dia_DIALOG --infobox "Creating and activating swapspace on $PART" 0 0
            else
                _dia_DIALOG --infobox "Creating $FSTYPE on $PART, mounting to ${TARGET_DIR}${MP}" 0 0
            fi
            _mkfs yes $PART $FSTYPE $TARGET_DIR $MP || return 1
        else
            if [ "$FSTYPE" = "swap" ]; then
                _dia_DIALOG --infobox "Activating swapspace on $PART" 0 0
            else
                _dia_DIALOG --infobox "Mounting $PART to ${TARGET_DIR}${MP}" 0 0
            fi
            _mkfs no $PART $FSTYPE $TARGET_DIR $MP || return 1
        fi
        sleep 1
    done

	notify "Partitions were successfully mounted."
	return 0
}

# select_packages()
# prompts the user to select packages to install
#
# params: none
# returns: 1 on error
interactive_select_packages() {

    _dia_DIALOG --msgbox "Package selection is split into two stages.  First you will select package categories that contain packages you may be interested in.  Then you will be presented with a full list of packages for each category, allowing you to fine-tune.\n\n" 15 70

    # set up our install location if necessary and sync up
    # so we can get package lists
    prepare_pacman
    if [ $? -ne 0 ]; then
        _dia_DIALOG --msgbox "Pacman preparation failed! Check $LOG for errors." 6 60
        return 1
    fi

    # show group listing for group selection
    local _catlist="base ^ ON"
    for i in $($PACMAN -Sg | sed "s/^base$/ /g"); do
        _catlist="${_catlist} ${i} - OFF"
    done

    _dia_DIALOG --checklist "Select Package Categories\nDO NOT deselect BASE unless you know what you're doing!" 19 55 12 $_catlist 2>$ANSWER || return 1
    _catlist="$(cat $ANSWER)"

    # assemble a list of packages with groups, marking pre-selected ones
    # <package> <group> <selected>
    local _pkgtmp="$($PACMAN -Sl core | awk '{print $2}')"
    local _pkglist=''

    $PACMAN -Si $_pkgtmp | \
        awk '/^Name/{ printf("%s ",$3) } /^Group/{ print $3 }' > $ANSWER
    while read pkgname pkgcat; do
        # check if this package is in a selected group
        # slightly ugly but sorting later requires newlines in the variable
        if [ "${_catlist/"\"$pkgcat\""/XXXX}" != "${_catlist}" ]; then
            _pkglist="$(echo -e "${_pkglist}\n${pkgname} ${pkgcat} ON")"
        else
            _pkglist="$(echo -e "${_pkglist}\n${pkgname} ${pkgcat} OFF")"
        fi
    done < $ANSWER

    # sort by category
    _pkglist="$(echo "$_pkglist" | sort -f -k 2)"

    _dia_DIALOG --checklist "Select Packages To Install." 19 60 12 $_pkglist 2>$ANSWER || return 1
    PACKAGES="$(cat $ANSWER)"
    return 0
}


# Hand-hold through setting up networking
#
# args: none
# returns: 1 on failure
interactive_runtime_network() {
    INTERFACE=""
    S_DHCP=""
    local ifaces
    ifaces=$(ifconfig -a |grep "Link encap:Ethernet"|sed 's/ \+Link encap:Ethernet \+HWaddr \+/ /g')

    if [ "$ifaces" = "" ]; then
        _dia_DIALOG --msgbox "Cannot find any ethernet interfaces. This usually means udev was\nunable to load the module and you must do it yourself. Switch to\nanother VT, load the appropriate module, and run this step again." 18 70
        return 1
    fi

    _dia_DIALOG --nocancel --ok-label "Select" --menu "Select a network interface" 14 55 7 $ifaces 2>$ANSWER
    case $? in
        0) INTERFACE=$(cat $ANSWER) ;;
        *) return 1 ;;
    esac

    _dia_DIALOG --yesno "Do you want to use DHCP?" 0 0
    if [ $? -eq 0 ]; then
        _dia_DIALOG --infobox "Please wait.  Polling for DHCP server on $INTERFACE..." 0 0
        dhcpcd $INTERFACE >$LOG 2>&1
        if [ $? -ne 0 ]; then
            _dia_DIALOG --msgbox "Failed to run dhcpcd.  See $LOG for details." 0 0
            return 1
        fi
        if [ ! $(ifconfig $INTERFACE | grep 'inet addr:') ]; then
            _dia_DIALOG --msgbox "DHCP request failed." 0 0 || return 1
        fi
        S_DHCP=1
    else
        NETPARAMETERS=""
        while [ "$NETPARAMETERS" = "" ]; do
            _dia_DIALOG --inputbox "Enter your IP address" 8 65 "192.168.0.2" 2>$ANSWER || return 1
            IPADDR=$(cat $ANSWER)
            _dia_DIALOG --inputbox "Enter your netmask" 8 65 "255.255.255.0" 2>$ANSWER || return 1
            SUBNET=$(cat $ANSWER)
            _dia_DIALOG --inputbox "Enter your broadcast" 8 65 "192.168.0.255" 2>$ANSWER || return 1
            BROADCAST=$(cat $ANSWER)
            _dia_DIALOG --inputbox "Enter your gateway (optional)" 8 65 "192.168.0.1" 2>$ANSWER || return 1
            GW=$(cat $ANSWER)
            _dia_DIALOG --inputbox "Enter your DNS server IP" 8 65 "192.168.0.1" 2>$ANSWER || return 1
            DNS=$(cat $ANSWER)
            _dia_DIALOG --inputbox "Enter your HTTP proxy server, for example:\nhttp://name:port\nhttp://ip:port\nhttp://username:password@ip:port\n\n Leave the field empty if no proxy is needed to install." 16 65 "" 2>$ANSWER || return 1
            PROXY_HTTP=$(cat $ANSWER)
            _dia_DIALOG --inputbox "Enter your FTP proxy server, for example:\nhttp://name:port\nhttp://ip:port\nhttp://username:password@ip:port\n\n Leave the field empty if no proxy is needed to install." 16 65 "" 2>$ANSWER || return 1
            PROXY_FTP=$(cat $ANSWER)
            _dia_DIALOG --yesno "Are these settings correct?\n\nIP address:         $IPADDR\nNetmask:            $SUBNET\nGateway (optional): $GW\nDNS server:         $DNS\nHTTP proxy server:  $PROXY_HTTP\nFTP proxy server:   $PROXY_FTP" 0 0
            case $? in
                1) ;;
                0) NETPARAMETERS="1" ;;
            esac
        done
        echo "running: ifconfig $INTERFACE $IPADDR netmask $SUBNET broadcast $BROADCAST up" >$LOG
        ifconfig $INTERFACE $IPADDR netmask $SUBNET broadcast $BROADCAST up >$LOG 2>&1 || _dia_DIALOG --msgbox "Failed to setup $INTERFACE interface." 0 0 || return 1
        if [ "$GW" != "" ]; then
            route add default gw $GW >$LOG 2>&1 || _dia_DIALOG --msgbox "Failed to setup your gateway." 0 0 || return 1
        fi
        if [ "$PROXY_HTTP" = "" ]; then
            unset http_proxy
        else
            export http_proxy=$PROXY_HTTP
        fi
        if [ "$PROXY_FTP" = "" ]; then
            unset ftp_proxy
        else
            export ftp_proxy=$PROXY_FTP
        fi
        echo "nameserver $DNS" >/etc/resolv.conf
    fi
    notify "The network is configured."
    return 0
}


interactive_install_grub() {
    get_grub_map
    local grubmenu="$TARGET_DIR/boot/grub/menu.lst"
    if [ ! -f $grubmenu ]; then
        _dia_DIALOG --msgbox "Error: Couldn't find $grubmenu.  Is GRUB installed?" 0 0
        return 1
    fi
    # try to auto-configure GRUB...
    if [ "$PART_ROOT" != "" -a "$S_GRUB" != "1" ]; then
        grubdev=$(mapdev $PART_ROOT)
        local _rootpart="${PART_ROOT}"
        local _uuid="$(getuuid ${PART_ROOT})"
        # attempt to use a UUID if the root device has one
        if [ -n "${_uuid}" ]; then
            _rootpart="/dev/disk/by-uuid/${_uuid}"
        fi
        # look for a separately-mounted /boot partition
        bootdev=$(mount | grep $TARGET_DIR/boot | cut -d' ' -f 1)
        if [ "$grubdev" != "" -o "$bootdev" != "" ]; then
            subdir=
            if [ "$bootdev" != "" ]; then
                grubdev=$(mapdev $bootdev)
            else
                subdir="/boot"
            fi
            # keep the file from being completely bogus
            if [ "$grubdev" = "DEVICE NOT FOUND" ]; then
                _dia_DIALOG --msgbox "Your root boot device could not be autodetected by setup.  Ensure you adjust the 'root (hd0,0)' line in your GRUB config accordingly." 0 0
                grubdev="(hd0,0)"
            fi
            # remove default entries by truncating file at our little tag (#-*)
            sed -i -e '/#-\*/q'
            cat >>$grubmenu <<EOF

# (0) Arch Linux
title  Arch Linux
root   $grubdev
kernel $subdir/vmlinuz26 root=${_rootpart} ro
initrd $subdir/kernel26.img

# (1) Arch Linux
title  Arch Linux Fallback
root   $grubdev
kernel $subdir/vmlinuz26 root=${_rootpart} ro
initrd $subdir/kernel26-fallback.img

# (2) Windows
#title Windows
#rootnoverify (hd0,0)
#makeactive
#chainloader +1
EOF
        fi
    fi

    _dia_DIALOG --msgbox "Before installing GRUB, you must review the configuration file.  You will now be put into the editor.  After you save your changes and exit the editor, you can install GRUB." 0 0
    [ "$EDITOR" ] || geteditor
    $EDITOR $grubmenu

    DEVS=$(finddisks _)
    DEVS="$DEVS $(findpartitions _)"
    if [ "$DEVS" = "" ]; then
        _dia_DIALOG --msgbox "No hard drives were found" 0 0
        return 1
    fi
    _dia_DIALOG --menu "Select the boot device where the GRUB bootloader will be installed (usually the MBR and not a partition)." 14 55 7 $DEVS 2>$ANSWER || return 1
    ROOTDEV=$(cat $ANSWER)
    _dia_DIALOG --infobox "Installing the GRUB bootloader..." 0 0
    cp -a $TARGET_DIR/usr/lib/grub/i386-pc/* $TARGET_DIR/boot/grub/
    sync
    # freeze xfs filesystems to enable grub installation on xfs filesystems
    if [ -x /usr/sbin/xfs_freeze ]; then
        /usr/sbin/xfs_freeze -f $TARGET_DIR/boot > /dev/null 2>&1
        /usr/sbin/xfs_freeze -f $TARGET_DIR/ > /dev/null 2>&1
    fi
    # look for a separately-mounted /boot partition
    bootpart=$(mount | grep $TARGET_DIR/boot | cut -d' ' -f 1)
    if [ "$bootpart" = "" ]; then
        if [ "$PART_ROOT" = "" ]; then
            _dia_DIALOG --inputbox "Enter the full path to your root device" 8 65 "/dev/sda3" 2>$ANSWER || return 1
            bootpart=$(cat $ANSWER)
        else
            bootpart=$PART_ROOT
        fi
    fi
    _dia_DIALOG --defaultno --yesno "Do you have your system installed on software raid?\nAnswer 'YES' to install grub to another hard disk." 0 0
    if [ $? -eq 0 ]; then
        _dia_DIALOG --menu "Please select the boot partition device, this cannot be autodetected!\nPlease redo grub installation for all partitions you need it!" 14 55 7 $DEVS 2>$ANSWER || return 1
        bootpart=$(cat $ANSWER)
    fi
    bootpart=$(mapdev $bootpart)
    bootdev=$(mapdev $ROOTDEV)
    if [ "$bootpart" = "" ]; then
        _dia_DIALOG --msgbox "Error: Missing/Invalid root device: $bootpart" 0 0
        return 1
    fi
    if [ "$bootpart" = "DEVICE NOT FOUND" -o "$bootdev" = "DEVICE NOT FOUND" ]; then
        _dia_DIALOG --msgbox "GRUB root and setup devices could not be auto-located.  You will need to manually run the GRUB shell to install a bootloader." 0 0
        return 1
    fi
    $TARGET_DIR/sbin/grub --no-floppy --batch >/tmp/grub.log 2>&1 <<EOF
root $bootpart
setup $bootdev
quit
EOF
    cat /tmp/grub.log >$LOG
    # unfreeze xfs filesystems
    if [ -x /usr/sbin/xfs_freeze ]; then
        /usr/sbin/xfs_freeze -u $TARGET_DIR/boot > /dev/null 2>&1
        /usr/sbin/xfs_freeze -u $TARGET_DIR/ > /dev/null 2>&1
    fi

    if grep "Error [0-9]*: " /tmp/grub.log >/dev/null; then
        _dia_DIALOG --msgbox "Error installing GRUB. (see $LOG for output)" 0 0
        return 1
    fi
    notify "GRUB was successfully installed."
	return 0
}


# select_source(). taken from setup.  TODO: decouple ui
# displays installation source selection menu
# and sets up relevant config files
#
# params: none
# returns: nothing
interactive_select_source()   
{
	var_PKG_SOURCE_TYPE=
        var_FILE_URL="file:///src/core/pkg"
        var_SYNC_URL=
        var_MIRRORLIST="/etc/pacman.d/mirrorlist"

    _dia_DIALOG --menu "Please select an installation source" 10 35 3 \
    "1" "CD-ROM or OTHER SOURCE" \
    "2" "FTP/HTTP" 2>$ANSWER

    case $(cat $ANSWER) in
        "1")
            var_PKG_SOURCE_TYPE="cd"
            ;;
        "2")  
            var_PKG_SOURCE_TYPE="ftp"
            ;;
    esac

    if [ "$var_PKG_SOURCE_TYPE" = "cd" ]; then
        TITLE="Arch Linux CDROM or OTHER SOURCE Installation"
        notify "Packages included on this disk have been mounted to /src/core/pkg. If you wish to use your own packages from another source, manually mount them there."
        if [ ! -d /src/core/pkg ]; then
            notify "Package directory /src/core/pkg is missing!"
            return 1
        fi
        echo "Using CDROM for package installation" >$LOG
    else
        TITLE="Arch Linux FTP/HTTP Installation"
        notify "If you wish to load your ethernet modules manually, please do so now in an another terminal."
   fi
   return 0
}


# select_mirror(). taken from setup.
# Prompt user for preferred mirror and set $var_SYNC_URL
#
# args: none
# returns: nothing
interactive_select_mirror() { 
        notify "Keep in mind ftp.archlinux.org is throttled.\nPlease select another mirror to get full download speed."
        # FIXME: this regex doesn't honor commenting
        MIRRORS=$(egrep -o '((ftp)|(http))://[^/]*' "${MIRRORLIST}" | sed 's|$| _|g')
        _dia_DIALOG --menu "Select an FTP/HTTP mirror" 14 55 7 \
                  $MIRRORS \
                  "Custom" "_" 2>$ANSWER || return 1
    local _server=$(cat $ANSWER)
    if [ "${_server}" = "Custom" ]; then
        _dia_DIALOG --inputbox "Enter the full URL to core repo." 8 65 \
                "ftp://ftp.archlinux.org/core/os/i686" 2>$ANSWER || return 1
        var_SYNC_URL=$(cat $ANSWER)
    else
        # Form the full URL for our mirror by grepping for the server name in
        # our mirrorlist and pulling the full URL out. Substitute 'core' in  
        # for the repository name, and ensure that if it was listed twice we 
        # only return one line for the mirror.
        var_SYNC_URL=$(egrep -o "${_server}.*" "${MIRRORLIST}" | sed 's/\$repo/core/g' | head -n1)
    fi
    echo "Using mirror: $var_SYNC_URL" >$LOG
}
