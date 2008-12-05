#!/bin/sh

#TODO: this should be fixed on the installcd.
modprobe dm-crypt || show_warning modprobe 'Could not modprobe dm-crypt. no support for disk encryption'
modprobe aes-i586 || show_warning modprobe 'Could not modprobe aes-i586. no support for disk encryption'



TMP_DEV_MAP=/home/arch/aif/runtime/dev.map
TMP_FSTAB=/home/arch/aif/runtime/.fstab
TMP_PARTITIONS=/home/arch/aif/runtime/.partitions
TMP_FILESYSTEMS=/home/arch/aif/runtime/.filesystems

# procedural code from quickinst functionized and fixed.
# there were functions like this in the setup script too, with some subtle differences.  see below
# NOTE: why were the functions in the setup called CHROOT_mount/umount? this is not chrooting ? ASKDEV
target_special_fs ()
{
	[ "$1" = on -o "$1" = off ] || die_error "special_fs needs on/off argument"
	if [ "$1" = on ]
	then
		# mount proc/sysfs first, so mkinitrd can use auto-detection if it wants
		! [ -d $var_TARGET_DIR/proc ] && mkdir $var_TARGET_DIR/proc
		! [ -d $var_TARGET_DIR/sys  ] && mkdir $var_TARGET_DIR/sys
		! [ -d $var_TARGET_DIR/dev  ] && mkdir $var_TARGET_DIR/dev
		#mount, if not mounted yet
		mount | grep -q "$var_TARGET_DIR/proc" || mount -t proc  none $var_TARGET_DIR/proc || die_error "Could not mount $var_TARGET_DIR/proc" # NOTE: setup script uses mount -t proc proc   ? what's best? ASKDEV
		mount | grep -q "$var_TARGET_DIR/sys"  || mount -t sysfs none $var_TARGET_DIR/sys  || die_error "Could not mount $var_TARGET_DIR/sys"  # NOTE: setup script uses mount -t sysfs sysfs ? what's best? ASKDEV
		mount | grep -q "$var_TARGET_DIR/dev"  || mount -o bind  /dev $var_TARGET_DIR/dev  || die_error "Could not mount $var_TARGET_DIR/dev"
	elif [ "$1" = off ]
	then
		umount $var_TARGET_DIR/proc || die_error "Could not umount $var_TARGET_DIR/proc"
		umount $var_TARGET_DIR/sys  || die_error "Could not umount $var_TARGET_DIR/sys"
		umount $var_TARGET_DIR/dev  || die_error "Could not umount $var_TARGET_DIR/dev"
	fi
}


# taken from setup
# Disable swap and all mounted partitions for the destination system. Unmount
# the destination root partition last!
target_umountall()
{
	infofy "Disabling swapspace, unmounting already mounted disk devices..."
	swapoff -a >/dev/null 2>&1
	umount $(mount | grep -v "${var_TARGET_DIR} " | grep "${var_TARGET_DIR}" | sed 's|\ .*||g') >/dev/null 2>&1
	umount $(mount | grep    "${var_TARGET_DIR} "                            | sed 's|\ .*||g') >/dev/null 2>&1
}


# taken from setup script, modified for separator control
# $1 set to 1 to echo a newline after device instead of a space (optional)
# $2 extra things to echo for each device (optional)
# $3 something to append directly after the device (optional)
finddisks() {
    workdir="$PWD"
    cd /sys/block 
    # ide devices 
    for dev in $(ls | egrep '^hd'); do
        if [ "$(cat $dev/device/media)" = "disk" ]; then
            echo -n "/dev/$dev$3"
            [ "$1" = 1 ] && echo || echo -n ' '
            [ "$2" ] && echo $2
        fi
    done  
    #scsi/sata devices
    for dev in $(ls | egrep '^sd'); do
        # TODO: what is the significance of 5? ASKDEV
        if ! [ "$(cat $dev/device/type)" = "5" ]; then
            echo -n "/dev/$dev$3"
            [ "$1" = 1 ] && echo || echo -n ' '
            [ "$2" ] && echo $2
        fi
    done  
    # cciss controllers
    if [ -d /dev/cciss ] ; then
        cd /dev/cciss
        for dev in $(ls | egrep -v 'p'); do
            echo -n "/dev/cciss/$dev$3"
            [ "$1" = 1 ] && echo || echo -n ' '
            [ "$2" ] && echo $2
        done
    fi
    # Smart 2 controllers
    if [ -d /dev/ida ] ; then
        cd /dev/ida
        for dev in $(ls | egrep -v 'p'); do
            echo -n"/dev/ida/$dev$3"
            [ "$1" = 1 ] && echo || echo -n ' '
            [ "$2" ] && echo $2
        done
    fi
    cd "$workdir"
}


# getuuid(). taken and modified from setup. this can probably be more improved. return an exit code, rely on blkid's exit codes etc.
# converts /dev/[hs]d?[0-9] devices to UUIDs
#
# parameters: device file
# outputs:    UUID on success
#             nothing on failure
# returns:    nothing
getuuid()
{
	[ -z "$1" ] && die_error "getuuid needs an argument"
	[ "${1%%/[hs]d?[0-9]}" != "${1}" ] && echo "$(blkid -s UUID -o value ${1})"  
}


# taken from setup script, slightly optimized and modified for separator control
# $1 set to 1 to echo a newline after partition instead of a space (optional)
# $2 extra things to echo for each partition (optional)
# $3 something to append directly after the partition (optional) TODO: refactor code so there's a space in between, merge $2 and $3. use echo -e to print whatever user wants
findpartitions() {
	workdir="$PWD"
	for devpath in $(finddisks)
	do
		disk=$(echo $devpath | sed 's|.*/||')
		cd /sys/block/$disk   
		for part in $disk*
		do
			# check if not already assembled to a raid device.  TODO: what is the significance of the 5? ASKDEV
			if ! [ "$(grep $part /proc/mdstat 2>/dev/null)" -o "$(fstype 2>/dev/null </dev/$part | grep lvm2)" -o "$(sfdisk -c /dev/$disk $(echo $part | sed -e "s#$disk##g") 2>/dev/null | grep "5")" ]
			then
				if [ -d $part ]
				then  
					echo -n "/dev/$part$3"
					[ "$1" = 1 ] && echo || echo -n ' '
					[ "$2" ] && echo $2
				fi
			fi
		done
	done
	# include any mapped devices
	for devpath in $(ls /dev/mapper 2>/dev/null | grep -v control)
	do
		echo -n "/dev/mapper/$devpath$3"
		[ "$1" = 1 ] && echo || echo -n ' '
		[ "$2" ] && echo $2
	done
	# include any raid md devices
	for devpath in $(ls -d /dev/md* | grep '[0-9]' 2>/dev/null)
	do
		if grep -qw $(echo $devpath /proc/mdstat | sed -e 's|/dev/||g')
		then
			echo -n "$devpath$3"
			[ "$1" = 1 ] && echo || echo -n ' '
			[ "$2" ] && echo $2
		fi
	done
	# inlcude cciss controllers
	if [ -d /dev/cciss ]
	then
		cd /dev/cciss
		for dev in $(ls | egrep 'p')
		do
			echo -n "/dev/cciss/$dev$3"
			[ "$1" = 1 ] && echo || echo -n ' '
			[ "$2" ] && echo $2
		done
	fi
	# inlcude Smart 2 controllers
	if [ -d /dev/ida ]
	then
		cd /dev/ida
		for dev in $(ls | egrep 'p')
		do
			echo -n "/dev/ida/$dev$3"
			[ "$1" = 1 ] && echo || echo -n ' '
			[ "$2" ] && echo $2
		done
	fi

	cd "$workdir"
}


# taken from setup
get_grub_map() {
	rm $TMP_DEV_MAP #TODO: this doesn't exist? is this a problem? ASKDEV
	infofy "Generating GRUB device map...\nThis could take a while.\n\n Please be patient."
	$var_TARGET_DIR/sbin/grub --no-floppy --device-map $TMP_DEV_MAP >/tmp/grub.log 2>&1 <<EOF
quit
EOF
}


# TODO: $1 is what?? ASKDEV
# taken from setup. slightly edited.
mapdev() {
    partition_flag=0
    device_found=0
    devs=$( grep -v fd $TMP_DEV_MAP | sed 's/ *\t/ /' | sed ':a;$!N;$!ba;s/\n/ /g')
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
        echo "DEVICE NOT FOUND" >&2
        return 2
    fi
}


# _mkfs() taken from setup code and altered.
# Create and mount filesystems in our destination system directory.
#
# args:
#  $1 device: target block device
#  $2 fstype: type of filesystem located at the device (or what to create)
#  $3 label:  label/name for the FS (you can pass an empty string) (optional)
#  $4 opts:   extra opts for the mkfs program (optional)


# returns: 1 on failure
_mkfs() {
	local _device=$1
	local _fstype=$2
	local _label=$3
	local opts=$4

	debug "_mkfs: _device: $1, fstype: $2, label: $3, opts: $4"
	# make sure the fstype is one we can handle
	local knownfs=0
	for fs in xfs jfs reiserfs ext2 ext3 vfat swap dm_crypt lvm-pv lvm-vg lvm-lv; do
		[ "${_fstype}" = "${fs}" ] && knownfs=1 && break
	done

	[ -z "$_label" ] && _label=default #TODO. when creating more then 1 VG we will get errors that it exists already. we should (per type) add incrementing numbers or something
	[ $knownfs -eq 0 ] && ( show_warning 'mkfs' "unknown fstype ${_fstype} for ${_device}" ; return 1 )
	local ret
	case ${_fstype} in
		xfs)      mkfs.xfs -f ${_device}           $opts >$LOG 2>&1; ret=$? ;;
		jfs)      yes | mkfs.jfs ${_device}        $opts >$LOG 2>&1; ret=$? ;;
		reiserfs) yes | mkreiserfs ${_device}      $opts >$LOG 2>&1; ret=$? ;;
		ext2)     mke2fs "${_device}"              $opts >$LOG 2>&1; ret=$? ;;
		ext3)     mke2fs -j ${_device}             $opts >$LOG 2>&1; ret=$? ;;
		vfat)     mkfs.vfat ${_device}             $opts >$LOG 2>&1; ret=$? ;;
		swap)     mkswap ${_device}                $opts >$LOG 2>&1; ret=$? ;;
		dm_crypt) [ -z "$opts" ] && opts='-c aes-xts-plain -y -s 512';
		          cryptsetup $opts luksFormat ${_device} >$LOG 2>&1; ret=$? ;;
		lvm-pv)   pvcreate $opts ${_device}              >$LOG 2>&1; ret=$? ;;
		lvm-vg)   vgcreate $opts $_label ${_device}      >$LOG 2>&1; ret=$? ;;
		lvm-lv)   lvcreate $opts -n $_label ${_device}   >$LOG 2>&1; ret=$? ;; #$opts is usually something like -L 10G
		# don't handle anything else here, we will error later
	esac
	[ "$ret" != 0 ] && ( show_warning mkfs "Error creating filesystem ${_fstype} on ${_device}" ; return 1 )
	sleep 2
}


# auto_fstab(). taken from setup
# preprocess fstab file
# comments out old fields and inserts new ones
# according to partitioning/formatting stage
#
target_configure_fstab()
{
	if [ -f $TMP_FSTAB ]
	then
		# comment out stray /dev entries
		sed -i 's/^\/dev/#\/dev/g' $var_TARGET_DIR/etc/fstab
		# append entries from new configuration
		sort $TMP_FSTAB >>$var_TARGET_DIR/etc/fstab
	fi
}


# partitions a disk. heavily altered
# $1 device to partition
# $2 a string of the form: <partsize>:<fstype>[:+] (the + is bootable flag)
partition()
{
	debug "Partition called like: partition '$1' '$2'"
	[ -z "$1" ] && die_error "partition() requires a device file and a partition string"
	[ -z "$2" ] && die_error "partition() requires a partition string"

	DEVICE=$1
	STRING=$2

	# validate DEVICE
	if [ ! -b "$DEVICE" ]; then
		notify "Device '$DEVICE' is not valid"
		return 1
	fi

	target_umountall

	# setup input var for sfdisk
	for fsspec in $STRING; do
		fssize=$(echo $fsspec | tr -d ' ' | cut -f1 -d:)
		fssize_spec=",$fssize"
		[ "$fssize" = "*" ] && fssize_spec=';'

		fstype=$(echo $fsspec | tr -d ' ' | cut -f2 -d:)
		fstype_spec=","
		[ "$fstype" = "swap" ] && fstype_spec=",S"

		bootflag=$(echo $fsspec | tr -d ' ' | cut -f3 -d:)
		bootflag_spec=""
		[ "$bootflag" = "+" ] && bootflag_spec=",*"

		sfdisk_input="${sfdisk_input}${fssize_spec}${fstype_spec}${bootflag_spec}\n"
	done

	sfdisk_input=$(printf "$sfdisk_input")

	# invoke sfdisk
	debug "Partition calls: sfdisk $DEVICE -uM >$LOG 2>&1 <<< $sfdisk_input"
	printk off
	infofy "Partitioning $DEVICE"
	sfdisk $DEVICE -uM >$LOG 2>&1 <<EOF
$sfdisk_input
EOF
    if [ $? -gt 0 ]; then
        notify "Error partitioning $DEVICE (see $LOG for details)"
        printk on
        return 1
    fi
    printk on

    return 0
}


# makes and mounts filesystems #TODO: don't use files but pass variables, integrate this with other functions
# $1 file with setup
fix_filesystems_deprecated ()
{
	[ -z "$1" -o ! -f "$1" ] && die_error "Fix_filesystems needs a file with the setup structure in it"

	# Umount all things first, umount / last.  After that create/mount stuff again, with / first
	# TODO: we now rely on the fact that the manual mountpoint selecter uses this order 'swap,/, /<*>'.  It works for now but it's not the most solid

    for line in $(tac $1); do
        MP=$(echo $line | cut -d: -f 3)
        umount ${var_TARGET_DIR}${MP}
    done
    for line in $(cat $1); do
        PART=$(echo $line | cut -d: -f 1)
        FSTYPE=$(echo $line | cut -d: -f 2)
        MP=$(echo $line | cut -d: -f 3)
        DOMKFS=$(echo $line | cut -d: -f 4)
        if [ "$DOMKFS" = "yes" ]; then
            if [ "$FSTYPE" = "swap" ]; then
                infofy "Creating and activating swapspace on $PART"
            else
                infofy "Creating $FSTYPE on $PART, mounting to ${var_TARGET_DIR}${MP}"
            fi
            _mkfs yes $PART $FSTYPE $var_TARGET_DIR $MP || return 1
        else
            if [ "$FSTYPE" = "swap" ]; then
                infofy "Activating swapspace on $PART"
            else
                infofy "Mounting $PART to ${var_TARGET_DIR}${MP}"
            fi
            _mkfs no $PART $FSTYPE $var_TARGET_DIR $MP || return 1
        fi
        sleep 1
    done

	return 0
}


# file layout:
#TMP_PARTITIONS
# disk partition-scheme

# go over each disk in $TMP_PARTITIONS and partition it
process_disks ()
{
	while read disk scheme
	do
		process_disk $disk "$scheme"
	done < $TMP_PARTITIONS
}


process_disk ()
{
	partition $1 $2
}


# go over each filesystem in $TMP_FILESYSTEMS, reorder them so that each entry has it's correspondent block device available (eg if you need /dev/mapper/foo which only becomes available after some other entry is processed) and process them
process_filesystems ()
{
	#TODO: reorder file by strlen of mountpoint (or alphabetically), so that we don't get 'overridden' mountpoints (eg you don't mount /a/b/c and then /a/b.  checking whether the parent dir exists is not good -> sort -t \  -k 2
	#TODO: we must make sure we have created all PV's, then reate a vg and the lv's.
	#TODO: 'deconstruct' the mounted filesystems, pv's, lv's,vg's,dm_crypt's.. in the right order before doing this (opposite order of construct) and swapoff.
	debug "process_filesystems Called.  checking all entries in $TMP_FILESYSTEMS"
	rm -f $TMP_FSTAB
	devs_avail=1
	while [ $devs_avail = 1 ]
	do
		devs_avail=0
		for part in `findpartitions`
		do
			if entry=`grep ^$part $TMP_FILESYSTEMS`
			then
				process_filesystem "$entry" && sed -i "/^$part/d" $TMP_FILESYSTEMS && debug "$part processed and removed from $TMP_FILESYSTEMS"
				devs_avail=1
			fi
		done
	done
	entries=`wc -l $TMP_FILESYSTEMS`
	if [ $entries -gt 0 ]
	then
		die_error "Could not process all entries because not all available blockdevices became available.  Unprocessed:`awk '{print \$1}' $TMP_FILESYSTEMS`"
	else
		debug "All entries processed..."
	fi
}


#TMP_FILESYSTEMS beware, the 'mount?' for now just matters for the location (if 'target', the target path gets prepended)
#blockdevice:filesystem:mountpoint:recreate FS?(yes/no):mount?(target,runtime,no)[:extra options for specific filesystem]

# make a filesystem on a blockdevice and mount if requested.
process_filesystem ()
{
	[ -z "$1" ] && die_error "process_filesystem needs a FS entry"
	debug "process_filesystem $1"
	line=$1
        BLOCK=$( echo $line | cut -d: -f 1)
        FSTYPE=$(echo $line | cut -d: -f 2)
        MP=$(    echo $line | cut -d: -f 3) # can be null for lvm/dm_crypt stuff
        DOMKFS=$(echo $line | cut -d: -f 4)
        DOMNT=$( echo $line | cut -d: -f 5)
        OPTS=$(  echo $line | cut -d: -f 6)

	if [ "$DOMKFS" = yes ]
	then
		 _mkfs $BLOCK $FSTYPE $OPTS || return 1
	fi

	if [ "$DOMNT" = runtime -o "$DOMNT" = target ]
	then
		if [ "$FSTYPE" = swap ]
		then
			debug "swaponning $BLOCK"
			swapon $BLOCK >$LOG 2>&1 || ( show_warning 'Swapon' "Error activating swap: swapon $BLOCK"  ;  return 1 )
		elif [ "$FSTYPE" = dm_crypt ]
		then
			debug "cryptsetup luksOpen $BLOCK $dst"
			cryptsetup luksOpen $BLOCK $dst >$LOG 2>&1 || ( show_warning 'cryptsetup' "Error luksOpening $BLOCK on $dst"  ;  return 1 )
		else
			[ "$DOMNT" = runtime ] && dst=$MP
			[ "$DOMNT" = target  ] && dst=$var_TARGET_DIR$MP
			debug "mounting $BLOCK on $dst"
			mount -t $FSTYPE $BLOCK $dst >$LOG 2>&1 || ( show_warning 'Mount' "Error mounting $BLOCK on $dst"  ;  return 1 )
		fi
	fi

	# add to temp fstab
	if [ $MP != null -a $DOMNT = target ]
	then
		local _uuid="$(getuuid $BLOCK)"
		if [ -n "${_uuid}" ]; then
			_device="UUID=${_uuid}"
		fi
		echo -n "$BLOCK ${_mountpoint} $FSTYPE defaults 0 " >>$TMP_FSTAB
		if [ "$FSTYPE" = "swap" ]; then
			echo "0" >>$TMP_FSTAB
		else
			echo "1" >>$TMP_FSTAB
		fi
	fi

	return 0
}


# $1 filesystem type
get_filesystem_program ()
{
	[ -z "$1" ] && die_error "get_filesystem_program needs a filesystem id as \$1"
	[ $1 = ext2     ] && echo mkfs.ext2
	[ $1 = ext3     ] && echo mkfs.ext3
	[ $1 = reiserfs ] && echo mkreiserfs
	[ $1 = xfs      ] && echo mkfs.xfs
	[ $1 = jfs      ] && echo mkfs.jfs
	[ $1 = vfat     ] && echo mkfs.vfat
	[ $1 = lvm-pv   ] && echo pvcreate
	[ $1 = lvm-vg   ] && echo vgcreate
	[ $1 = lvg-lv   ] && echo lvcreate
	[ $1 = dm_crypt ] && echo cryptsetup
}