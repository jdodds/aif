#!/bin/sh

finddisks() {
	workdir="$PWD"
	cd /sys/block
	# ide devices
	for dev in $(ls | egrep '^hd'); do
		if [ "$(cat $dev/device/media)" = "disk" ]; then
			if [ "$(dmesg | grep sectors | grep $dev)" ]; then
				echo "/dev/$dev"
				[ "$1" ] && echo $1
			fi
		fi
	done
	#scsi/sata devices
	for dev in $(ls | egrep '^sd'); do
		if ! [ "$(cat $dev/device/type)" = "5" ]; then
			if [ "$(dmesg | grep sectors | grep $dev)" ]; then
				echo "/dev/$dev"
				[ "$1" ] && echo $1
			fi
		fi
	done
	# cciss controllers
	if [ -d /dev/cciss ] ; then
		cd /dev/cciss
		for dev in $(ls | egrep -v 'p'); do
			echo "/dev/cciss/$dev"
			[ "$1" ] && echo $1
		done
	fi
	# Smart 2 controllers
        if [ -d /dev/ida ] ; then
                cd /dev/ida
                for dev in $(ls | egrep -v 'p'); do
                        echo "/dev/ida/$dev"
                        [ "$1" ] && echo $1
                done
        fi
	cd "$workdir"
}

# getuuid()
# converts /dev/[hs]d?[0-9] devices to UUIDs
#
# parameters: device file
# outputs:    UUID on success
#             nothing on failure
# returns:    nothing
getuuid()
{
    if [ "${1%%/[hs]d?[0-9]}" != "${1}" ]; then
        echo "$(blkid -s UUID -o value ${1})"
    fi
}


findcdroms() {
	workdir="$PWD"
	cd /sys/block
	# ide devices
	for dev in $(ls | egrep '^hd'); do
		if [ "$(cat $dev/device/media)" = "cdrom" ]; then
			echo "/dev/$dev"
			[ "$1" ] && echo $1
		fi
	done
	# scsi/sata and other devices
	for dev in $(ls | egrep '^sd|^sr|^scd|^sg'); do
		if [ "$(cat $dev/device/type)" = "5" ]; then
			echo "/dev/$dev"
			[ "$1" ] && echo $1
		fi
	done
	cd "$workdir"
}

findpartitions() {
	workdir="$PWD"
	for devpath in $(finddisks); do
		disk=$(echo $devpath | sed 's|.*/||')
		cd /sys/block/$disk
		for part in $disk*; do
			# check if not already assembled to a raid device
			if ! [ "$(cat /proc/mdstat 2>/dev/null | grep $part)" -o "$(fstype 2>/dev/null </dev/$part | grep "lvm2")" -o "$(sfdisk -c /dev/$disk $(echo $part | sed -e "s#$disk##g") 2>/dev/null | grep "5")" ]; then
				if [ -d $part ]; then
					echo "/dev/$part"
					[ "$1" ] && echo $1
				fi
			fi
		done
	done
	# include any mapped devices
	for devpath in $(ls /dev/mapper 2>/dev/null | grep -v control); do
		echo "/dev/mapper/$devpath"
		[ "$1" ] && echo $1
	done
	# include any raid md devices
	for devpath in $(ls -d /dev/md* | grep '[0-9]' 2>/dev/null); do
		if cat /proc/mdstat | grep -qw $(echo $devpath | sed -e 's|/dev/||g'); then
		echo "$devpath"
		[ "$1" ] && echo $1
		fi
	done
	# inlcude cciss controllers
	if [ -d /dev/cciss ] ; then
		cd /dev/cciss
		for dev in $(ls | egrep 'p'); do
			echo "/dev/cciss/$dev"
			[ "$1" ] && echo $1
		done
	fi
	# inlcude Smart 2 controllers
	if [ -d /dev/ida ] ; then
		cd /dev/ida
		for dev in $(ls | egrep 'p'); do
			echo "/dev/ida/$dev"
			[ "$1" ] && echo $1
		done
	fi
	cd "$workdir"
}

get_grub_map() {
	rm /tmp/dev.map
	DIALOG --infobox "Generating GRUB device map...\nThis could take a while.\n\n Please be patient." 0 0
	$DESTDIR/sbin/grub --no-floppy --device-map /tmp/dev.map >/tmp/grub.log 2>&1 <<EOF
quit
EOF
}

mapdev() {
	partition_flag=0
	device_found=0
	devs=$(cat /tmp/dev.map | grep -v fd | sed 's/ *\t/ /' | sed ':a;$!N;$!ba;s/\n/ /g')
	linuxdevice=$(echo $1 | cut -b1-8)
	if [ "$(echo $1 | egrep '[0-9]$')" ]; then
		# /dev/hdXY
		pnum=$(echo $1 | cut -b9-)
		pnum=$(($pnum-1))
		partition_flag=1
	fi
	for  dev in $devs
	do
	    if [ "(" = $(echo $dev | cut -b1) ]; then
		grubdevice="$dev"
	    else
		if [ "$dev" = "$linuxdevice" ]; then
			device_found=1
			break   
		fi
	   fi
	done	
	if [ "$device_found" = "1" ]; then
		if [ "$partition_flag" = "0" ]; then
			echo "$grubdevice"
		else
			grubdevice_stringlen=${#grubdevice}
			grubdevice_stringlen=$(($grubdevice_stringlen - 1))
			grubdevice=$(echo $grubdevice | cut -b1-$grubdevice_stringlen)
			echo "$grubdevice,$pnum)"
		fi
	else
		echo " DEVICE NOT FOUND"
	fi
}

_mkfs() {
	local _domk=$1
	local _device=$2
	local _fstype=$3
	local _dest=$4
	local _mountpoint=$5

	if [ "${_fstype}" = "swap" ]; then
		_mountpoint="swap"
		swapoff ${_device} >/dev/null 2>&1
		if [ "${_domk}" = "yes" ]; then
			mkswap ${_device} >$LOG 2>&1
			if [ $? != 0 ]; then
				DIALOG --msgbox "Error creating swap: mkswap ${_device}" 0 0
				return 1
			fi
		fi
		swapon ${_device} >$LOG 2>&1
		if [ $? != 0 ]; then
			DIALOG --msgbox "Error activating swap: swapon ${_device}" 0 0
			return 1
		fi
	elif [ "${_fstype}" = "xfs" ]; then
		if [ "${_domk}" = "yes" ]; then
			mkfs.xfs -f ${_device} >$LOG 2>&1
			if [ $? != 0 ]; then
				DIALOG --msgbox "Error creating filesystem: mkfs.xfs ${_device}" 0 0
				return 1
			fi
			sleep 2
		fi
		mkdir -p ${_dest}${_mountpoint}
		mount -t xfs ${_device} ${_dest}${_mountpoint} >$LOG 2>&1
		if [ $? != 0 ]; then
			DIALOG --msgbox "Error mounting ${_dest}${_mountpoint}" 0 0
			return 1
		fi
	elif [ "${_fstype}" = "jfs" ]; then
		if [ "${_domk}" = "yes" ]; then
			yes | mkfs.jfs ${_device} >$LOG 2>&1
			if [ $? != 0 ]; then
				DIALOG --msgbox "Error creating filesystem: mkfs.jfs ${_device}" 0 0
				return 1
			fi
			sleep 2
		fi
		mkdir -p ${_dest}${_mountpoint}
		mount -t jfs ${_device} ${_dest}${_mountpoint} >$LOG 2>&1
		if [ $? != 0 ]; then
			DIALOG --msgbox "Error mounting ${_dest}${_mountpoint}" 0 0
			return 1
		fi
	elif [ "${_fstype}" = "reiserfs" ]; then
		if [ "${_domk}" = "yes" ]; then
			yes | mkreiserfs ${_device} >$LOG 2>&1
			if [ $? != 0 ]; then
				DIALOG --msgbox "Error creating filesystem: mkreiserfs ${_device}" 0 0
				return 1
			fi
			sleep 2
		fi
		mkdir -p ${_dest}${_mountpoint}
		mount -t reiserfs ${_device} ${_dest}${_mountpoint} >$LOG 2>&1
		if [ $? != 0 ]; then
			DIALOG --msgbox "Error mounting ${_dest}${_mountpoint}" 0 0
			return 1
		fi
	elif [ "${_fstype}" = "ext2" ]; then
		if [ "${_domk}" = "yes" ]; then
			mke2fs "${_device}" >$LOG 2>&1
			if [ $? != 0 ]; then
				DIALOG --msgbox "Error creating filesystem: mke2fs ${_device}" 0 0
				return 1
			fi
			sleep 2
		fi
		mkdir -p ${_dest}${_mountpoint}
		mount -t ext2 ${_device} ${_dest}${_mountpoint} >$LOG 2>&1
		if [ $? != 0 ]; then
			DIALOG --msgbox "Error mounting ${_dest}${_mountpoint}" 0 0
			return 1
		fi
	elif [ "${_fstype}" = "ext3" ]; then
		if [ "${_domk}" = "yes" ]; then
			mke2fs -j ${_device} >$LOG 2>&1
			if [ $? != 0 ]; then
				DIALOG --msgbox "Error creating filesystem: mke2fs -j ${_device}" 0 0
				return 1
			fi
			sleep 2
		fi
		mkdir -p ${_dest}${_mountpoint}
		mount -t ext3 ${_device} ${_dest}${_mountpoint} >$LOG 2>&1
		if [ $? != 0 ]; then
			DIALOG --msgbox "Error mounting ${_dest}${_mountpoint}" 0 0
			return 1
		fi
	elif [ "${_fstype}" = "vfat" ]; then
		if [ "${_domk}" = "yes" ]; then
			mkfs.vfat ${_device} >$LOG 2>&1
			if [ $? != 0 ]; then
				DIALOG --msgbox "Error creating filesystem: mkfs.vfat ${_device}" 0 0
				return 1
			fi
			sleep 2
		fi
		mkdir -p ${_dest}${_mountpoint}
		mount -t vfat ${_device} ${_dest}${_mountpoint} >$LOG 2>&1
		if [ $? != 0 ]; then
			DIALOG --msgbox "Error mounting ${_dest}${_mountpoint}" 0 0
			return 1
		fi
	else
		DIALOG --msgbox "unknown fstype for ${_device}" 0 0
		return 1
	fi

	# add to temp fstab
	if [ "$UUIDPARAMETER" = "yes" ]; then
		local _uuid="$(getuuid ${_device})"
		if [ -n "${_uuid}" ]; then
			_device="UUID=${_uuid}"
		fi
		echo -n "${_device} ${_mountpoint} ${_fstype} defaults 0 " >>/tmp/.fstab
	else
		echo -n "${_device} ${_mountpoint} ${_fstype} defaults 0 " >>/tmp/.fstab
	fi
	if [ "${_fstype}" = "swap" ]; then
		echo "0" >>/tmp/.fstab
	else
		echo "1" >>/tmp/.fstab
	fi
}

mksimplefs() {
	DEVICE=$1
	FSSPECS=$2
	sfdisk_input=""

	# we assume a /dev/hdX format (or /dev/sdX)
	dev=$DEVICE
	PART_SWAP="${dev}2"
	PART_ROOT="${dev}3"

	if [ "$S_MKFS" = "1" ]; then
		DIALOG --msgbox "You have already prepared your filesystems manually" 0 0
		return 0
	fi

	# validate DEVICE
	if [ ! -b "$DEVICE" ]; then
	  DIALOG --msgbox "Device '$DEVICE' is not valid" 0 0
	  return 1
	fi

	# validate DEST
	if [ ! -d "$DESTDIR" ]; then
		DIALOG --msgbox "Destination directory '$DESTDIR' is not valid" 0 0
		return 1
	fi

	# /boot required
	if [ $(echo $FSSPECS | grep '/boot:' | wc -l) -ne 1 ]; then
		DIALOG --msgbox "Need exactly one boot partition" 0 0
		return 1
	fi

	# swap required
	if [ $(echo $FSSPECS | grep 'swap:' | wc -l) -lt 1 ]; then
		DIALOG --msgbox "Need at least one swap partition" 0 0
		return 1
	fi

	# / required
	if [ $(echo $FSSPECS | grep '/:' | wc -l) -ne 1 ]; then
		DIALOG --msgbox "Need exactly one root partition" 0 0
		return 1
	fi

	if [ $(echo $FSSPECS | grep '/home:' | wc -l) -ne 1 ]; then
		DIALOG --msgbox "Need exactly one home partition" 0 0
		return 1
	fi

	rm -f /tmp/.fstab

	# disable swap and all mounted partitions, umount / last!
	DIALOG --infobox "Disabling swapspace, unmounting already mounted disk devices..." 0 0
	swapoff -a >/dev/null 2>&1
	umount $(mount | grep -v "${DESTDIR} " | grep "${DESTDIR}" | sed 's|\ .*||g') >/dev/null 2>&1
	umount $(mount | grep "${DESTDIR} " | sed 's|\ .*||g') >/dev/null 2>&1

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
	DIALOG --infobox "Partitioning $DEVICE" 0 0
	sfdisk $DEVICE -uM >$LOG 2>&1 <<EOF
$sfdisk_input
EOF
	if [ $? -gt 0 ]; then
		DIALOG --msgbox "Error partitioning $DEVICE (see $LOG for details)" 0 0
		prink on
		return 1
	fi
	printk on

	# need to mount root first, then do it again for the others
	part=1
	for fsspec in $FSSPECS; do
		mountpoint=$(echo $fsspec | tr -d ' ' | cut -f1 -d:)
		fstype=$(echo $fsspec | tr -d ' ' | cut -f3 -d:)
		if echo $mountpoint | tr -d ' ' | grep '^/$' 2>&1 > /dev/null; then
				_mkfs yes ${DEVICE}${part} "$fstype" "$DESTDIR" "$mountpoint" || return 1
		fi
		part=$(($part + 1))
	done

	# make other filesystems
	part=1
	for fsspec in $FSSPECS; do
		mountpoint=$(echo $fsspec | tr -d ' ' | cut -f1 -d:)
		fstype=$(echo $fsspec | tr -d ' ' | cut -f3 -d:)
		if [ $(echo $mountpoint | tr -d ' ' | grep '^/$' | wc -l) -eq 0 ]; then
			_mkfs yes ${DEVICE}${part} "$fstype" "$DESTDIR" "$mountpoint" || return 1
		fi
		part=$(($part + 1))
	done

	DIALOG --msgbox "Auto-prepare was successful" 0 0
	S_MKFSAUTO=1
}

partition() {
	if [ "$S_MKFSAUTO" = "1" ]; then
		DIALOG --msgbox "You have already prepared your filesystems with Auto-prepare" 0 0
		return 0
	fi
	# disable swap and all mounted partitions, umount / last!
	DIALOG --infobox "Disabling swapspace, unmounting already mounted disk devices..." 0 0
	swapoff -a >/dev/null 2>&1
	umount $(mount | grep -v "${DESTDIR} " | grep "${DESTDIR}" | sed 's|\ .*||g') >/dev/null 2>&1
	umount $(mount | grep "${DESTDIR} " | sed 's|\ .*||g') >/dev/null 2>&1
	#
	# Select disk to partition
	#
	DISCS=$(finddisks _)
	DISCS="$DISCS OTHER -"
	DIALOG --msgbox "Available Disks:\n\n$(for i in $(finddisks); do echo -n $(echo $i | sed 's#/dev/##g'): '' ; dmesg | grep $(echo $i | sed 's#/dev/##g') | grep sectors | sort -u | cut -d'(' -f2 | cut -d')' -f1; echo "\n"; done)\n"
	DIALOG --menu "Select the disk you want to partition" 14 55 7 $DISCS 2>$ANSWER || return 1
	DISC=$(cat $ANSWER)
	if [ "$DISC" = "OTHER" ]; then
		DIALOG --inputbox "Enter the full path to the device you wish to partition" 8 65 "/dev/sda" 2>$ANSWER || return 1
		DISC=$(cat $ANSWER)
	fi
	while [ "$DISC" != "DONE" ]; do
		#
		# Partition disc
		#
		DIALOG --msgbox "Now you'll be put into the cfdisk program where you can partition your hard drive. You should make a swap partition and as many data partitions as you will need.  NOTE: cfdisk may tell you to reboot after creating partitions.  If you need to reboot, just re-enter this install program, skip this step and go on to step 2." 18 70
		cfdisk $DISC

		DIALOG --menu "Select the disk you want to partition" 14 55 7 $DISCS DONE + 2>$ANSWER || return 1
		DISC=$(cat $ANSWER)
		if [ "$DISC" = "OTHER" ]; then
			DIALOG --inputbox "Enter the full path to the device you wish to partition" 8 65 "/dev/sda" 2>$ANSWER || return 1
			DISC=$(cat $ANSWER)
		fi
	done
	S_PART=1
}

mountpoints() {
	if [ "$S_MKFSAUTO" = "1" ]; then
		DIALOG --msgbox "You have already prepared your filesystems with Auto-prepare" 0 0
		return 0
	fi
	while [ "$PARTFINISH" != "DONE" ]; do
	: >/tmp/.fstab
	: >/tmp/.parts

	# Determine which filesystems are available
	insmod /lib/modules/$(uname -r)/kernel/fs/xfs/xfs.ko >/dev/null 2>&1
	insmod /lib/modules/$(uname -r)/kernel/fs/jfs/jfs.ko >/dev/null 2>&1
	FSOPTS="ext2 Ext2 ext3 Ext3"
	[ "$(which mkreiserfs 2>/dev/null)" ] && FSOPTS="$FSOPTS reiserfs Reiser3"
	[ "$(which mkfs.xfs 2>/dev/null)" ]   && FSOPTS="$FSOPTS xfs XFS"
	[ "$(which mkfs.jfs 2>/dev/null)" ]   && FSOPTS="$FSOPTS jfs JFS"
	[ "$(which mkfs.vfat 2>/dev/null)" ]   && FSOPTS="$FSOPTS vfat VFAT"

	#
	# Select mountpoints
	#
	DIALOG --msgbox "Available Disks:\n\n$(for i in $(finddisks); do echo -n $(echo $i | sed 's#/dev/##g'): '' ; dmesg | grep $(echo $i | sed 's#/dev/##g') | grep sectors | sort -u | cut -d'(' -f2 | cut -d')' -f1; echo "\n"; done)\n" 0 0
	PARTS=$(findpartitions _)
	DIALOG --menu "Select the partition to use as swap" 21 50 13 NONE - $PARTS 2>$ANSWER || return 1
	PART=$(cat $ANSWER)
	PARTS="$(echo $PARTS | sed -e "s#${PART}\ _##g")"
	PART_SWAP=$PART
	if [ "$PART_SWAP" != "NONE" ]; then
		DOMKFS="no"
		DIALOG --yesno "Would you like to create a filesystem on $PART?\n\n(This will overwrite existing data!)" 0 0 && DOMKFS="yes"
		echo "$PART:swap:swap:$DOMKFS" >>/tmp/.parts
	fi
	
	DIALOG --menu "Select the partition to mount as /" 21 50 13 $PARTS 2>$ANSWER || return 1
	PART=$(cat $ANSWER)
	PARTS="$(echo $PARTS | sed -e "s#${PART}\ _##g")"
	PART_ROOT=$PART
	# Select root filesystem type
	DIALOG --menu "Select a filesystem for $PART" 13 45 6 $FSOPTS 2>$ANSWER || return 1
	FSTYPE=$(cat $ANSWER)
	DOMKFS="no"
	DIALOG --yesno "Would you like to create a filesystem on $PART?\n\n(This will overwrite existing data!)" 0 0 && DOMKFS="yes"
	echo "$PART:$FSTYPE:/:$DOMKFS" >>/tmp/.parts

	#
	# Additional partitions
	#
	DIALOG --menu "Select any additional partitions to mount under your new root (select DONE when finished)" 21 50 13 $PARTS DONE _ 2>$ANSWER || return 1
	PART=$(cat $ANSWER)
	while [ "$PART" != "DONE" ]; do
		PARTS="$(echo $PARTS | sed -e "s#${PART}\ _##g")"
		# Select a filesystem type
		DIALOG --menu "Select a filesystem for $PART" 13 45 6 $FSOPTS 2>$ANSWER || return 1
		FSTYPE=$(cat $ANSWER)
		MP=""
		while [ "${MP}" = "" ]; do
			DIALOG --inputbox "Enter the mountpoint for $PART" 8 65 "/boot" 2>$ANSWER || return 1
			MP=$(cat $ANSWER)
			if grep ":$MP:" /tmp/.parts; then
				DIALOG --msgbox "ERROR: You have defined 2 identical mountpoints! Please select another mountpoint." 8 65
				MP=""
			fi
		done
		DOMKFS="no"
		DIALOG --yesno "Would you like to create a filesystem on $PART?\n\n(This will overwrite existing data!)" 0 0 && DOMKFS="yes"
		echo "$PART:$FSTYPE:$MP:$DOMKFS" >>/tmp/.parts
		DIALOG --menu "Select any additional partitions to mount under your new root" 21 50 13 $PARTS DONE _ 2>$ANSWER || return 1
		PART=$(cat $ANSWER)
	done
	DIALOG --yesno "Would you like to create and mount the filesytems like this?\n\nSyntax\n------\nDEVICE:TYPE:MOUNTPOINT:FORMAT\n\n$(for i in $(cat /tmp/.parts); do echo "$i\n";done)" 0 0 && PARTFINISH="DONE"
	done
	# disable swap and all mounted partitions
	DIALOG --infobox "Disabling swapspace, unmounting already mounted disk devices..." 0 0
	swapoff -a >/dev/null 2>&1
	umount $(mount | grep -v "${DESTDIR} " | grep "${DESTDIR}" | sed 's|\ .*||g') >/dev/null 2>&1
	umount $(mount | grep "${DESTDIR} " | sed 's|\ .*||g') >/dev/null 2>&1
	for line in $(cat /tmp/.parts); do
		PART=$(echo $line | cut -d: -f 1)
		FSTYPE=$(echo $line | cut -d: -f 2)
		MP=$(echo $line | cut -d: -f 3)
		DOMKFS=$(echo $line | cut -d: -f 4)
		umount ${DESTDIR}${MP}
		if [ "$DOMKFS" = "yes" ]; then
			if [ "$FSTYPE" = "swap" ]; then
				DIALOG --infobox "Creating swapspace on $PART, activating..." 0 0
			else
				DIALOG --infobox "Creating $FSTYPE on $PART, mounting to ${DESTDIR}${MP}" 0 0
			fi
			_mkfs yes $PART $FSTYPE $DESTDIR $MP || return 1
		else
			if [ "$FSTYPE" = "swap" ]; then
				DIALOG --infobox "Activating swapspace on $PART" 0 0
			else
				DIALOG --infobox "Mounting $PART to ${DESTDIR}${MP}"
			fi
			_mkfs no $PART $FSTYPE $DESTDIR $MP || return 1
		fi
		sleep 1
	done

	DIALOG --msgbox "Partitions were successfully mounted." 0 0
	S_MKFS=1
}

select_cdrom () {
	# we may have leftover mounts...
	umount /src >/dev/null 2>&1
	CDROMS=$(findcdroms _)
	if [ "$CDROMS" = "" ]; then
		DIALOG --msgbox "No CD drives were found" 0 0
		return 1
	fi
	DIALOG --msgbox "Available CD drives:\n\n$(for i in $(findcdroms); do k=$(echo $i: | sed 's#/dev/##g'); dmesg | grep $k | grep "CD/"| cut -d, -f1 | sed 's/ /|/g';l=$(echo "$k"$(dmesg | grep $(dmesg | grep $(echo $k | sed 's#:##g') |grep CD- |cut -d\  -f2) | grep ^scsi | sed -e 's/ /|/g' | sed -e 's#.*CD-ROM##g' | sed -e 's#|||##g' | sed -e 's#||#|#g')); ! [ "$l" = "$k" ] && echo $l; done)\n" 0 0
	DIALOG --menu "Select the CD drive that contains Arch packages" 14 55 7 $CDROMS 2>$ANSWER || return 1
	CDROM=$(cat $ANSWER)
	DIALOG --infobox "Mounting $CDROM" 0 0
	mount -t iso9660 $CDROM /src >/dev/null 2>&1
	if [ $? -gt 0 ]; then
		DIALOG --msgbox "Failed to mount $CDROM" 0 0
		return 1
	fi
}

dolilo() {
	if [ ! -f $DESTDIR/etc/lilo.conf ]; then
		DIALOG --msgbox "Error: Couldn't find $DESTDIR/etc/lilo.conf.  Is LILO installed?" 0 0
		return 1
	fi
	# Try to auto-configure LILO...
	if [ "$PART_ROOT" != "" -a "$S_LILO" != "1" ]; then
		sed -i "s|vmlinuz26|vmlinuz|g" $DESTDIR/etc/lilo.conf
		sed -i "s|vmlinuz|$VMLINUZ|g" $DESTDIR/etc/lilo.conf
		if [ "$UUIDPARAMETER" = "yes" ]; then
			local _rootpart="${PART_ROOT}"
			local _uuid="$(getuuid ${PART_ROOT})"
			if [ -n "${_uuid}" ]; then
				_rootpart="/dev/disk/by-uuid/${_uuid}"
			fi
			sed -i "s|root=.*$|append=\"root=${_rootpart}\"|g" $DESTDIR/etc/lilo.conf
		else
			sed -i "s|root=.*$|root=${PART_ROOT}|g" $DESTDIR/etc/lilo.conf
		fi
	fi
	DEVS=$(finddisks _)
	DEVS="$DEVS $(findpartitions _)"
	if [ "$DEVS" = "" ]; then
		DIALOG --msgbox "No hard drives were found" 0 0
		return 1
	fi
	DIALOG --menu "Select the boot device where the LILO bootloader will be installed (usually the MBR)" 14 55 7 $DEVS 2>$ANSWER || return 1
	ROOTDEV=$(cat $ANSWER)
	sed -i "s|boot=.*$|boot=$ROOTDEV|g" $DESTDIR/etc/lilo.conf
	DIALOG --msgbox "Before installing LILO, you must review the configuration file.  You will now be put into the editor.  After you save your changes and exit the editor, LILO will be installed." 0 0
	[ "$EDITOR" ] || geteditor
	$EDITOR ${DESTDIR}/etc/lilo.conf
	DIALOG --infobox "Installing the LILO bootloader..." 0 0
	mount -t proc none $DESTDIR/proc
	mount -o bind /dev $DESTDIR/dev
	chroot $DESTDIR /sbin/lilo >$LOG 2>&1
	if [ $? -gt 0 ]; then
		umount $DESTDIR/dev $DESTDIR/proc
		DIALOG --msgbox "Error installing LILO. (see $LOG for output)" 0 0
		return 1
	fi
	umount $DESTDIR/dev $DESTDIR/proc
	DIALOG --msgbox "LILO was successfully installed." 0 0
	S_LILO=1
}

dogrub() {
	get_grub_map	
	if [ ! -f $DESTDIR/boot/grub/menu.lst ]; then
		DIALOG --msgbox "Error: Couldn't find $DESTDIR/boot/grub/menu.lst.  Is GRUB installed?" 0 0
		return 1
	fi
	# try to auto-configure GRUB...
	if [ "$PART_ROOT" != "" -a "$S_GRUB" != "1" ]; then
		grubdev=$(mapdev $PART_ROOT)
		if [ "$UUIDPARAMETER" = "yes" ]; then
			local _rootpart="${PART_ROOT}"
			local _uuid="$(getuuid ${PART_ROOT})"
			if [ -n "${_uuid}" ]; then
				_rootpart="/dev/disk/by-uuid/${_uuid}"
			fi
		fi
		# look for a separately-mounted /boot partition
		bootdev=$(mount | grep $DESTDIR/boot | cut -d' ' -f 1)
		if [ "$grubdev" != "" -o "$bootdev" != "" ]; then
			cp $DESTDIR/boot/grub/menu.lst /tmp/.menu.lst
			# remove the default entries by truncating the file at our little tag (#-*)
			head -n $(cat /tmp/.menu.lst | grep -n '#-\*' | cut -d: -f 1) /tmp/.menu.lst >$DESTDIR/boot/grub/menu.lst
			rm -f /tmp/.menu.lst
			echo "" >>$DESTDIR/boot/grub/menu.lst
			echo "# (0) Arch Linux" >>$DESTDIR/boot/grub/menu.lst
			echo "title  Arch Linux" >>$DESTDIR/boot/grub/menu.lst
			subdir=
			if [ "$bootdev" != "" ]; then
				grubdev=$(mapdev $bootdev)
			else
				subdir="/boot"
			fi
			echo "root   $grubdev" >>$DESTDIR/boot/grub/menu.lst
			if [ "$UUIDPARAMETER" = "yes" ]; then
				echo "kernel $subdir/$VMLINUZ root=${_rootpart} ro" >>$DESTDIR/boot/grub/menu.lst
			else
				echo "kernel $subdir/$VMLINUZ root=$PART_ROOT ro" >>$DESTDIR/boot/grub/menu.lst
			fi
			if [ "$VMLINUZ" = "vmlinuz26" ]; then
				echo "initrd $subdir/kernel26.img" >>$DESTDIR/boot/grub/menu.lst
			fi
			echo "" >>$DESTDIR/boot/grub/menu.lst
			# adding fallback/full image
			echo "# (1) Arch Linux" >>$DESTDIR/boot/grub/menu.lst
			echo "title  Arch Linux Fallback" >>$DESTDIR/boot/grub/menu.lst
			echo "root   $grubdev" >>$DESTDIR/boot/grub/menu.lst
			if [ "$UUIDPARAMETER" = "yes" ]; then
				echo "kernel $subdir/$VMLINUZ root=${_rootpart} ro" >>$DESTDIR/boot/grub/menu.lst
			else
				echo "kernel $subdir/$VMLINUZ root=$PART_ROOT ro" >>$DESTDIR/boot/grub/menu.lst
			fi
			if [ "$VMLINUZ" = "vmlinuz26" ]; then
				echo "initrd $subdir/kernel26-fallback.img" >>$DESTDIR/boot/grub/menu.lst
			fi
			echo "" >>$DESTDIR/boot/grub/menu.lst
			echo "# (1) Windows" >>$DESTDIR/boot/grub/menu.lst
			echo "#title Windows" >>$DESTDIR/boot/grub/menu.lst
			echo "#rootnoverify (hd0,0)" >>$DESTDIR/boot/grub/menu.lst
			echo "#makeactive" >>$DESTDIR/boot/grub/menu.lst
			echo "#chainloader +1" >>$DESTDIR/boot/grub/menu.lst
		fi
	fi

	DIALOG --msgbox "Before installing GRUB, you must review the configuration file.  You will now be put into the editor.  After you save your changes and exit the editor, you can install GRUB." 0 0
	[ "$EDITOR" ] || geteditor
	$EDITOR ${DESTDIR}/boot/grub/menu.lst

	DEVS=$(finddisks _)
	DEVS="$DEVS $(findpartitions _)"
	if [ "$DEVS" = "" ]; then
		DIALOG --msgbox "No hard drives were found" 0 0
		return 1
	fi
	DIALOG --menu "Select the boot device where the GRUB bootloader will be installed (usually the MBR)" 14 55 7 $DEVS 2>$ANSWER || return 1
	ROOTDEV=$(cat $ANSWER)
	DIALOG --infobox "Installing the GRUB bootloader..." 0 0
	cp -a $DESTDIR/usr/lib/grub/i386-pc/* $DESTDIR/boot/grub/
	sync
	# freeze xfs filesystems to enable grub installation on xfs filesystems
	if [ -x /usr/sbin/xfs_freeze ]; then
		/usr/sbin/xfs_freeze -f $DESTDIR/boot > /dev/null 2>&1
		/usr/sbin/xfs_freeze -f $DESTDIR/ > /dev/null 2>&1
	fi
	# look for a separately-mounted /boot partition
	bootpart=$(mount | grep $DESTDIR/boot | cut -d' ' -f 1)
	if [ "$bootpart" = "" ]; then
		if [ "$PART_ROOT" = "" ]; then
			DIALOG --inputbox "Enter the full path to your root device" 8 65 "/dev/sda3" 2>$ANSWER || return 1
			bootpart=$(cat $ANSWER)
		else
			bootpart=$PART_ROOT
		fi
	fi
	DIALOG --defaultno --yesno "Do you have your system installed on software raid?\nAnswer 'YES' to install grub to another hard disk."  0 0
	if [ $? -eq 0 ]; then
		DIALOG --menu "Please select the boot partition device, this cannot be autodetected!\nPlease redo grub installation for all partitions you need it!" 14 55 7 $DEVS 2>$ANSWER || return 1
		bootpart=$(cat $ANSWER)
	fi	
	bootpart=$(mapdev $bootpart)
	bootdev=$(mapdev $ROOTDEV)
	if [ "$bootpart" = "" ]; then
		DIALOG --msgbox "Error: Missing/Invalid root device: $bootpart" 0 0
		return 1
	fi
	$DESTDIR/sbin/grub --no-floppy --batch >/tmp/grub.log 2>&1 <<EOF
root $bootpart
setup $bootdev
quit
EOF
	cat /tmp/grub.log >$LOG
	# unfreeze xfs filesystems
	if [ -x /usr/sbin/xfs_freeze ]; then
		/usr/sbin/xfs_freeze -u $DESTDIR/boot > /dev/null 2>&1
		/usr/sbin/xfs_freeze -u $DESTDIR/ > /dev/null 2>&1
	fi

	if grep "Error [0-9]*: " /tmp/grub.log >/dev/null; then
		DIALOG --msgbox "Error installing GRUB. (see $LOG for output)" 0 0
		return 1
	fi
	DIALOG --msgbox "GRUB was successfully installed." 0 0
	S_GRUB=1
}

prepare_harddrive()
{
	S_MKFSAUTO=0
	S_MKFS=0
	DONE=0
	UUIDPARAMETER=""
	NEXTITEM=""
	DIALOG --yesno "Do you want to use UUID device name scheme,\ninstead of kernel device name scheme?" 0 0 && UUIDPARAMETER=yes
	while [ "$DONE" = "0" ]; do
		if [ -n "$NEXTITEM" ]; then
			DEFAULT="--default-item $NEXTITEM"
		else
			DEFAULT=""
		fi
		dialog $DEFAULT --backtitle "$TITLE" --menu "Prepare Hard Drive" 12 60 5 \
			"1" "Auto-Prepare (erases the ENTIRE hard drive)" \
			"2" "Partition Hard Drives" \
			"3" "Set Filesystem Mountpoints" \
			"4" "Return to Main Menu" 2>$ANSWER
		NEXTITEM="$(cat $ANSWER)"
		case $(cat $ANSWER) in
			"1")
				DISCS=$(finddisks)
				if [ $(echo $DISCS | wc -w) -gt 1 ]; then
					DIALOG --msgbox "Available Disks:\n\n$(for i in $(finddisks); do dmesg | grep $(echo $i | sed 's#/dev/##g') | grep sectors | sort -u | cut -d')' -f1 |sed -e 's/ /|/g' -e 's/SCSI|device|//g' -e 's/(//g'; done)\n" 0 0
					DIALOG --menu "Select the hard drive to use" 14 55 7 $(finddisks _) 2>$ANSWER || return 1
					DISC=$(cat $ANSWER)
				else
					DISC=$DISCS
				fi
					SET_DEFAULTFS=""
					BOOT_PART_SET=""
					SWAP_PART_SET=""
					ROOT_PART_SET=""
					CHOSEN_FS=""
					DISC_SIZE=$(dmesg | grep $(echo $DISC | sed 's#/dev/##g') | grep sectors | sort -u | cut -d'(' -f2 | sed -e 's# .*##g')
					while [ "$SET_DEFAULTFS" = "" ]; do
						FSOPTS="ext2 Ext2 ext3 Ext3"
						[ "$(which mkreiserfs 2>/dev/null)" ] && FSOPTS="$FSOPTS reiserfs Reiser3"
						[ "$(which mkfs.xfs 2>/dev/null)" ]   && FSOPTS="$FSOPTS xfs XFS"
						[ "$(which mkfs.jfs 2>/dev/null)" ]   && FSOPTS="$FSOPTS jfs JFS"
						while [ "$BOOT_PART_SET" = "" ]; do
							DIALOG --inputbox "Enter the size (MegaByte/MB) of your /boot partition,\n(minimum value is 16).\n\nDisk space left: $DISC_SIZE (MegaByte/MB)" 8 65 "32" 2>$ANSWER || return 1
							BOOT_PART_SIZE="$(cat $ANSWER)"
							if [ "$BOOT_PART_SIZE" = ""  ]; then
								DIALOG --msgbox "ERROR: You have entered a wrong size, please enter again." 0 0
							else
								if [ "$BOOT_PART_SIZE" -ge "$DISC_SIZE" -o "$BOOT_PART_SIZE" -lt "16" -o "$SBOOT_PART_SIZE" = "$DISC_SIZE" ]; then
									DIALOG --msgbox "ERROR: You have entered a wrong size, please enter again." 0 0
								else
									BOOT_PART_SET=1
								fi
							fi
						done
						DISC_SIZE=$(($DISC_SIZE-$BOOT_PART_SIZE))
						while [ "$SWAP_PART_SET" = "" ]; do
							DIALOG --inputbox "Enter the size (MegaByte/MB) of your swap partition,\n(minimum value is > 0).\n\nDisk space left: $DISC_SIZE (MegaByte/MB)" 8 65 "256" 2>$ANSWER || return 1
							SWAP_PART_SIZE=$(cat $ANSWER)
							if [ "$SWAP_PART_SIZE" = "" -o  "$SWAP_PART_SIZE" = "0" ]; then
								DIALOG --msgbox "ERROR: You have entered a wrong size, please enter again." 0 0
							else
								if [ "$SWAP_PART_SIZE" -ge "$DISC_SIZE" ]; then
									DIALOG --msgbox "ERROR: You have entered a wrong size, please enter again." 0 0
								else
									SWAP_PART_SET=1
								fi
							fi
						done
						DISC_SIZE=$(($DISC_SIZE-$SWAP_PART_SIZE))
						while [ "$ROOT_PART_SET" = "" ]; do
							DIALOG --inputbox "Enter the size (MegaByte/MB) of your / partition,\nthe /home partition will take all the left space.\n\nDisk space left:  $DISC_SIZE (MegaByte/MB)" 8 65 "7500" 2>$ANSWER || return 1
							ROOT_PART_SIZE=$(cat $ANSWER)
							if [ "$ROOT_PART_SIZE" = "" -o "$ROOT_PART_SIZE" = "0" ]; then
								DIALOG --msgbox "ERROR: You have entered a wrong size, please enter again." 0 0
							else
								if [ "$ROOT_PART_SIZE" -ge "$DISC_SIZE" ]; then
									DIALOG --msgbox "ERROR: You have entered a wrong size, please enter again." 0 0
								else
									DIALOG --yesno "$(($DISC_SIZE-$ROOT_PART_SIZE)) (MegaByte/MB) will be used for your /home partition?" 0 0 && ROOT_PART_SET=1
								fi
							fi
						done
						while [ "$CHOSEN_FS" = "" ]; do
							DIALOG --menu "Select a filesystem for / and /home" 13 45 6 $FSOPTS 2>$ANSWER || return 1
									FSTYPE=$(cat $ANSWER)
							DIALOG --yesno "$FSTYPE will be used for / and /home?" 0 0 && CHOSEN_FS=1
						done
						SET_DEFAULTFS=1
					done
				REAL_DEFAULTFS=$(echo $DEFAULTFS | sed -e "s|/:7500:ext3|/:$ROOT_PART_SIZE:$FSTYPE|g" -e "s|/home:\*:ext3|/home:\*:$FSTYPE|g" -e "s|swap:256|swap:$SWAP_PART_SIZE|g" -e "s|/boot:32|/boot:$BOOT_PART_SIZE|g")
				DIALOG --defaultno --yesno "$DISC will be COMPLETELY ERASED!  Are you absolutely sure?" 0 0 \
					&& mksimplefs $DISC "$REAL_DEFAULTFS" ;;
			"2")
				partition ;;
			"3")
				PARTFINISH=""
				mountpoints ;;
			*)
				DONE=1 ;;
		esac
	done
	NEXTITEM="3"
}

install_bootloader()
{
	DIALOG --menu "Which bootloader would you like to use?  Grub is the Arch default.\n\n" \
		10 55 2 \
		"GRUB" "Use the GRUB bootloader (default)" \
		"LILO" "Use the LILO bootloader" 2>$ANSWER
	case $(cat $ANSWER) in
		"GRUB") dogrub ;;
		"LILO") dolilo ;;
	esac
}

