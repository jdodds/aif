#!/bin/bash
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

	 ## PREPROCESSING ##

	#TODO: only need to do this once.  check 'ended_ok worker configure_system' is not good because this could be done already even if worker did not exit 0
	# /etc/pacman.d/mirrorlist
	# add installer-selected mirror to the top of the mirrorlist
	if [ "$var_PKG_SOURCE_TYPE" = "ftp" -a "${var_SYNC_URL}" != "" ]; then
		debug 'PROCEDURE' "Adding choosen mirror (${var_SYNC_URL}) to ${var_TARGET_DIR}/$var_MIRRORLIST"
		mirrorlist=`awk "BEGIN { printf(\"# Mirror used during installation\nServer = "${var_SYNC_URL}"\n\n\") } 1 " "${var_TARGET_DIR}/$var_MIRRORLIST"`
		echo "$mirrorlist" > "${var_TARGET_DIR}/$var_MIRRORLIST" #TODO: test this, this may not work
	fi

	# /etc/rc.conf
	# Make sure timezone and utc info are what we want
	# NOTE: If a timezone string never contains more then 1 slash, we can use ${TIMEZONE/\//\\/}
	sed -i -e "s/^TIMEZONE=.*/TIMEZONE=\"${TIMEZONE//\//\\/}\"/g" \
	-e "s/^HARDWARECLOCK=.*/HARDWARECLOCK=\"$HARDWARECLOCK\"/g" \
	${var_TARGET_DIR}/etc/rc.conf

	# main menu loop
	while true; do
		DEFAULT=no
		[ -n "$FILE" ] &&  DEFAULT="$FILE"
		helptext="Note that if you want to change any file not listed here (unlikely) you can go to another tty and update ${var_TARGET_DIR}/etc/<filename> yourself"
		grep -q '^/dev/mapper' $TMP_FSTAB && helptext="$helptext\nDon't forget to add the appropriate modules for your /dev/mapper devices to mkinitcpio.conf" #TODO: we can improve this a bit
		ask_option $DEFAULT "Configuration" "$helptext" required \
		"/etc/rc.conf"                  "System Config" \
		"/etc/fstab"                    "Filesystem Mountpoints" \
		"/etc/mkinitcpio.conf"          "Initramfs Config" \
		"/etc/modprobe.d/modprobe.conf" "Kernel Modules" \
		"/etc/resolv.conf"              "DNS Servers" \
		"/etc/hosts"                    "Network Hosts" \
		"/etc/hosts.deny"               "Denied Network Services" \
		"/etc/hosts.allow"              "Allowed Network Services" \
		"/etc/locale.gen"               "Glibc Locales" \
		"/etc/pacman.conf"              "Pacman.conf" \
		"$var_MIRRORLIST"               "Pacman Mirror List" \
		"Root-Password"                 "Set the root password" \
		"Done"                          "Return to Main Menu" || return 1
		FILE=$ANSWER_OPTION

		if [ "$FILE" = "Done" ]; then       # exit
			break
		elif [ "$FILE" = "Root-Password" ]; then            # non-file
			while true; do
				chroot ${var_TARGET_DIR} passwd root && break
			done
		else                                                #regular file
			$EDITOR ${var_TARGET_DIR}${FILE}
		fi

		# if user edited /etc/rc.conf, add the hostname to /etc/hosts if it's not already there.
		# note that if the user edits rc.conf several times to change the hostname more then once, we will add them all to /etc/hosts.  this is not perfect, but to avoid this, too much code would be required (feel free to prove me wrong :))
		if [ "$FILE" = "/etc/rc.conf" ]
		then
			HOSTNAME=`sed -n '/^HOSTNAME/s/HOSTNAME=//p' ${var_TARGET_DIR}${FILE} | sed 's/"//g'`
			if ! grep '127\.0\.0\.1' ${var_TARGET_DIR}/etc/hosts | grep -q "$HOSTNAME"
			then
				sed -i "s/127\.0\.0\.1.*/& $HOSTNAME/" ${var_TARGET_DIR}/etc/hosts
			fi
		fi
	done

	# temporary backup files are not useful anymore past this point.
	find "${var_TARGET_DIR}/etc/" -name '*~' -delete &>/dev/null
	return 0
}


interactive_timezone () {
	ask_timezone || return 1
        TIMEZONE=$ANSWER_TIMEZONE
        infofy "Setting Timezone to $TIMEZONE"
		if [ -n "$TIMEZONE" -a -e "/usr/share/zoneinfo/$TIMEZONE" ]
		then
			# This changes probably also the systemtime (UTC->$TIMEZONE)!
			# localtime users will have a false time after that!
			/bin/rm -f /etc/localtime
			/bin/cp "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
		fi
}


interactive_time () {
        # utc or localtime?
        ask_option UTC "Clock configuration" "Is your hardware clock in UTC or local time? UTC is recommended" required "UTC" " " "localtime" " " || return 1
        HARDWARECLOCK=$ANSWER_OPTION
		# To avoid a false time for localtime users after above
		# we must re-read the hwclock value again, but now into the
		# correct timezone.
		[ "$HARDWARECLOCK" == "localtime" ] && dohwclock $HARDWARECLOCK hctosys

	NEXTITEM=
        while true; do
		current=$(date)
                default=no
                [ -n "$NEXTITEM" ] && default="$NEXTITEM"
                #TODO: only propose if network ok
                EXTRA=()
		type ntpdate &>/dev/null && EXTRA=('ntp' 'Set time and date using ntp')

                ask_option $default "Date/time configuration" "According to your settings and your hardwareclock, the date should now be $current.  If this is incorrect, you can correct this now" required \
                "${EXTRA[@]}" "manual" "Set time and date manually" "return" "Looks good. back to main menu" || return 1
                if [ "$ANSWER_OPTION" = ntp ]
                then
			if ntpdate pool.ntp.org >/dev/null 
			then
				notify "Synced clock with internet pool successfully."
				dohwclock $HARDWARECLOCK systohc && NEXTITEM=3
			else
				show_warning 'Ntp failure' "An error has occured, time was not changed!"
			fi
		fi
		if [ "$ANSWER_OPTION" = manual ]
		then
			ask_datetime 
			if date -s "$ANSWER_DATETIME"
			then
				dohwclock $HARDWARECLOCK systohc && NEXTITEM=3
			else
				show_warning "Date/time setting failed" "Something went wrong when doing date -s $ANSWER_DATETIME" 
			fi
		fi
                [ "$ANSWER_OPTION" = return ] && break
        done
}


interactive_prepare_disks ()
{
	DONE=0
	ret=1 # 1 means unsuccessful. 0 for ok
	NEXTITEM=
	DISK_CONFIG_TYPE=
	[ "$BLOCK_ROLLBACK_USELESS" = "0" ] && show_warning "Rollback may be needed" "It seems you already went here.  You should probably rollback previous changes before reformatting, otherwise stuff will probably fail"
	while [ "$DONE" = "0" ]
	do
		rollbackstr=" (you don't need to do this)"
		[ "$BLOCK_ROLLBACK_USELESS" = "0" ] && rollbackstr=" (this will revert your last changes)"
		default=no
		[ -n "$NEXTITEM" ] && default="$NEXTITEM"

		#TODO: inform user (using dialog's --item-help or so) that autoprepare uses 1 disk and uses it in a "fairly regular" (though somewhat customizable) manner.
		ask_option $default "Prepare Hard Drive" '' required \
			"1" "Auto-Prepare (erases the ENTIRE hard drive and sets up partitions and filesystems)" \
			"2" "Partition Hard Drives" \
			"3" "Configure block devices, filesystems and mountpoints" \
			"4" "Rollback last filesystem changes$rollbackstr" \
			"5" "Return to Main Menu"

		case $ANSWER_OPTION in
			"1")
				[ "$BLOCK_ROLLBACK_USELESS" = "0" ] && ask_yesno "You should probably rollback your last changes first, otherwise this will probably fail.  Go back to menu to do rollback?" && NEXTITEM=4 && break;
				interactive_autoprepare && NEXTITEM=5 && ret=0 && DISK_CONFIG_TYPE=auto;; #TODO: for some reason. if this completes $?=0, next item will be 1 :/
			"2")
				[ "$BLOCK_ROLLBACK_USELESS" = "0" ] && ask_yesno "You should probably rollback your last changes first, otherwise this will probably fail.  Go back to menu to do rollback?" && NEXTITEM=4 && break;
				interactive_partition && ret=1 && NEXTITEM=3 && DISK_CONFIG_TYPE=manual
				;;
			"3")
				[ "$BLOCK_ROLLBACK_USELESS" = "0" ] && ask_yesno "You should probably rollback your last changes first, otherwise this will probably fail.  Go back to menu to do rollback?" && NEXTITEM=4 && break;
				PARTFINISH=""
				interactive_filesystems && ret=0 && NEXTITEM=5 && DISK_CONFIG_TYPE=manual
				;;
			"4")
				if [ "$BLOCK_ROLLBACK_USELESS" = "1" ]
				then
					ask_yesno "It seems like you haven't partitioned/formatted/mounted anything yet (or rolled back already).  This operation is useless (unless the installer is buggy), but it doesn't harm.  Do you want to continue?" || NEXTITEM=5
				fi
				if [ $? -eq 0 -o "$BLOCK_ROLLBACK_USELESS" = "0" ]
				then
					if rollback_filesystems #TODO: this part doesn't belong here. move it to ui-interactive. (interactive_rollback)
					then
						infofy "Rollback succeeded"
					else
						show_warning "Rollback failed" "Rollback failed"
					fi
				fi
				;;
			*)
				DONE=1 ;;
		esac
	done
	return $ret
}



interactive_autoprepare()
{
	DISCS=$(finddisks)
	if [ $(echo $DISCS | wc -w) -gt 1 ]
	then
		notify "Available Disks:\n\n$(_getavaildisks)\n"
		ask_option no 'Harddrive selection' "Select the hard drive to use" required $(finddisks 1 _) || return 1
		DISC=$ANSWER_OPTION
	else
		DISC=$DISCS
	fi

	DISC=${DISC// /} # strip all whitespace.  we need this for some reason.TODO: find out why

	get_blockdevice_size $DISC MiB
	FSOPTS=
	which `get_filesystem_program ext2`     &>/dev/null && FSOPTS="$FSOPTS ext2 Ext2"
	which `get_filesystem_program ext3`     &>/dev/null && FSOPTS="$FSOPTS ext3 Ext3"
	which `get_filesystem_program ext4`     &>/dev/null && FSOPTS="$FSOPTS ext4 Ext4"
	which `get_filesystem_program reiserfs` &>/dev/null && FSOPTS="$FSOPTS reiserfs Reiser3"
	which `get_filesystem_program xfs`      &>/dev/null && FSOPTS="$FSOPTS xfs XFS"
	which `get_filesystem_program jfs`      &>/dev/null && FSOPTS="$FSOPTS jfs JFS"
	which `get_filesystem_program vfat`     &>/dev/null && FSOPTS="$FSOPTS vfat VFAT"

	ask_number "Enter the size (MiB) of your /boot partition.  Recommended size: 100MiB\n\nDisk space left: $BLOCKDEVICE_SIZE MiB" 16 $BLOCKDEVICE_SIZE 100 || return 1
	BOOT_PART_SIZE=$ANSWER_NUMBER

	BLOCKDEVICE_SIZE=$(($BLOCKDEVICE_SIZE-$BOOT_PART_SIZE))

	ask_number "Enter the size (MiB) of your swap partition.  Recommended size: 256MiB\n\nDisk space left: $BLOCKDEVICE_SIZE MiB" 1 $BLOCKDEVICE_SIZE 256 || return 1
	SWAP_PART_SIZE=$ANSWER_NUMBER

        BLOCKDEVICE_SIZE=$(($BLOCKDEVICE_SIZE-$SWAP_PART_SIZE))

	ROOT_PART_SET=""
	while [ "$ROOT_PART_SET" = "" ]
	do
		ask_number "Enter the size (MiB) of your / partition.  Recommended size:7500.  The /home partition will use the remaining space.\n\nDisk space left:  $BLOCKDEVICE_SIZE MiB" 1 $BLOCKDEVICE_SIZE 7500 || return 1
		ROOT_PART_SIZE=$ANSWER_NUMBER
		ask_yesno "$(($BLOCKDEVICE_SIZE-$ROOT_PART_SIZE)) MiB will be used for your /home partition.  Is this OK?" yes && ROOT_PART_SET=1 #TODO: when doing yes, cli mode prints option JFS all the time, dia mode goes back to disks menu
        done

	CHOSEN_FS=""
	while [ "$CHOSEN_FS" = "" ]
	do
		ask_option no 'Filesystem selection' "Select a filesystem for / and /home:" required $FSOPTS || return 1
		FSTYPE=$ANSWER_OPTION
		ask_yesno "$FSTYPE will be used for / and /home. Is this OK?" yes && CHOSEN_FS=1
        done

	ask_yesno "$DISC will be COMPLETELY ERASED!  Are you absolutely sure?" || return 1


	echo "$DISC $BOOT_PART_SIZE:ext2:+ $SWAP_PART_SIZE:swap $ROOT_PART_SIZE:$FSTYPE *:$FSTYPE" > $TMP_PARTITIONS

	echo "${DISC}1 raw no_label ext2;yes;/boot;target;no_opts;no_label;no_params"         >  $TMP_BLOCKDEVICES
	echo "${DISC}2 raw no_label swap;yes;no_mountpoint;target;no_opts;no_label;no_params" >> $TMP_BLOCKDEVICES
	echo "${DISC}3 raw no_label $FSTYPE;yes;/;target;no_opts;no_label;no_params"          >> $TMP_BLOCKDEVICES
	echo "${DISC}4 raw no_label $FSTYPE;yes;/home;target;no_opts;no_label;no_params"      >> $TMP_BLOCKDEVICES


	process_disks       || die_error "Something went wrong while partitioning"
	if ! process_filesystems
	then
		show_warning "Filesystem processing" "Something went wrong while processing the filesystems.  Attempting rollback."
		if rollback_filesystems
		then
			show_warning "Filesystem rollback" "Rollback succeeded.  Please try to figure out what went wrong and try me again.  If you found a bug in the installer, please report it."
			return 1
		else
			die_error "Filesystem processing and rollback failed.  Please try the installer again.  If you found a bug in the installer, please report it."
		fi
	else
		notify "Auto-prepare was successful"
		return 0
	fi
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
        ask_option no 'Disc selection' "Select the disk you want to partition (select DONE when finished)" required $DISCS || return 1
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
	local part=$1       # must be given and (scheduled to become) a valid device -> don't do [ -b "$1" ] because the device might not exist *yet*
	local part_type=$2  # a part should always have a type
	local part_label=$3 # can be empty
	local fs_string=$4  # can be empty
	local fs_type=
	local fs_create
	local fs_mountpoint=
	local fs_mount
	local fs_opts=
	local fs_label=
	local fs_params=
	NEW_FILESYSTEM=
	if [ -n "$fs_string" ]
	then
		fs_type=`       cut -d ';' -f 1 <<< $fs_string`
		fs_create=`     cut -d ';' -f 2 <<< $fs_string` #not asked for to the user. this is always 'yes' for now
		fs_mountpoint=` cut -d ';' -f 3 <<< $fs_string`
		fs_mount=`      cut -d ';' -f 4 <<< $fs_string` #we dont need to ask this to the user. this is always 'target' for 99.99% of the users
		fs_opts=`       cut -d ';' -f 5 <<< $fs_string`
		fs_label=`      cut -d ';' -f 6 <<< $fs_string`
		fs_params=`     cut -d ';' -f 7 <<< $fs_string`
		[ "$fs_type"   = no_type             ] && fs_type=
		[ "$fs_mountpoint"  = no_mountpoint  ] && fs_mountpoint=
		[ "$fs_mount"  = no_mount            ] && fs_mount=
		[ "$fs_opts"   = no_opts             ] && fs_opts=
		[ "$fs_label"  = no_label            ] && fs_label=
		[ "$fs_params" = no_params           ] && fs_params=
		local old_fs_type=$fs_type
		local old_fs_create=$fs_create
		local old_fs_mountpoint=$fs_mountpoint
		local old_fs_mount=$fs_mount
		local old_fs_opts=$fs_opts
		local old_fs_label=$fs_label
		local old_fs_params=$fs_params

		ask_option edit "Alter this $fs_type filesystem on $part ?" \
		                "Alter $fs_type filesystem (label:$fs_label, mountpoint:$fs_mountpoint) on $part (type:$part_type, label:$part_label) ?" required \
		                edit EDIT delete DELETE #TODO: nicer display if label is empty etc

		# Don't alter, and return if user cancels
		[ $? -gt 0 ] && NEW_FILESYSTEM=$fs_string && return 0
		# Erase and return if that's what the user wants
		[ "$ANSWER_OPTION" = delete ] && NEW_FILESYSTEM=no_fs
	fi

	if [ "$NEW_FILESYSTEM" != no_fs ]
	then
		# Possible filesystems/software layers on partitions/block devices

		# name        on top of             mountpoint?    label?        DM device?                     theoretical device?                        opts?      special params?

		# swap        raw/lvm-lv/dm_crypt   no             no            no                             no                                         no         no
		# ext 2       raw/lvm-lv/dm_crypt   optional       optional      no                             no                                         optional   no
		# ext 3       raw/lvm-lv/dm_crypt   optional       optional      no                             no                                         optional   no
		# ext 4       raw/lvm-lv/dm_crypt   optional       optional      no                             no                                         optional   no
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
		[ $part_type = raw -o $part_type = lvm-lv -o $part_type = dm_crypt ] && which `get_filesystem_program ext4`     &>/dev/null && FSOPTS="$FSOPTS ext4 Ext4"
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
			notify "Automatically picked the ${fsopts[1]} filesystem.  It's the only option for $part_type blockdevices"
			fs_type=${fsopts[0]}
		else
			default=
			[ -n "$fs_type" ] && default="--default-item $fs_type"
			ask_option no "Select filesystem" "Select a filesystem for $part:" required $FSOPTS || return 1
			fs_type=$ANSWER_OPTION
		fi

		# ask mountpoint, if relevant
		if [[ $fs_type != lvm-* && "$fs_type" != dm_crypt && $fs_type != swap ]]
		then
			default=no
			[ -n "$fs_mountpoint" ] && default="$fs_mountpoint"
			ask_option $default "Select the mountpoint" "Select a mountpoint for $part" required / 'root' /boot 'files for booting' /etc 'config files' /home 'home directories' /tmp 'temporary files' custom 'enter a custom mountpoint' || return 1
			fs_mountpoint=$ANSWER_OPTION
			[ "$default" == 'no' ] && default=
			if [ "$ANSWER_OPTION" == custom ]
			then
				ask_string "Enter the custom mountpoint for $part" "$default" && fs_mountpoint=$ANSWER_STRING || return 1
			fi
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
			# add $part to $fs_params if it's not in there because the user wants this enabled by default. TODO: we should find something out so you can't disable $part. (would be weird to have a vg listed on $part and not have $part it fs_params)
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
			[ -z "$fs_params" ] && default='5000'
			[ -n "$fs_params" ] && default="$fs_params"
			ask_number "Enter the size for this $fs_type on $part in MiB" 1 0 "$default" || return 1 #TODO: can we get the upperlimit from somewhere?
			# Lvm tools use binary units but have their own suffixes ( K,M,G,T,P,E, but they mean KiB, MiB etc)
			fs_params="${ANSWER_NUMBER}M"
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

		[ -z "$fs_type"       ] && fs_type=no_type
		[ -z "$fs_mountpoint" ] && fs_mountpoint=no_mountpoint
		[ -z "$fs_opts"       ] && fs_opts=no_opts
		[ -z "$fs_label"      ] && fs_label=no_label
		[ -z "$fs_params"     ] && fs_params=no_params
		NEW_FILESYSTEM="$fs_type;yes;$fs_mountpoint;target;$fs_opts;$fs_label;$fs_params" #TODO: make re-creation yes/no asking available in this UI.

		# add new theoretical blockdevice, if relevant
		new_device=
		[ "$fs_type" = lvm-vg   ] && new_device="/dev/mapper/$fs_label $fs_type $fs_label"
		[ "$fs_type" = lvm-pv   ] && new_device="$part+ $fs_type no_label"
		[ "$fs_type" = lvm-lv   ] && new_device="/dev/mapper/$part_label-$fs_label $fs_type $fs_label"
		[ "$fs_type" = dm_crypt ] && new_device="/dev/mapper/$fs_label $fs_type no_label"
		[ -n "$new_device" ] && ! grep -q "^$new_device " $TMP_BLOCKDEVICES && echo "$new_device no_fs" >> $TMP_BLOCKDEVICES
	fi

	[ -z "$old_fs_label" ] && old_fs_label=no_label

	# Cascading remove theoretical blockdevice(s), if relevant ( eg if we just changed from vg->ext3, dm_crypt -> fat, or if we changed the label of a FS, causing a name change in a dm_mapper device)
	if [[ $old_fs_type = lvm-* || $old_fs_type = dm_crypt ]] && [ "$NEW_FILESYSTEM" = no_fs -o "$old_fs_type" != "$fs_type" -o "$old_fs_label" != "$fs_label" ]
	then
		[ "$old_fs_type" = lvm-vg   ] && remove_blockdevice "/dev/mapper/$old_fs_label"             "$old_fs_type" "$old_fs_label"
		[ "$old_fs_type" = lvm-pv   ] && remove_blockdevice "$part+"                                "$old_fs_type" "$old_fs_label"
		[ "$old_fs_type" = lvm-lv   ] && remove_blockdevice "/dev/mapper/$part_label-$old_fs_label" "$old_fs_type" "$old_fs_label"
		[ "$old_fs_type" = dm_crypt ] && remove_blockdevice "/dev/mapper/$old_fs_label"             "$old_fs_type" "$old_fs_label"
	fi

	return 0
}


remove_blockdevice ()
{
	local part=$1       # must be given but doesn't need to exist
	local part_type=$2  # a part should always have a type
	local part_label=$3 # must be given

	target="$part $part_type $part_label"
	declare target_escaped=${target//\//\\/} # note: apparently no need to escape the '+' sign for sed.
	declare target_escawk=${target_escaped/+/\\+} # ...but that doesn't count for awk
	fs_string=`awk "/^$target_escawk / { print \$4}" $TMP_BLOCKDEVICES` #TODO: fs_string is the entire line, incl part?
	debug 'UI-INTERACTIVE' "Cleaning up partition $part (type $part_type, label $part_label).  It has the following FS's on it: $fs_string"
	sed -i "/$target_escaped/d" $TMP_BLOCKDEVICES || show_warning "blockdevice removal" "Could not remove partition $part (type $part_type, label $part_label).  This is a bug. please report it"
	for fs in `sed 's/|/ /g' <<< $fs_string`
	do
		fs_type=`       cut -d ';' -f 1 <<< $fs`
		fs_label=`      cut -d ';' -f 6 <<< $fs`
		[ "$fs_type" = lvm-vg   ] && remove_blockdevice "/dev/mapper/$fs_label"             "$fs_type" "$fs_label"
		[ "$fs_type" = lvm-pv   ] && remove_blockdevice "$part+"                            "$fs_type" "$fs_label"
		[ "$fs_type" = lvm-lv   ] && remove_blockdevice "/dev/mapper/$part_label-$fs_label" "$fs_type" "$fs_label"
		[ "$fs_type" = dm_crypt ] && remove_blockdevice "/dev/mapper/$fs_label"             "$fs_type" "$fs_label"
	done
}


interactive_filesystems() {

	#notify "Available Disks:\n\n$(_getavaildisks)\n" quite useless here I think

	findpartitions 0 'no_fs' ' raw no_label' > $TMP_BLOCKDEVICES

	ALLOK=0
	while [ "$ALLOK" = 0 ]
	do
		# Let the user make filesystems and mountpoints. USERHAPPY becomes 1 when the user hits DONE.
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
				[ "$label" != no_label ] && label_display="($label)"
				[ "$label"  = no_label ] && label_display=
				if [ -b "${part/+/}" ] && get_blockdevice_size ${part/+/} MiB # test -b <-- exit's 0, test -b '' exits >0.
				then
					infostring="${type},${BLOCKDEVICE_SIZE}MiB${label_display}->$fs_display" # add size in MiB for existing blockdevices (eg not for mapper devices that are not yet created yet)
				else
					infostring="${type}${label_display}->$fs_display"
				fi
				menu_list="$menu_list $part $infostring" #don't add extra spaces, dialog doesn't like that.
			done < $TMP_BLOCKDEVICES

			ask_option no "Manage filesystems" "Here you can manage your filesystems, block devices and virtual devices (device mapper). Note that you don't *need* to specify opts, labels or extra params if you're not using lvm, dm_crypt, etc." required $menu_list DONE _
			[ $? -gt 0                 ] && USERHAPPY=1 && break
			[ "$ANSWER_OPTION" == DONE ] && USERHAPPY=1 && break

			part=$ANSWER_OPTION

			declare part_escaped=${part//\//\\/} # escape all slashes otherwise awk complains
			declare part_escaped=${part_escaped/+/\\+} # escape the + sign too
			part_type=$( awk "/^$part_escaped / {print \$2}" $TMP_BLOCKDEVICES)
			part_label=$(awk "/^$part_escaped / {print \$3}" $TMP_BLOCKDEVICES)
			fs=$(        awk "/^$part_escaped / {print \$4}" $TMP_BLOCKDEVICES)
			[ "$part_label" == no_label ] && part_label=
			[ "$fs"         == no_fs    ] && fs=

			if [ $part_type = lvm-vg ] # one lvm VG can host multiple LV's so that's a bit a special blockdevice...
			then
				list=
				if [ -n "$fs" ]
				then
					for lv in `sed 's/|/ /g' <<< $fs`
					do
						label=$(cut -d ';' -f 6 <<< $lv)
						size=$( cut -d ';' -f 7 <<< $lv)
						list="$list $label $size"
					done
				fi
				list="$list empty NEW"
				ask_option empty "Manage LV's on this VG" "Edit/create new LV's on this VG:" required $list && {
					EDIT_VG=$ANSWER_OPTION
					if [ "$ANSWER_OPTION" = empty  ]
					then
						# a new LV must be created on this VG
						if interactive_filesystem $part $part_type $part_label '' 
						then
							if [ "$NEW_FILESYSTEM" != no_fs ]
							then
								[ -n "$fs" ] && fs="$fs|$NEW_FILESYSTEM"
								[ -z "$fs" ] && fs=$NEW_FILESYSTEM
							fi
						fi
					else
						# an existing LV will be edited and it's settings updated
						for lv in `sed 's/|/ /g' <<< $fs`
						do
							label=$(cut -d ';' -f 6 <<< $lv)
							[ "$label" = "$EDIT_VG" ] && found_lv="$lv"
						done
						interactive_filesystem $part $part_type $part_label "$found_lv"
						newfs=
						for lv in `sed 's/|/ /g' <<< $fs`
						do
							label=$(cut -d ';' -f 6 <<< $lv)
							if [ "$label" != "$EDIT_VG" ]
							then
								add=$lv
							elif [ $NEW_FILESYSTEM != no_fs ]
							then
								add=$NEW_FILESYSTEM
							else
								add=
							fi
							[ -n "$add" -a -n "$newfs" ] && newfs="$newfs|$add"
							[ -n "$add" -a -z "$newfs" ] && newfs=$add
						done
						fs=$newfs
					fi
				}
			else
				interactive_filesystem $part $part_type "$part_label" "$fs"
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
			[ -n "$errors" ] && str="$str\nIt is highly recommended you go back to fix at least the errors."
			str="$str\nIf you hit cancel, we will abort here and go back to the menu"
			if ask_option back "Issues detected. what do you want to do?" "$str" required back "go back to fix the issues" ignore "continue, ignoring the issues"
			then
				[ "$ANSWER_OPTION" == ignore ] && ALLOK=1
			else
				return 1
			fi
		else
			ALLOK=1
		fi

	done


	process_filesystems && notify "Partitions were successfully created." && return 0
	ask_yesno "Seems like some stuff went wrong while processing the filesystems.  do you want to rollback? (this cleans up the new mountpoints, filesystems, etc. not doing this can break the next run of the installer unless you clean it up yourself" yes && rollback_filesystems
	return 1
}


# select_packages()
# prompts the user to select packages to install
#
# params: none
# returns: 1 on error
interactive_select_packages() {

	# set up our install location if necessary and sync up so we can get package lists
	target_prepare_pacman || ( show_warning 'Pacman preparation failure' "Pacman preparation failed! Check $LOG for errors." && return 1 )

	repos=`list_pacman_repos target`
	notify "Package selection is split into two stages.  First you will select package groups that contain packages you may be interested in.  Then you will be presented with a full list of packages for each group, allowing you to fine-tune.\n\n
Note that right now the packages (and groups) selection is limited to the repos available at this time ($repos).  One you have your Arch system up and running, you have access to more repositories and packages."

    # show group listing for group selection, base is ON by default, all others are OFF
    local _grouplist="base ^ ON"
    for i in $(list_package_groups | sed "s/^base$/ /g"); do
        _grouplist="${_grouplist} ${i} - OFF"
    done

    ask_checklist "Select Package groups\nDO NOT deselect BASE unless you know what you're doing!" $_grouplist || return 1
    _grouplist=$ANSWER_CHECKLIST # _grouplist now contains all groups (the tags from the dialog checklist)

    # assemble a list of packages with groups, marking pre-selected ones
    # <package> <group> <selected>
    local _pkgtmp="$(list_packages repo core | awk '{print $2}')" # all packages in core repository
    local _pkglist=''

    which_group "$_pkgtmp"
    while read pkgname pkggroup; do
        # check if this package is in a selected group
        # slightly ugly but sorting later requires newlines in the variable
        if [ "${_grouplist/"\"$pkggroup\""/XXXX}" != "${_grouplist}" ]; then
            _pkglist="$(echo -e "${_pkglist}\n${pkgname} ${pkggroup} ON")"
        else
            _pkglist="$(echo -e "${_pkglist}\n${pkgname} ${pkggroup} OFF")"
        fi
    done <<< "$PACKAGE_GROUPS"

    # sort by group
    _pkglist="$(echo "$_pkglist" | sort -f -k 2)"

    ask_checklist "Select Packages To Install." $_pkglist || return 1
	var_TARGET_PACKAGES=$ANSWER_CHECKLIST # contains now all package names
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

    ask_option no "Interface selection" "Select a network interface" required $ifaces || return 1 #TODO: code used originaly --nocancel here. what's the use? + make ok button 'select'
    INTERFACE=$ANSWER_OPTION


    if ask_yesno "Do you want to use DHCP?"
    then
        infofy "Please wait.  Polling for DHCP server on $INTERFACE..."
        dhcpcd -k $INTERFACE >$LOG 2>&1
        if ! dhcpcd $INTERFACE >$LOG 2>&1
        then
            show_warning "Dhcpcd problem" "Failed to run dhcpcd.  See $LOG for details."
            return 1
        fi
        if ! ifconfig $INTERFACE | grep -q 'inet addr:'
	then
            show_warning "Dhcpcd problem" "DHCP request failed. dhcpcd returned 0 but no ip configured for $INTERFACE"
            return 1
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
            ask_string "Enter your HTTP proxy server, for example:\nhttp://name:port\nhttp://ip:port\nhttp://username:password@ip:port\n\n Leave the field empty if no proxy is needed to install." "" 0 || return 1
            PROXY_HTTP=$ANSWER_STRING
            ask_string "Enter your FTP proxy server, for example:\nhttp://name:port\nhttp://ip:port\nhttp://username:password@ip:port\n\n Leave the field empty if no proxy is needed to install." "" 0 || return 1
            PROXY_FTP=$ANSWER_STRING
            ask_yesno "Are these settings correct?\n\nIP address:         $IPADDR\nNetmask:            $SUBNET\nBroadcast:          $BROADCAST\nGateway (optional): $GW\nDNS server:         $DNS\nHTTP proxy server:  $PROXY_HTTP\nFTP proxy server:   $PROXY_FTP"
            case $? in
                1) ;;
                0) NETPARAMETERS="1" ;;
            esac
        done
        echo "running: ifconfig $INTERFACE $IPADDR netmask $SUBNET broadcast $BROADCAST up" >$LOG
        if ! ifconfig $INTERFACE $IPADDR netmask $SUBNET broadcast $BROADCAST up >$LOG 2>&1
        then
        	show_warning "Ifconfig problem" "Failed to setup interface $INTERFACE"
        	return 1
        fi
        if [ -n "$GW" ]; then
            route add default gw $GW >$LOG 2>&1 || notify "Failed to setup your gateway." || return 1
        fi
        if [ -z "$PROXY_HTTP" ]; then
            unset http_proxy
        else
            export http_proxy=$PROXY_HTTP
        fi
        if [ -z "$PROXY_FTP" ]; then
            unset ftp_proxy
        else
            export ftp_proxy=$PROXY_FTP
        fi
        echo "nameserver $DNS" >/etc/resolv.conf
    fi
    notify "The network is configured."
    return 0
}

interactive_install_bootloader () {
	ask_option Grub "Choose bootloader" "Which bootloader would you like to use?  Grub is the Arch default." required \
	                "Grub" "Use the GRUB bootloader (default)" \
	                "None" "\Zb\Z1Warning\Z0\ZB: you must install your own bootloader!"

	bl=`tr '[:upper:]' '[:lower:]' <<< "$ANSWER_OPTION"`
	[ "$bl" != grub ] && return 0
	interactive_install_grub
}

interactive_install_grub() {
	get_grub_map
	local grubmenu="$var_TARGET_DIR/boot/grub/menu.lst"
	[ ! -f $grubmenu ] && show_warning "No grub?" "Error: Couldn't find $grubmenu.  Is GRUB installed?" && return 1

    # try to auto-configure GRUB...
    debug 'UI-INTERACTIVE' "install_grub \$PART_ROOT $PART_ROOT \$GRUB_OK $GRUB_OK"
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
            [ -n "$bootdev" ] && grubdev=$(mapdev $bootdev) || subdir="/boot"

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

	#TODO: handle dmraid/mdadm,lvm,dm_crypt etc. replace entries where needed
	# / on dm_crypt        -> no substitution needed: specify physical device that hosts the encrypted /
	# / on lvm             -> root=/dev/mapper/<volume-group>-<logical-volume-root> resume=/dev/mapper/<volume-group>-<logical-volume-swap> 
	# / on lvm on dm_crypt -> root=/dev/mapper/<volume-group>-<logical-volume-root> cryptdevice=/dev/<luks-part>:<volume-group>
	# / on dm_crypt on lvm -> specify the lvm device that hosts the encrypted /
	# ...

    notify "Before installing GRUB, you must review the configuration file.  You will now be put into the editor.  After you save your changes and exit the editor, you can install GRUB."
    [ -n "$EDITOR" ] || interactive_get_editor
    $EDITOR $grubmenu

    DEVS=$(finddisks 1 _)
    DEVS="$DEVS $(findpartitions 1 _)"
    if [ "$DEVS" = "" ]; then
        notify "No hard drives were found"
        return 1
    fi
    ask_option no "Boot device selection" "Select the boot device where the GRUB bootloader will be installed (usually the MBR and not a partition)." required $DEVS || return 1
    ROOTDEV=$ANSWER_OPTION
    infofy "Installing the GRUB bootloader..."
    cp -a $var_TARGET_DIR/usr/lib/grub/i386-pc/* $var_TARGET_DIR/boot/grub/
    sync
    # freeze xfs filesystems to enable grub installation on xfs filesystems
    for xfsdev in $(blkid -t TYPE=xfs -o device); do
	mnt=$(mount | grep $xfsdev | cut -d' ' -f 3)
        if [ $mnt = "$var_TARGET_DIR/boot" -o $mnt = "$var_TARGET_DIR/" ]; then
            /usr/sbin/xfs_freeze -f $mnt > /dev/null 2>&1
        fi
    done
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
        ask_option no "Boot partition device selection" "Please select the boot partition device, this cannot be autodetected!\nPlease redo grub installation for all partitions you need it!" required $DEVS || return 1
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
    for xfsdev in $(blkid -t TYPE=xfs -o device); do
        mnt=$(mount | grep $xfsdev | cut -d' ' -f 3)
        if [ $mnt = "$var_TARGET_DIR/boot" -o $mnt = "$var_TARGET_DIR/" ]; then
            /usr/sbin/xfs_freeze -u $mnt > /dev/null 2>&1
        fi
    done

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

	ask_option no "Source selection" "Please select an installation source" required \
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
        ask_option no "Mirror selection" "Select an FTP/HTTP mirror" required $MIRRORS "Custom" "_" || return 1
    local _server=$ANSWER_OPTION
    if [ "${_server}" = "Custom" ]; then
        ask_string "Enter the full URL to core repo." "ftp://ftp.archlinux.org/core/os/$var_ARCH" || return 1
        var_SYNC_URL=${ANSWER_STRING/\/core\///\$repo/} #replace '/core/' by '/$repo/'
    else
        # Form the full URL for our mirror by grepping for the server name in
        # our mirrorlist and pulling the full URL out.
        # Ensure that if it was listed twice we only return one line for the mirror.
        var_SYNC_URL=$(egrep -o "${_server}.*" "${var_MIRRORLIST}" | head -n1)
    fi
    echo "Using mirror: $var_SYNC_URL" >$LOG
}

# geteditor().
# prompts the user to choose an editor
# sets EDITOR global variable
#
interactive_get_editor() {
	unset EDITOR_OPTS
	which nano &>/dev/null && EDITOR_OPTS+=("nano" "nano (easier)")
	which joe  &>/dev/null && EDITOR_OPTS+=("joe"  "joe's editor")
	which vi   &>/dev/null && EDITOR_OPTS+=("vi"   "vi (advanced)")
	ask_option no "Text editor selection" "Select a Text Editor to Use" required "${EDITOR_OPTS[@]}"
	#TODO: this code could be a little bit cleaner.
	case $ANSWER_OPTION in
		"nano") EDITOR="nano" ;;
		"joe")  EDITOR="joe"  ;;
		"vi")   EDITOR="vi"   ;;
		*)      EDITOR="nano" ;;
	esac
}


select_source_extras_menu ()
{
	while true; do
		ask_option no "FTP Installation" "Make sure the network is ok and you've selected a mirror before continuing the installer" required \
		"1" "$worker_runtime_network_title" \
		"2" "$worker_select_mirror_title" \
		"3" "Return to Main Menu" || return 1
		[ "$ANSWER_OPTION" = 1 ] && execute worker runtime_network
		[ "$ANSWER_OPTION" = 2 ] && execute worker select_mirror
		[ "$ANSWER_OPTION" = 3 ] && break
	done
}
