#!/bin/sh
#TODO: get backend code out of here!!


# check if a worker has completed successfully. if not -> tell user he must do it + return 1
# if ok -> don't warn anything and return 0
check_depend ()
{
	[ -z "$1" -o -z "$2" ] && die_error "Use the check_depend function like this: check_depend <type> <name> with type=phase/worker"
	[ "$1" != phase -a "$1" != worker ] && die_error "check_depend's first argument must be a valid type (phase/worker)"

	ended_ok $1 $2 && return 0
	subject="$1 $2"
	title=$1_$2_title
	[ -n "${!title}" ] && subject="'${!title}'"
	show_warning "Cannot Continue.  Going back to $2" "You must do $subject first before going here!." && return 1
}


interactive_configure_system()
{
	[ "$EDITOR" ] || interactive_get_editor
	FILE=""

	# main menu loop
	while true; do
		DEFAULT=no
		[ -n "$FILE" ] &&  DEFAULT="$FILE"
		ask_option $DEFAULT "Configuration"  \
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
		"Return"        "Return to Main Menu" || FILE="Return"
		FILE=$ANSWER_OPTION

		if [ "$FILE" = "Return" -o -z "$FILE" ]; then       # exit
			break
		elif [ "$FILE" = "Root-Password" ]; then            # non-file
			while true; do
				chroot ${var_TARGET_DIR} passwd root && break
			done
		else                                                #regular file
			$EDITOR ${var_TARGET_DIR}${FILE}
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
	ask_option no "Is your hardware clock in UTC or local time?" \
        "UTC" " " \
        "local" " " \
        || return 1
    HARDWARECLOCK=$ANSWER_OPTION

    # timezone?
    TIMEZONE=`tzselect` || return 1


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
        notify "Available Disks:\n\n$(_getavaildisks)\n"
        ask_option no "Select the hard drive to use" $(finddisks 1 _) || return 1
        DISC=$ANSWER_OPTION
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
            ask_string "Enter the size (MB) of your /boot partition.  Minimum value is 16.\n\nDisk space left: $DISC_SIZE MB" "32" || return 1
            BOOT_PART_SIZE=$ANSWER_STRING
            if [ "$BOOT_PART_SIZE" = "" ]; then
                notify "ERROR: You have entered an invalid size, please enter again."
            else
                if [ "$BOOT_PART_SIZE" -ge "$DISC_SIZE" -o "$SBOOT_PART_SIZE" = "$DISC_SIZE" ]; then
                    notify "ERROR: You have entered a too large size, please enter again."
                   elif [ "$BOOT_PART_SIZE" -lt "16" ];
                   then
                   	notify "ERROR: You have entered a too small size, please enter again."
                else
                    BOOT_PART_SET=1
                fi
            fi
        done
        DISC_SIZE=$(($DISC_SIZE-$BOOT_PART_SIZE))
        while [ "$SWAP_PART_SET" = "" ]; do
            ask_string "Enter the size (MB) of your swap partition.  Minimum value is > 0.\n\nDisk space left: $DISC_SIZE MB" "256" || return 1
            SWAP_PART_SIZE=$ANSWER_STRING
            if [ "$SWAP_PART_SIZE" = "" -o  "$SWAP_PART_SIZE" -le "0" ]; then
                notify "ERROR: You have entered an invalid size, please enter again."
            else
                if [ "$SWAP_PART_SIZE" -ge "$DISC_SIZE" ]; then
                    notify "ERROR: You have entered a too large size, please enter again."
                else
                    SWAP_PART_SET=1
                fi
            fi
        done
        DISC_SIZE=$(($DISC_SIZE-$SWAP_PART_SIZE))
        while [ "$ROOT_PART_SET" = "" ]; do
            ask_string "Enter the size (MB) of your / partition.  The /home partition will use the remaining space.\n\nDisk space left:  $DISC_SIZE MB" "7500" || return 1
            ROOT_PART_SIZE=$ANSWER_STRING
            if [ "$ROOT_PART_SIZE" = "" -o "$ROOT_PART_SIZE" -le "0" ]; then
                notify "ERROR: You have entered an invalid size, please enter again."
            else
                if [ "$ROOT_PART_SIZE" -ge "$DISC_SIZE" ]; then
                    notify "ERROR: You have entered a too large size, please enter again."
                else
                    ask_yesno "$(($DISC_SIZE-$ROOT_PART_SIZE)) MB will be used for your /home partition.  Is this OK?" && ROOT_PART_SET=1
                fi
            fi
        done
        while [ "$CHOSEN_FS" = "" ]; do
            ask_option "Select a filesystem for / and /home:" $FSOPTS || return 1
            FSTYPE=$ANSWER_OPTION
            ask_yesno "$FSTYPE will be used for / and /home. Is this OK?" && CHOSEN_FS=1
        done
        SET_DEFAULTFS=1
    done

    ask_yesno "$DISC will be COMPLETELY ERASED!  Are you absolutely sure?" || return 1


	# we assume a /dev/hdX format (or /dev/sdX)
	PART_ROOT="${DISC}3"

	echo "$DISC $BOOT_PART_SIZE:ext2:+ $SWAP_PART_SIZE:swap $ROOT_PART_SIZE:$FSTYPE *:$FSTYPE" > $TMP_PARTITIONS
	echo "${DISC}1:ext2:/boot:yes:target"     >$TMP_FILESYSTEMS
	echo "${DISC}2:swap:null:yes:target"      >$TMP_FILESYSTEMS
	echo "${DISC}3:$FSTYPE:/:yes:target"      >$TMP_FILESYSTEMS
	echo "${DISC}4:$FSTYPE:/home:yes:target"  >$TMP_FILESYSTEMS


	process_disks       || die_error "Something went wrong while partitioning"
	process_filesystems || die_error "Something went wrong while processing the filesystems"
	notify "Auto-prepare was successful"
	return 0

}


interactive_partition() {
    target_umountall

    # Select disk to partition
    DISCS=$(finddisks 1 _)
    DISCS="$DISCS OTHER - DONE +"
    notify "Available Disks:\n\n$(_getavaildisks)\n"
    DISC=""
    while true; do
        # Prompt the user with a list of known disks
        ask_option no "Select the disk you want to partition (select DONE when finished)" $DISCS || return 1
        DISC=$ANSWER_OPTION
        if [ "$DISC" = "OTHER" ]; then
            ask_string "Enter the full path to the device you wish to partition" "/dev/sda" || return 1
            DISC=$ANSWER_STRING
        fi
        # Leave our loop if the user is done partitioning
        [ "$DISC" = "DONE" ] && break
        # Partition disc
        notify "Now you'll be put into the cfdisk program where you can partition your hard drive. You should make a swap partition and as many data partitions as you will need.\
        NOTE: cfdisk may tell you to reboot after creating partitions.  If you need to reboot, just re-enter this install program, skip this step and go on to the mountpoints selection step."
        cfdisk $DISC
    done
    return 0
}


# create new, delete, or edit a filesystem
interactive_filesystem ()
{
	part=$1 # must be given and a valid device
	part_type=$2 # a part should always have a type
	part_label=$3 # can be empty
	fs=$4 # can be empty
	NEW_FILESYSTEM=
	real_part=${part/+/} # strip away an extra '+' which is used for lvm pv's
	[ -b $real_part ] || die_error "interactive_filesystem \$1 must be a blockdevice! ($part given)"
	if [ -z "$fs" ]
	then
		fs_type=
		fs_mount=
		fs_opts=
		fs_label=
		fs_params=
	else
		ask_option edit "Alter $part (type:$part_type,label:$part_label) ?" edit EDIT delete 'DELETE (revert to raw partition)'
		[ $? -gt 0 ] && NEW_FILESYSTEM=$fs && return 0
		if [ "$ANSWER_OPTION" = delete ]
		then
			NEW_FILESYSTEM=empty
			return 0
		else
			fs_type=`  cut -d ';' -f 1 <<< $fs`
			fs_mount=` cut -d ';' -f 2 <<< $fs`
			fs_opts=`  cut -d ';' -f 3 <<< $fs`
			fs_label=` cut -d ';' -f 4 <<< $fs`
			fs_params=`cut -d ';' -f 5 <<< $fs`
			[ "$fs_type"   = no_type   ] && fs_type=
			[ "$fs_mount"  = no_mount  ] && fs_mount=
			[ "$fs_opts"   = no_opts   ] && fs_opts=
			[ "$fs_label"  = no_label  ] && fs_label=
			[ "$fs_params" = no_params ] && fs_params=
			old_fs_type=$fs_type
			old_fs_mount=$fs_mount
			old_fs_opts=$fs_opts
			old_fs_label=$fs_label
			old_fs_params=$fs_params
		fi
	fi

	# Possible filesystems/software layers on partitions/block devices

	# name        on top of             mountpoint?    label?        DM device?                     theoretical device?                        opts?      special params?

	# swap        raw/lvm-lv/dm_crypt   no             no            no                             no                                         no         no
	# ext 2       raw/lvm-lv/dm_crypt   optional       optional      no                             no                                         optional   no
	# ext 3       raw/lvm-lv/dm_crypt   optional       optional      no                             no                                         optional   no
	# reiserFS    raw/lvm-lv/dm_crypt   optional       optional      no                             no                                         optional   no
	# xfs         raw/lvm-lv/dm_crypt   optional       optional      no                             no                                         optional   no
	# jfs         raw/lvm-lv/dm_crypt   optional       optional      no                             no                                         optional   no
	# vfat        raw/lvm-lv/dm_crypt   optional       opt i guess   no                             no                                         optional   no
	# lvm-pv      raw/dm_crypt          no             no            no.  $pv = $part               $part+ (+ is to differentiate from $part)  optional   no
	# lvm-vg      lvm-pv                no             yes           /dev/mapper/$label             =dm device                                 optional   PV's to use
	# lvm-lv      lvm-vg                no             yes           /dev/mapper/$part_label-$label =dm device                                 optional   LV size
	# dm_crypt    raw/rvm-lv            no             yes           /dev/mapper/$label             =dm device                                 optional   no


	# Determine which filesystems/blockdevices are possible for this blockdevice
	FSOPTS=
	[ $part_type = raw -o $part_type = lvm-lv -o $part_type = dm_crypt ] && which mkfs.ext2  &>/dev/null && FSOPTS="$FSOPTS ext2 Ext2"
	[ $part_type = raw -o $part_type = lvm-lv -o $part_type = dm_crypt ] && which mkfs.ext3  &>/dev/null && FSOPTS="$FSOPTS ext3 Ext3"
	[ $part_type = raw -o $part_type = lvm-lv -o $part_type = dm_crypt ] && which mkreiserfs &>/dev/null && FSOPTS="$FSOPTS reiserfs Reiser3"
	[ $part_type = raw -o $part_type = lvm-lv -o $part_type = dm_crypt ] && which mkfs.xfs   &>/dev/null && FSOPTS="$FSOPTS xfs XFS"
	[ $part_type = raw -o $part_type = lvm-lv -o $part_type = dm_crypt ] && which mkfs.jfs   &>/dev/null && FSOPTS="$FSOPTS jfs JFS"
	[ $part_type = raw -o $part_type = lvm-lv -o $part_type = dm_crypt ] && which mkfs.vfat  &>/dev/null && FSOPTS="$FSOPTS vfat VFAT"
	[ $part_type = raw                        -o $part_type = dm_crypt ] && which pvcreate   &>/dev/null && FSOPTS="$FSOPTS lvm-pv LVM_Physical_Volume"
	[ $part_type = lvm-pv                                              ] && which vgcreate   &>/dev/null && FSOPTS="$FSOPTS lvm-vg LVM_Volumegroup"
	[ $part_type = lvm-vg                                              ] && which lvcreate   &>/dev/null && FSOPTS="$FSOPTS lvm-lv LVM_Logical_Volume"
	[ $part_type = raw -o $part_type = lvm-lv                          ] && which cryptsetup &>/dev/null && FSOPTS="$FSOPTS dm_crypt DM_crypt_Volume"

		# determine FS
		fsopts=($FSOPTS);
		if [ ${#fsopts[*]} -lt 4 ] # less then 4 words in the $FSOPTS string. eg only one option
		then
			notify "Automatically picked ${fsopts[1]}.  It's the only option for $part_type blockdevices"
			fs_type=${fsopts[0]}
		else
			default=
			[ -n "$fs_type" ] && default="--default-item $fs_type"
			ask_option no "Select a filesystem for $part:" $FSOPTS || return 1
			fs_type=$ANSWER_OPTION
		fi

		# ask mountpoint, if relevant
		if [[ $fs_type != lvm-* && "$fs_type" != dm_crypt ]]
		then
			default=
			[ -n "$fs_mount" ] && default="$fs_mount"
			ask_string "Enter the mountpoint for $part" "$default" || return 1
			fs_mount=$ANSWER_STRING
		fi

		# ask label, if relevant
		if [ "$fs_type" = lvm-vg -o "$fs_type" = lvm-lv -o "$fs_type" = dm_crypt ]
		then
			default=
			[ -n "$fs_label" ] && default="$fs_label"
			ask_string "Enter the label/name for $part" "$default" 0 #TODO: check that you can't give LV's labels that have been given already or the installer will break
			fs_label=$ANSWER_STRING
		fi

		# ask special params, if relevant
		if [ "$fs_type" = lvm-vg ]
		then
			# add $part to $fs_params if it's not in there because the user wants this enabled by default
			pv=${part/+/}
			grep -q ":$pv:" <<< $fs_params || grep -q ":$pv\$" <<< $fs_params || fs_params="$fs_params:$pv"

			for pv in `sed 's/:/ /' <<< $fs_params`
			do
				list="$list $pv ON"
			done
			for pv in `grep '+ lvm-pv' $BLOCK_DATA | awk '{print $1}' | sed 's/\+$//'` # find PV's to be added: their blockdevice ends on + and has lvm-pv as type
			do
				grep -q "$pv ON" <<< "$list" || list="$list $pv OFF"
			done
			ask_checklist "Which lvm PV's must this volume group span?" $list || return 1
			fs_params="$(sed 's/ /:/' <<< "$ANSWER_CHECKLIST")" #replace spaces by colon's, we cannot have spaces anywhere in any string
		fi
		if [ "$fs_type" = lvm-lv ]
		then
			[ -z "$fs_params" ] && default='5G'
			[ -n "$fs_params" ] && default="$fs_params"
			ask_string "Enter the size for this $fs_type on $part (suffix K,M,G,T,P,E. default is M)" "$default" || return 1
			fs_params=$ANSWER_STRING
		fi

		# ask opts
		default=
		[ -n "$fs_opts" ] && default="$fs_opts"
		program=`get_filesystem_program $fs_type`
		ask_string "Enter any additional opts for $program" "$default" 0
		fs_opts=$(sed 's/ /_/g' <<< "$ANSWER_STRING") #TODO: clean up all whitespace (tabs and shit)

		[ -z "$fs_type"   ] && fs_type=no_type
		[ -z "$fs_mount"  ] && fs_mount=no_mount
		[ -z "$fs_opts"   ] && fs_opts=no_opts
		[ -z "$fs_label"  ] && fs_label=no_label
		[ -z "$fs_params" ] && fs_params=no_params
		NEW_FILESYSTEM="$fs_type;$fs_mount;$fs_opts;$fs_label;$fs_params"

		# add new theoretical blockdevice, if relevant
		if [ "$fs_type" = lvm-vg ]
		then
			echo "/dev/mapper/$fs_label $fs_type $fs_label no_fs" >> $BLOCK_DATA
		elif [ "$fs_type" = lvm-pv ]
		then
			echo "$part+ $fs_type no_label no_fs" >> $BLOCK_DATA
		elif [ "$fs_type" = lvm-lv ]
		then
			echo "/dev/mapper/$part_label-$fs_label $fs_type no_label no_fs" >> $BLOCK_DATA
		elif  [ "$fs_type" = dm_crypt ]
		then
			echo "/dev/mapper/$fs_label $fs_type no_label no_fs" >> $BLOCK_DATA
		fi

		# TODO: cascading remove theoretical blockdevice(s), if relevant ( eg if we just changed from vg->ext3, dm_crypt -> fat, or if we changed the label of something, etc)
		if [[ $old_fs = lvm-* || $old_fs = dm_crypt ]] && [[ $fs != lvm-* && "$fs" != dm_crypt ]]
		then
			[ "$fs" = lvm-vg -o "$fs" = dm_cryp ] && target="/dev/mapper/$label"
			[ "$fs" = lvm-lv ] && target="/dev/mapper/$vg-$label" #TODO: $vg not set
			sed -i "#$target#d" $BLOCK_DATA #TODO: check affected items, delete those, etc etc.
		fi
}

interactive_filesystems() {

	notify "Available Disks:\n\n$(_getavaildisks)\n"

	# Let the user make filesystems and mountpoints
	USERHAPPY=0
	BLOCK_DATA=/home/arch/aif/runtime/.blockdata

	# $BLOCK_DATA entry. easily parsable.:
	# <blockdevice> type label/no_label <FS-string>/no_fs
	# FS-string:
	# type;mountpoint;opts;label;params[|FS-string|...] where opts have _'s instead of whitespace

	findpartitions 0 'no_fs' ' raw no_label' > $BLOCK_DATA
	while [ "$USERHAPPY" = 0 ]
	do
		# generate a menu based on the information in the datafile
		menu_list=
		while read part type label fs
		do
			get_blockdevice_size ${part/+/}
			menu_list="$menu_list $part size:${BLOCKDEVICE_SIZE}MB,type:$type,label:$label,fs:$fs" #don't add extra spaces, dialog doesn't like that.
		done < $BLOCK_DATA

		ask_option no "Manage filesystems, block devices and virtual devices. Note that you don't *need* to specify opts, labels or extra params if you're not using lvm, dm_crypt, etc." $menu_list DONE _
		[ $? -gt 0                 ] && USERHAPPY=1 && break
		[ "$ANSWER_OPTION" == DONE ] && USERHAPPY=1 && break

		part=$ANSWER_OPTION

		declare part_escaped=${part//\//\\/} # escape all slashes otherwise awk complains
		declare part_escaped=${part_escaped/+/\\+} # escape the + sign too
		part_type=$( awk "/^$part_escaped/ {print \$2}" $BLOCK_DATA)
		part_label=$(awk "/^$part_escaped/ {print \$3}" $BLOCK_DATA)
		fs=$(        awk "/^$part_escaped/ {print \$4}" $BLOCK_DATA)
		[ "$part_label" == no_label ] && part_label=
		[ "$fs"         == no_fs    ] && fs=

		if [ $part_type = lvm-vg ] # one lvm VG can host multiple LV's so that's a bit a special blockdevice...
		then
			list=
			if [ -n "$fs" ]
			then
				for lv in `sed '/|/ /' <<< $fs`
				do
					label=$(cut -d ';' -f 4 <<< $lv)
					mountpoint=$(cut -d ';' -f 2 <<< $lv)
					list="$list $label $mountpoint"
				done
			else
				list="XXX no-LV's-defined-yet-make-a-new-one"
			fi
			list="$list empty NEW"
			ask_option empty "Edit/create new LV's on this VG:" $list
			if [ "$ANSWER_OPTION" = XXX -o "$ANSWER_OPTION" = empty  ]
			then
				# a new LV must be created on this VG
				if interactive_filesystem $part $part_type $part_label '' 
				then
					[ -z "$fs" ] && fs=$NEW_FILESYSTEM
					[ -n "$fs" ] && fs="$fs|$NEW_FILESYSTEM"
				fi
			else
				# an existing LV will be edited and it's settings updated
				for lv in `sed '/|/ /' <<< $fs`
				do
					label=$(cut -d ';' -f 4 <<< $lv)
					[ "$label" = "$ANSWER_OPTION" ] && found_lv="$lv"
				done
				interactive_filesystem $part $part_type $part_label "$found_lv"
				fs=
				for lv in `sed '/|/ /' <<< $fs`
				do
					label=$(cut -d ';' -f 4 <<< $lv)
					add=$lv
					[ "$label" = "$ANSWER_OPTION" ] && add=$NEW_FILESYSTEM
					[ -z "$fs" ] && fs=$add
					[ -n "$fs" ] && fs="$fs|$add"
				done
			fi
		else
			interactive_filesystem $part $part_type $part_label $fs
			[ $? -eq 0 ] && fs=$NEW_FILESYSTEM
		fi

		# update the menu # NOTE that part_type remains raw for basic filesystems!
		[ -z "$part_label" ] && part_label=no_label
		[ -z "$fs"         ] && fs=no_fs
		sed -i "s#^$part $part_type $part_label.*#$part $part_type $part_label $fs#" $BLOCK_DATA # '#' is a forbidden character !

	done

	# If the user has forgotten one or more fundamental ones, ask him now
	ALLOK=true
	# TODO: check all conditions that would make ALLOK untrue again
	while [ "$ALLOK" != "true" ]; do

        _dia_DIALOG --menu "Select the partition to use as swap" 21 50 13 NONE - $PARTS 2>$ANSWER || return 1
        PART=$(cat $ANSWER)
        PARTS="$(echo $PARTS | sed -e "s#${PART}\ _##g")"
        if [ "$PART" != "NONE" ]; then
            DOMKFS="no"
            ask_yesno "Would you like to create a filesystem on $PART?\n\n(This will overwrite existing data!)" && DOMKFS="yes"
            echo "$PART:swap:swap:$DOMKFS" >>/home/arch/aif/runtime/.parts
        fi

        _dia_DIALOG --menu "Select the partition to mount as /" 21 50 13 $PARTS 2>$ANSWER || return 1
        PART=$(cat $ANSWER)
        PARTS="$(echo $PARTS | sed -e "s#${PART}\ _##g")"
        PART_ROOT=$PART
        # Select root filesystem type
        _dia_DIALOG --menu "Select a filesystem for $PART" 13 45 6 $FSOPTS 2>$ANSWER || return 1
        FSTYPE=$(cat $ANSWER)
        DOMKFS="no"
        ask_yesno "Would you like to create a filesystem on $PART?\n\n(This will overwrite existing data!)" && DOMKFS="yes"
        echo "$PART:$FSTYPE:/:$DOMKFS" >>/home/arch/aif/runtime/.parts

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
                if grep ":$MP:" /home/arch/aif/runtime/.parts; then
                    notify "ERROR: You have defined 2 identical mountpoints! Please select another mountpoint."
                    MP=""
                fi
            done
            DOMKFS="no"
            ask_yesno "Would you like to create a filesystem on $PART?\n\n(This will overwrite existing data!)" && DOMKFS="yes"
            echo "$PART:$FSTYPE:$MP:$DOMKFS" >>file
            _dia_DIALOG --menu "Select any additional partitions to mount under your new root" 21 50 13 $PARTS DONE _ 2>$ANSWER || return 1
            PART=$(cat $ANSWER)
        done
        ask_yesno "Would you like to create and mount the filesytems like this?\n\nSyntax\n------\nDEVICE:TYPE:MOUNTPOINT:FORMAT\n\n$(for i in $(cat /home/arch/aif/runtime/.parts); do echo "$i\n";done)"  && PARTFINISH="DONE"
    done

	# TODO: should not need this anymore    target_umountall
	# TODO: prepend $var_TARGET_DIR before handing over
	# TODO: convert our format to what process_filesystems will understand

	process_filesystems && notify "Partitions were successfully created." && return 0
	show_warning "Something went wrong while processing the filesystems"
	return 1
}

# select_packages()
# prompts the user to select packages to install
#
# params: none
# returns: 1 on error
interactive_select_packages() {

    notify "Package selection is split into two stages.  First you will select package categories that contain packages you may be interested in.  Then you will be presented with a full list of packages for each category, allowing you to fine-tune.\n\n"

    # set up our install location if necessary and sync up
    # so we can get package lists
    target_prepare_pacman || ( notify "Pacman preparation failed! Check $LOG for errors." && return 1 )

    # show group listing for group selection, base is ON by default, all others are OFF
    local _catlist="base ^ ON"
    for i in $($PACMAN -Sg | sed "s/^base$/ /g"); do
        _catlist="${_catlist} ${i} - OFF"
    done

    _dia_DIALOG --checklist "Select Package Categories\nDO NOT deselect BASE unless you know what you're doing!" 19 55 12 $_catlist 2>$ANSWER || return 1
    _catlist="$(cat $ANSWER)" # _catlist now contains all categories (the tags from the dialog checklist)

    # assemble a list of packages with groups, marking pre-selected ones
    # <package> <group> <selected>
    local _pkgtmp="$($PACMAN -Sl core | awk '{print $2}')" # all packages in core repository
    local _pkglist=''

    $PACMAN -Si $_pkgtmp | awk '/^Name/{ printf("%s ",$3) } /^Group/{ print $3 }' > $ANSWER
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
	TARGET_PACKAGES="$(cat $ANSWER)" # contains now all package names
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
        notify "Cannot find any ethernet interfaces. This usually means udev was\nunable to load the module and you must do it yourself. Switch to\nanother VT, load the appropriate module, and run this step again."
        return 1
    fi

    _dia_DIALOG --nocancel --ok-label "Select" --menu "Select a network interface" 14 55 7 $ifaces 2>$ANSWER
    case $? in
        0) INTERFACE=$(cat $ANSWER) ;;
        *) return 1 ;;
    esac

    ask_yesno "Do you want to use DHCP?"
    if [ $? -eq 0 ]; then
        infofy "Please wait.  Polling for DHCP server on $INTERFACE..."
        killall dhcpd
        killall -9 dhcpd
        sleep 1
        dhcpcd $INTERFACE >$LOG 2>&1
        if [ $? -ne 0 ]; then
            notify "Failed to run dhcpcd.  See $LOG for details."
            return 1
        fi
        if [ ! $(ifconfig $INTERFACE | grep 'inet addr:') ]; then
            notify "DHCP request failed." || return 1
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
            ask_yesno "Are these settings correct?\n\nIP address:         $IPADDR\nNetmask:            $SUBNET\nGateway (optional): $GW\nDNS server:         $DNS\nHTTP proxy server:  $PROXY_HTTP\nFTP proxy server:   $PROXY_FTP"
            case $? in
                1) ;;
                0) NETPARAMETERS="1" ;;
            esac
        done
        echo "running: ifconfig $INTERFACE $IPADDR netmask $SUBNET broadcast $BROADCAST up" >$LOG
        ifconfig $INTERFACE $IPADDR netmask $SUBNET broadcast $BROADCAST up >$LOG 2>&1 || notify "Failed to setup $INTERFACE interface." || return 1
        if [ "$GW" != "" ]; then
            route add default gw $GW >$LOG 2>&1 || notify "Failed to setup your gateway." || return 1
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
	local grubmenu="$var_TARGET_DIR/boot/grub/menu.lst"
	[ ! -f $grubmenu ] && show_warning "No grub?" "Error: Couldn't find $grubmenu.  Is GRUB installed?" && return 1

    # try to auto-configure GRUB...
    if [ -n "$PART_ROOT" -a "$GRUB_OK" != '1' ] ; then
    GRUB_OK=0
        grubdev=$(mapdev $PART_ROOT)
        local _rootpart="${PART_ROOT}"
        local _uuid="$(getuuid ${PART_ROOT})"
        # attempt to use a UUID if the root device has one
        if [ -n "${_uuid}" ]; then
            _rootpart="/dev/disk/by-uuid/${_uuid}"
        fi
        # look for a separately-mounted /boot partition
        bootdev=$(mount | grep $var_TARGET_DIR/boot | cut -d' ' -f 1)
        if [ "$grubdev" != "" -o "$bootdev" != "" ]; then
            subdir=
            if [ "$bootdev" != "" ]; then
                grubdev=$(mapdev $bootdev)
            else
                subdir="/boot"
            fi
            # keep the file from being completely bogus
            if [ "$grubdev" = "DEVICE NOT FOUND" ]; then
                notify "Your root boot device could not be autodetected by setup.  Ensure you adjust the 'root (hd0,0)' line in your GRUB config accordingly."
                grubdev="(hd0,0)"
            fi
            # remove default entries by truncating file at our little tag (#-*)
            sed -i -e '/#-\*/q' $grubmenu
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

    notify "Before installing GRUB, you must review the configuration file.  You will now be put into the editor.  After you save your changes and exit the editor, you can install GRUB."
    [ "$EDITOR" ] || interactive_get_editor
    $EDITOR $grubmenu

    DEVS=$(finddisks 1 _)
    DEVS="$DEVS $(findpartitions 1 _)"
    if [ "$DEVS" = "" ]; then
        notify "No hard drives were found"
        return 1
    fi
    _dia_DIALOG --menu "Select the boot device where the GRUB bootloader will be installed (usually the MBR and not a partition)." 14 55 7 $DEVS 2>$ANSWER || return 1
    ROOTDEV=$(cat $ANSWER)
    infofy "Installing the GRUB bootloader..."
    cp -a $var_TARGET_DIR/usr/lib/grub/i386-pc/* $var_TARGET_DIR/boot/grub/
    sync
    # freeze xfs filesystems to enable grub installation on xfs filesystems
    if [ -x /usr/sbin/xfs_freeze ]; then
        /usr/sbin/xfs_freeze -f $var_TARGET_DIR/boot > /dev/null 2>&1
        /usr/sbin/xfs_freeze -f $var_TARGET_DIR/ > /dev/null 2>&1
    fi
    # look for a separately-mounted /boot partition
    bootpart=$(mount | grep $var_TARGET_DIR/boot | cut -d' ' -f 1)
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
        notify "Error: Missing/Invalid root device: $bootpart"
        return 1
    fi
    if [ "$bootpart" = "DEVICE NOT FOUND" -o "$bootdev" = "DEVICE NOT FOUND" ]; then
        notify "GRUB root and setup devices could not be auto-located.  You will need to manually run the GRUB shell to install a bootloader."
        return 1
    fi
    $var_TARGET_DIR/sbin/grub --no-floppy --batch >/tmp/grub.log 2>&1 <<EOF
root $bootpart
setup $bootdev
quit
EOF
    cat /tmp/grub.log >$LOG
    # unfreeze xfs filesystems
    if [ -x /usr/sbin/xfs_freeze ]; then
        /usr/sbin/xfs_freeze -u $var_TARGET_DIR/boot > /dev/null 2>&1
        /usr/sbin/xfs_freeze -u $var_TARGET_DIR/ > /dev/null 2>&1
    fi

    if grep "Error [0-9]*: " /tmp/grub.log >/dev/null; then
        notify "Error installing GRUB. (see $LOG for output)"
        return 1
    fi
    notify "GRUB was successfully installed."
    GRUB_OK=1
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

	ask_option no "Please select an installation source" \
    "1" "CD-ROM or OTHER SOURCE" \
    "2" "FTP/HTTP" 

    case $ANSWER_OPTION in
        "1") var_PKG_SOURCE_TYPE="cd" ;;
        "2") var_PKG_SOURCE_TYPE="ftp" ;;
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
        MIRRORS=$(egrep -o '((ftp)|(http))://[^/]*' "${var_MIRRORLIST}" | sed 's|$| _|g')
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
        var_SYNC_URL=$(egrep -o "${_server}.*" "${var_MIRRORLIST}" | sed 's/\$repo/core/g' | head -n1)
    fi
    echo "Using mirror: $var_SYNC_URL" >$LOG
}

# geteditor(). taken from original setup code. 
# prompts the user to choose an editor
# sets EDITOR global variable
#
interactive_get_editor() {
	ask_option no "Select a Text Editor to Use" \
	"1" "nano (easier)" \
	"2" "vi" 
	case $ANSWER_OPTION in
		"1") EDITOR="nano" ;;
		"2") EDITOR="vi" ;;
		*)   EDITOR="nano" ;;
	esac
}
