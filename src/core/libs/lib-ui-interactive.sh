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
		ask_option $DEFAULT "Configuration" '' \
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
	ask_option no "Clock configuration" "Is your hardware clock in UTC or local time?" "UTC" " " "local" " " || return 1
	HARDWARECLOCK=$ANSWER_OPTION

	# timezone?
	ask_timezone || return 1
	TIMEZONE=$ANSWER_TIMEZONE

	# set system clock from hwclock - stolen from rc.sysinit
	local HWCLOCK_PARAMS=""
	if [ "$HARDWARECLOCK" = "UTC" ]
	then
		HWCLOCK_PARAMS="$HWCLOCK_PARAMS --utc"
	else
		HWCLOCK_PARAMS="$HWCLOCK_PARAMS --localtime"
	fi

	if [ "$TIMEZONE" != "" -a -e "/usr/share/zoneinfo/$TIMEZONE" ]
	then
		/bin/rm -f /etc/localtime
		/bin/cp "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
	fi
	/sbin/hwclock --hctosys $HWCLOCK_PARAMS --noadjfile

	# display and ask to set date/time
	ask_datetime

	# save the time
	date -s "$ANSWER_DATETIME" || show_warning "Date/time setting failed" "Something went wrong when doing date -s $ANSWER_DATETIME"
	/sbin/hwclock --systohc $HWCLOCK_PARAMS --noadjfile

	return 0
}


interactive_autoprepare()
{
	DISCS=$(finddisks)
	if [ $(echo $DISCS | wc -w) -gt 1 ]
	then
		notify "Available Disks:\n\n$(_getavaildisks)\n"
		ask_option no 'Harddrive selection' "Select the hard drive to use" $(finddisks 1 _) || return 1
		DISC=$ANSWER_OPTION
	else
		DISC=$DISCS
	fi

	DISC=${DISC// /} # strip all whitespace.  we need this for some reason.TODO: find out why

	get_blockdevice_size $DISC SI
	FSOPTS=
	which `get_filesystem_program ext2`     &>/dev/null && FSOPTS="$FSOPTS ext2 Ext2"
	which `get_filesystem_program ext3`     &>/dev/null && FSOPTS="$FSOPTS ext3 Ext3"
	which `get_filesystem_program reiserfs` &>/dev/null && FSOPTS="$FSOPTS reiserfs Reiser3"
	which `get_filesystem_program xfs`      &>/dev/null && FSOPTS="$FSOPTS xfs XFS"
	which `get_filesystem_program jfs`      &>/dev/null && FSOPTS="$FSOPTS jfs JFS"
	which `get_filesystem_program vfat`     &>/dev/null && FSOPTS="$FSOPTS vfat VFAT"

	ask_number "Enter the size (MB) of your /boot partition.  Recommended size: 100MB\n\nDisk space left: $BLOCKDEVICE_SIZE MB" 16 $BLOCKDEVICE_SIZE || return 1
	BOOT_PART_SIZE=$ANSWER_NUMBER

	BLOCKDEVICE_SIZE=$(($BLOCKDEVICE_SIZE-$BOOT_PART_SIZE))

	ask_number "Enter the size (MB) of your swap partition.  Recommended size: 256MB\n\nDisk space left: $BLOCKDEVICE_SIZE MB" 1 $BLOCKDEVICE_SIZE || return 1
	SWAP_PART_SIZE=$ANSWER_NUMBER

        BLOCKDEVICE_SIZE=$(($BLOCKDEVICE_SIZE-$SWAP_PART_SIZE))

	ROOT_PART_SET=""
	while [ "$ROOT_PART_SET" = "" ]
	do
		ask_number "Enter the size (MB) of your / partition.  Recommended size:7500.  The /home partition will use the remaining space.\n\nDisk space left:  $BLOCKDEVICE_SIZE MB" 1 $BLOCKDEVICE_SIZE || return 1
		ROOT_PART_SIZE=$ANSWER_NUMBER
		ask_yesno "$(($BLOCKDEVICE_SIZE-$ROOT_PART_SIZE)) MB will be used for your /home partition.  Is this OK?" yes && ROOT_PART_SET=1 #TODO: when doing yes, cli mode prints option JFS all the time, dia mode goes back to disks menu
        done

	CHOSEN_FS=""
	while [ "$CHOSEN_FS" = "" ]
	do
		ask_option no 'Filesystem selection' "Select a filesystem for / and /home:" $FSOPTS || return 1
		FSTYPE=$ANSWER_OPTION
		ask_yesno "$FSTYPE will be used for / and /home. Is this OK?" yes && CHOSEN_FS=1
        done

	ask_yesno "$DISC will be COMPLETELY ERASED!  Are you absolutely sure?" || return 1


	# we assume a /dev/hdX format (or /dev/sdX)
	PART_ROOT="${DISC}3"

	echo "$DISC $BOOT_PART_SIZE:ext2:+ $SWAP_PART_SIZE:swap $ROOT_PART_SIZE:$FSTYPE *:$FSTYPE" > $TMP_PARTITIONS

	echo "${DISC}1 raw no_label ext2;yes;/boot;target;no_opts;no_label;no_params"         >  $TMP_BLOCKDEVICES
	echo "${DISC}2 raw no_label swap;yes;no_mountpoint;target;no_opts;no_label;no_params" >> $TMP_BLOCKDEVICES
	echo "${DISC}3 raw no_label $FSTYPE;yes;/;target;no_opts;no_label;no_params"          >> $TMP_BLOCKDEVICES
	echo "${DISC}4 raw no_label $FSTYPE;yes;/home;target;no_opts;no_label;no_params"      >> $TMP_BLOCKDEVICES


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
        ask_option no 'Disc selection' "Select the disk you want to partition (select DONE when finished)" $DISCS || return 1
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
# At first I had the idea of a menu where all properties of a filesystem and you could pick one to update only that one (eg mountpoint, type etc)\
# but I think it's better to go through them all and by default always show the previous choice.
interactive_filesystem ()
{
	part=$1 # must be given and (scheduled to become) a valid device -> don't do [ -b "$1" ] because the device might not exist *yet*
	part_type=$2 # a part should always have a type
	part_label=$3 # can be empty
	fs=$4 # can be empty
	NEW_FILESYSTEM=
	if [ -z "$fs" ]
	then
		fs_type=
		fs_mountpoint=
		fs_opts=
		fs_label=
		fs_params=
	else
		ask_option edit "Alter $part ?" "Alter $part (type:$part_type, label:$part_label) ?" edit EDIT delete 'DELETE (revert to raw partition)'
		[ $? -gt 0 ] && NEW_FILESYSTEM=$fs && return 0
		if [ "$ANSWER_OPTION" = delete ]
		then
			NEW_FILESYSTEM=empty
			return 0
		else
			fs_type=`       cut -d ';' -f 1 <<< $fs`
			fs_create=`     cut -d ';' -f 2 <<< $fs` #not asked for to the user. this is always 'yes' for now
			fs_mountpoint=` cut -d ';' -f 3 <<< $fs`
			fs_mount=`      cut -d ';' -f 4 <<< $fs` #we dont need to ask this to the user. this is always 'target' for 99.99% of the users
			fs_opts=`       cut -d ';' -f 5 <<< $fs`
			fs_label=`      cut -d ';' -f 6 <<< $fs`
			fs_params=`     cut -d ';' -f 7 <<< $fs`
			[ "$fs_type"   = no_type   ] && fs_type=
			[ "$fs_mountpoint"  = no_mountpoint  ] && fs_mountpoint=
			[ "$fs_opts"   = no_opts   ] && fs_opts=
			[ "$fs_label"  = no_label  ] && fs_label=
			[ "$fs_params" = no_params ] && fs_params=
			old_fs_type=$fs_type
			old_fs_mountpoint=$fs_mountpoint
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
	[ $part_type = raw -o $part_type = lvm-lv -o $part_type = dm_crypt ] && which `get_filesystem_program swap`     &>/dev/null && FSOPTS="$FSOPTS swap Swap"
	[ $part_type = raw -o $part_type = lvm-lv -o $part_type = dm_crypt ] && which `get_filesystem_program ext2`     &>/dev/null && FSOPTS="$FSOPTS ext2 Ext2"
	[ $part_type = raw -o $part_type = lvm-lv -o $part_type = dm_crypt ] && which `get_filesystem_program ext3`     &>/dev/null && FSOPTS="$FSOPTS ext3 Ext3"
	[ $part_type = raw -o $part_type = lvm-lv -o $part_type = dm_crypt ] && which `get_filesystem_program reiserfs` &>/dev/null && FSOPTS="$FSOPTS reiserfs Reiser3"
	[ $part_type = raw -o $part_type = lvm-lv -o $part_type = dm_crypt ] && which `get_filesystem_program xfs`      &>/dev/null && FSOPTS="$FSOPTS xfs XFS"
	[ $part_type = raw -o $part_type = lvm-lv -o $part_type = dm_crypt ] && which `get_filesystem_program jfs`      &>/dev/null && FSOPTS="$FSOPTS jfs JFS"
	[ $part_type = raw -o $part_type = lvm-lv -o $part_type = dm_crypt ] && which `get_filesystem_program vfat`     &>/dev/null && FSOPTS="$FSOPTS vfat VFAT"
	[ $part_type = raw                        -o $part_type = dm_crypt ] && which `get_filesystem_program lvm-pv`   &>/dev/null && FSOPTS="$FSOPTS lvm-pv LVM_Physical_Volume"
	[ $part_type = lvm-pv                                              ] && which `get_filesystem_program lvm-vg`   &>/dev/null && FSOPTS="$FSOPTS lvm-vg LVM_Volumegroup"
	[ $part_type = lvm-vg                                              ] && which `get_filesystem_program lvm-lv`   &>/dev/null && FSOPTS="$FSOPTS lvm-lv LVM_Logical_Volume"
	[ $part_type = raw -o $part_type = lvm-lv                          ] && which `get_filesystem_program dm_crypt` &>/dev/null && FSOPTS="$FSOPTS dm_crypt DM_crypt_Volume"

		# determine FS
		fsopts=($FSOPTS);
		if [ ${#fsopts[*]} -lt 4 ] # less then 4 words in the $FSOPTS string. eg only one option
		then
			notify "Automatically picked the ${fsopts[1]} filesystem.  It's the only option for $part_type blockdevices" #TODO:  ${fsopts[1]} is empty when making an LV on a VG
			fs_type=${fsopts[0]}
		else
			default=
			[ -n "$fs_type" ] && default="--default-item $fs_type"
			ask_option no "Select filesystem" "Select a filesystem for $part:" $FSOPTS || return 1
			fs_type=$ANSWER_OPTION
		fi

		# ask mountpoint, if relevant
		if [[ $fs_type != lvm-* && "$fs_type" != dm_crypt && $fs_type != swap ]]
		then
			default=
			[ -n "$fs_mountpoint" ] && default="$fs_mountpoint"
			ask_string "Enter the mountpoint for $part" "$default" || return 1
			fs_mountpoint=$ANSWER_STRING
		fi

		# ask label, if relevant
		if [ "$fs_type" = lvm-vg -o "$fs_type" = lvm-lv -o "$fs_type" = dm_crypt ]
		then
			default=
			[ -n "$fs_label" ] && default="$fs_label"
			ask_string "Enter the label/name for this $fs_type on $part" "$default" 0 #TODO: check that you can't give LV's labels that have been given already or the installer will break
			fs_label=$ANSWER_STRING
		fi

		# ask special params, if relevant
		if [ "$fs_type" = lvm-vg ]
		then
			# add $part to $fs_params if it's not in there because the user wants this enabled by default
			pv=${part/+/}
			grep -q ":$pv:" <<< $fs_params || grep -q ":$pv\$" <<< $fs_params || fs_params="$fs_params:$pv"
			list=

			for pv in `sed 's/:/ /' <<< $fs_params`
			do
				list="$list $pv ^ ON"
			done
			for pv in `grep '+ lvm-pv' $TMP_BLOCKDEVICES | awk '{print $1}' | sed 's/\+$//'` # find PV's to be added: their blockdevice ends on + and has lvm-pv as type #TODO: i'm not sure we check which pv's are taken already
			do
				grep -q "$pv ^ ON" <<< "$list" || list="$list $pv - OFF"
			done
			list2=($list)
			if [ ${#list2[*]} -lt 6 ] # less then 6 words in the list. eg only one option
			then
				notify "Automatically picked PV ${list2[0]} to use for this VG.  It's the only available lvm PV"
				fs_params=${list2[0]}
			else
				ask_checklist "Which lvm PV's must this volume group span?" $list || return 1
				fs_params="$(sed 's/ /:/' <<< "$ANSWER_CHECKLIST")" #replace spaces by colon's, we cannot have spaces anywhere in any string
			fi
		fi
		if [ "$fs_type" = lvm-lv ]
		then
			[ -z "$fs_params" ] && default='5G'
			[ -n "$fs_params" ] && default="$fs_params"
			ask_string "Enter the size for this $fs_type on $part (suffix K,M,G,T,P,E. default is M)" "$default" || return 1
			fs_params=$ANSWER_STRING
		fi
		if [ "$fs_type" = dm_crypt ]
		then
			[ -z "$fs_params" ] && default='-c aes-xts-plain -y -s 512'
			[ -n "$fs_params" ] && default="${fs_params//_/ }"
			ask_string "Enter the options for this $fs_type on $part" "$default" || return 1
			fs_params="${ANSWER_STRING// /_}"
		fi

		# ask opts
		default=
		[ -n "$fs_opts" ] && default="$fs_opts"
		program=`get_filesystem_program $fs_type`
		ask_string "Enter any additional opts for $program" "$default" 0
		fs_opts=$(sed 's/ /_/g' <<< "$ANSWER_STRING") #TODO: clean up all whitespace (tabs and shit)

		[ -z "$fs_type"   ] && fs_type=no_type
		[ -z "$fs_mountpoint"  ] && fs_mountpoint=no_mountpoint
		[ -z "$fs_opts"   ] && fs_opts=no_opts
		[ -z "$fs_label"  ] && fs_label=no_label
		[ -z "$fs_params" ] && fs_params=no_params
		NEW_FILESYSTEM="$fs_type;yes;$fs_mountpoint;target;$fs_opts;$fs_label;$fs_params" #TODO: make re-creation yes/no asking available in this UI.

		# add new theoretical blockdevice, if relevant
		if [ "$fs_type" = lvm-vg ]
		then
			echo "/dev/mapper/$fs_label $fs_type $fs_label no_fs" >> $TMP_BLOCKDEVICES
		elif [ "$fs_type" = lvm-pv ]
		then
			echo "$part+ $fs_type no_label no_fs" >> $TMP_BLOCKDEVICES
		elif [ "$fs_type" = lvm-lv ]
		then
			echo "/dev/mapper/$part_label-$fs_label $fs_type no_label no_fs" >> $TMP_BLOCKDEVICES
		elif  [ "$fs_type" = dm_crypt ]
		then
			echo "/dev/mapper/$fs_label $fs_type no_label no_fs" >> $TMP_BLOCKDEVICES
		fi

		# TODO: cascading remove theoretical blockdevice(s), if relevant ( eg if we just changed from vg->ext3, dm_crypt -> fat, or if we changed the label of something, etc)
		if [[ $old_fs = lvm-* || $old_fs = dm_crypt ]] && [[ $fs != lvm-* && "$fs" != dm_crypt ]]
		then
			[ "$fs" = lvm-vg -o "$fs" = dm_cryp ] && target="/dev/mapper/$label"
			[ "$fs" = lvm-lv ] && target="/dev/mapper/$vg-$label" #TODO: $vg not set
			sed -i "#$target#d" $TMP_BLOCKDEVICES #TODO: check affected items, delete those, etc etc.
		fi
}

interactive_filesystems() {

	#notify "Available Disks:\n\n$(_getavaildisks)\n" quite useless here I think

	findpartitions 0 'no_fs' ' raw no_label' > $TMP_BLOCKDEVICES

	ALLOK=0
	while [ "$ALLOK" = 0 ]
	do
		# Let the user make filesystems and mountpoints
		USERHAPPY=0

		while [ "$USERHAPPY" = 0 ]
		do
			# generate a menu based on the information in the datafile
			menu_list=
			while read part type label fs
			do
				# leave out unneeded info from fs string
				fs_display=${fs//;yes/}
				fs_display=${fs//;target/}
				infostring="$type,$label,$fs_display"
				[ -b ${part/+/} ] && get_blockdevice_size ${part/+/} IEC && infostring="${BLOCKDEVICE_SIZE}MB,$infostring" # add size in MB for existing blockdevices (eg not for mapper devices that are not yet created yet) #TODO: ${BLOCKDEVICE_SIZE} is empty?
				menu_list="$menu_list $part $infostring" #don't add extra spaces, dialog doesn't like that.
			done < $TMP_BLOCKDEVICES

			ask_option no "Manage filesystems" "Here you can manage your filesystems, block devices and virtual devices (device mapper). Note that you don't *need* to specify opts, labels or extra params if you're not using lvm, dm_crypt, etc." $menu_list DONE _
			[ $? -gt 0                 ] && USERHAPPY=1 && break
			[ "$ANSWER_OPTION" == DONE ] && USERHAPPY=1 && break

			part=$ANSWER_OPTION

			declare part_escaped=${part//\//\\/} # escape all slashes otherwise awk complains
			declare part_escaped=${part_escaped/+/\\+} # escape the + sign too
			part_type=$( awk "/^$part_escaped/ {print \$2}" $TMP_BLOCKDEVICES)
			part_label=$(awk "/^$part_escaped/ {print \$3}" $TMP_BLOCKDEVICES)
			fs=$(        awk "/^$part_escaped/ {print \$4}" $TMP_BLOCKDEVICES)
			[ "$part_label" == no_label ] && part_label=
			[ "$fs"         == no_fs    ] && fs=

			if [ $part_type = lvm-vg ] # one lvm VG can host multiple LV's so that's a bit a special blockdevice...
			then
				list=
				if [ -n "$fs" ]
				then
					for lv in `sed 's/|/ /g' <<< $fs`
					do
						label=$(cut -d ';' -f 4 <<< $lv)
						mountpoint=$(cut -d ';' -f 2 <<< $lv)
						list="$list $label $mountpoint"
					done
				else
					list="XXX no-LV's-defined-yet-make-a-new-one"
				fi
				list="$list empty NEW"
				ask_option empty "Manage LV's on this VG" "Edit/create new LV's on this VG:" $list
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
			sed -i "s#^$part $part_type $part_label.*#$part $part_type $part_label $fs#" $TMP_BLOCKDEVICES # '#' is a forbidden character !

		done

		# Check all conditions that need to be fixed and ask the user if he wants to go back and correct them
		errors=
		warnings=

		grep -q ';/boot;' $TMP_BLOCKDEVICES || warnings="$warnings\n-No separate /boot filesystem"
		grep -q ';/;'     $TMP_BLOCKDEVICES || errors="$errors\n-No filesystem with mountpoint /"
		grep -q ' swap;'  $TMP_BLOCKDEVICES || grep -q '|swap;' $TMP_BLOCKDEVICES || warnings="$warnings\n-No swap partition defined"

		if [ -n "$errors$warnings" ]
		then
			str="The following issues have been detected:\n"
			[ -n "$errors" ] && str="$str\n - Errors: $errors"
			[ -n "$warnings" ] && str="$str\n - Warnings: $warnings"
			ask_yesno "$str\n Do you want to back to fix (one of) these issues?" || ALLOK=1 # TODO: we should ask the user if he wants to continue, return or abort.
		else
			ALLOK=1
		fi

	done


	process_filesystems && notify "Partitions were successfully created." && return 0
	show_warning "Filesystem processing" "Something went wrong while processing the filesystems"
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
    target_prepare_pacman || ( show_warning 'Pacman preparation failure' "Pacman preparation failed! Check $LOG for errors." && return 1 )

    # show group listing for group selection, base is ON by default, all others are OFF
    local _catlist="base ^ ON"
    for i in $($PACMAN -Sg | sed "s/^base$/ /g"); do
        _catlist="${_catlist} ${i} - OFF"
    done

    ask_checklist "Select Package Categories\nDO NOT deselect BASE unless you know what you're doing!" $_catlist || return 1
    _catlist=$ANSWER_CHECKLIST # _catlist now contains all categories (the tags from the dialog checklist)

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

    ask_checklist "Select Packages To Install." $_pkglist || return 1
	TARGET_PACKAGES=$ANSWER_CHECKLIST # contains now all package names
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

    ask_option no "Interface selection" "Select a network interface" $ifaces || return 1 #TODO: code used originaly --nocancel here. what's the use? + make ok button 'select'
    INTERFACE=$ANSWER_OPTION


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
            ask_string "Enter your IP address" "192.168.0.2" || return 1
            IPADDR=$ANSWER_STRING
            ask_string "Enter your netmask" "255.255.255.0" || return 1
            SUBNET=$ANSWER_STRING
            ask_string "Enter your broadcast" "192.168.0.255" || return 1
            BROADCAST=$ANSWER_STRING
            ask_string "Enter your gateway (optional)" "192.168.0.1" 0 || return 1
            GW=$ANSWER_STRING
            ask_string "Enter your DNS server IP" "192.168.0.1" || return 1
            DNS=$ANSWER_STRING
            ask_string "Enter your HTTP proxy server, for example:\nhttp://name:port\nhttp://ip:port\nhttp://username:password@ip:port\n\n Leave the field empty if no proxy is needed to install." 0 || return 1
            PROXY_HTTP=$ANSWER_STRING
            ask_string "Enter your FTP proxy server, for example:\nhttp://name:port\nhttp://ip:port\nhttp://username:password@ip:port\n\n Leave the field empty if no proxy is needed to install." 0 || return 1
            PROXY_FTP=$ANSWER_STRING
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
    ask_option no "Boot device selection" "Select the boot device where the GRUB bootloader will be installed (usually the MBR and not a partition)." $DEVS || return 1
    ROOTDEV=$ANSWER_OPTION
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
            ask_string "Enter the full path to your root device" "/dev/sda3" || return 1
            bootpart=$ANSWER_STRING
        else
            bootpart=$PART_ROOT
        fi
    fi
    ask_yesno "Do you have your system installed on software raid?\nAnswer 'YES' to install grub to another hard disk." no
    if [ $? -eq 0 ]; then
        ask_option no "Boot partition device selection" "Please select the boot partition device, this cannot be autodetected!\nPlease redo grub installation for all partitions you need it!" $DEVS || return 1
        bootpart=$ANSWER_OPTION
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


# select_source(). taken from setup.
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

	ask_option no "Source selection" "Please select an installation source" \
    "1" "CD-ROM or OTHER SOURCE" \
    "2" "FTP/HTTP" || return 1

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
        ask_option no "Mirror selection" "Select an FTP/HTTP mirror" $MIRRORS "Custom" "_" || return 1
    local _server=$ANSWER_OPTION
    if [ "${_server}" = "Custom" ]; then
        ask_string "Enter the full URL to core repo." "ftp://ftp.archlinux.org/core/os/i686" || return 1
        var_SYNC_URL=$ANSWER_STRING
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
	ask_option no "Text editor selection" "Select a Text Editor to Use" \
	"1" "nano (easier)" \
	"2" "vi" 
	case $ANSWER_OPTION in
		"1") EDITOR="nano" ;;
		"2") EDITOR="vi" ;;
		*)   EDITOR="nano" ;;
	esac
}
