#!/bin/sh

#TODO: this should be fixed on the installcd.
modprobe dm-crypt || show_warning modprobe 'Could not modprobe dm-crypt. no support for disk encryption'
modprobe aes-i586 || show_warning modprobe 'Could not modprobe aes-i586. no support for disk encryption'



TMP_DEV_MAP=/home/arch/aif/runtime/dev.map
TMP_FSTAB=/home/arch/aif/runtime/.fstab
TMP_PARTITIONS=/home/arch/aif/runtime/.partitions
TMP_FILESYSTEMS=/home/arch/aif/runtime/.filesystems # Only used internally by this library.  Do not even think about using this as interface to this library.  it won't work

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
# the destination root partition last! TODO: only taking care of / is not enough, we can have the same problem on another level (eg /a/b/c and /a/b)
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


generate_filesystem_list ()
{
	echo -n > $TMP_FILESYSTEMS
	while read part type label fs_string
	do
		if [ "$fs_string" != no_fs ]
		then
			for fs in `sed 's/|/ /g' <<< $fs_string` # this splits multiple fs'es up, or just takes the one if there is only one (lvm vg's can have more then one lv)
			do
				fs_type=`       cut -d ';' -f 1 <<< $fs`
				fs_create=`     cut -d ';' -f 2 <<< $fs`
				fs_mountpoint=` cut -d ';' -f 3 <<< $fs`
				fs_mount=`      cut -d ';' -f 4 <<< $fs`
				fs_opts=`       cut -d ';' -f 5 <<< $fs`
				fs_label=`      cut -d ';' -f 6 <<< $fs`
				fs_params=`     cut -d ';' -f 7 <<< $fs`
				echo "$part $part_type $part_label $fs_type $fs_create $fs_mountpoint $fs_mount $fs_opts $fs_label $fs_params" >> $TMP_FILESYSTEMS
			done
		fi
	done < $BLOCK_DATA

}


# process all entries in $BLOCK_DATA, create all blockdevices and filesystems and mount them correctly, destroying what's necessary first.
process_filesystems ()
{
	generate_filesystem_list

	# phase 1: deconstruct all mounts in the vfs that are about to be reconstructed. (and also swapoff where appropriate)
	# re-order list so that we umount in the correct order. eg first umount /a/b/c, then /a/b. we sort alphabetically, which has the side-effect of sorting by stringlength, hence by vfs dependencies.

	sort -t \  -k 2 test $TMP_FILESYSTEMS | tac | while read part part_type part_label fs_type fs_create fs_mountpoint fs_mount fs_opts fs_label fs_params
	do
		if [ "$fs_type" = swap ]
		then
			swapoff $part
		elif [ "$fs_mountpoint" != no_mount ]
		then
			[ "$fs_mount" = target ] && fs_mountpoint=$var_TARGET_DIR$fs_mountpoint
			umount $fs_mountpoint
		fi
	done

	# TODO: phase 2: deconstruct blockdevices if they would exist already (destroy any lvm things, dm_crypt devices etc in the correct order)
	# in theory devices with same names could be stacked on each other with different dependencies.  I hope that's not the case for now.  In the future maybe we should deconstruct things we need and who are in /etc/mtab or something.
	# targets for deconstruction: /dev/mapper devices and lvm PV's who contain no fs, or a non-lvm/dm_crypt fs. TODO: improve regexes
	# after deconstructing. the parent must be updated to reflect the vanished child.

# TODO: as long as devices in this list remains and exist physically
# TODO: abort when there still are physical devices listed, but we tried to deconstruct them already, give error

	egrep '\+|mapper' $BLOCK_DATA | egrep -v ' lvm-pv;| lvm-vg;| lvm-lv;| dm_crypt;' | while read part part_type part_label fs
	do
		real_part=${part/+/}
		if [ -b "$real_part" ]
		then
			debug "Attempting deconstruction of device $part (type $part_type)"
			[ "$part_type" = lvm-pv   ] && ( pvremove             $part || show_warning "process_filesystems blockdevice deconstruction" "Could not pvremove $part") 
			[ "$part_type" = lvm-vg   ] && ( vgremove -f          $part || show_warning "process_filesystems blockdevice deconstruction" "Could not vgremove -f $part")
			[ "$part_type" = lvm-lv   ] && ( lvremove -f          $part || show_warning "process_filesystems blockdevice deconstruction" "Could not lvremove -f $part")
			[ "$part_type" = dm_crypt ] && ( cryptsetup luksClose $part || show_warning "process_filesystems blockdevice deconstruction" "Could not cryptsetup luksClose $part")
		else
			debug "Skipping deconstruction of device $part (type $part_type) because it doesn't exist"
		fi
	done

	# TODO: phase 3: create all blockdevices in the correct order (for each fs, the underlying block device must be available so dependencies must be resolved. for lvm:first pv's, then vg's, then lv's etc, but all device mapper devices need attention)

	# TODO: phase 4: mount all filesystems in the vfs in the correct order. (also swapon where appropriate)
	# reorder file by strlen of mountpoint (or alphabetically), so that we don't get 'overridden' mountpoints (eg you don't mount /a/b/c and then /a/b.  checking whether the parent dir exists is not good -> sort -t \  -k 2
	 sort -t \  -k 2 test


	debug "process_filesystems Called.  checking all entries in $BLOCK_DATA"
	rm -f $TMP_FSTAB
	devs_avail=1
	while [ $devs_avail = 1 ]
	do
		devs_avail=0
		for part in `findpartitions`
		do
			if entry=`grep ^$part $BLOCK_DATA`
			then
				process_filesystem "$entry" && sed -i "/^$part/d" $BLOCK_DATA && debug "$part processed and removed from $BLOCK_DATA"
				devs_avail=1
			fi
		done
	done
	entries=`wc -l $BLOCK_DATA`
	if [ $entries -gt 0 ]
	then
		die_error "Could not process all entries because not all available blockdevices became available.  Unprocessed:`awk '{print \$1}' $BLOCK_DATA`"
	else
		debug "All entries processed..."
	fi
}

# NOTE:  beware, the 'mount?' for now just matters for the location (if 'target', the target path gets prepended)

# FORMAT DEFINITION:

# MAIN FORMAT FOR $BLOCK_DATA (format used to interface with this library): one line per blockdevice, multiple fs'es in 1 'fs-string'
# $BLOCK_DATA entry.
# <blockdevice> type label/no_label <FS-string>/no_fs
# FS-string:
# type;recreate(yes/no);mountpoint;mount?(target,runtime,no);opts;label;params[|FS-string|...] where opts have _'s instead of whitespace


# ADDITIONAL INTERNAL FORMAT FOR $TMP_FILESYSTEMS: each filesystem on a separate line, so block devices can be on multiple lines
# part part_type part_label fs_type fs_create fs_mountpoint fs_mount fs_opts fs_label fs_params


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


# $1 blockdevice
# output will be in $BLOCKDEVICE_SIZE in MB
get_blockdevice_size ()
{
	[ -b "$1" ] || die_error "get_blockdevice_size needs a blockdevice as \$1 ($1 given)"
	blocks=`fdisk -s $1` || show_warning "Fdisk problem" "Something failed when trying to do fdisk -s $1"
	#NOTE: on some interwebs they say 1 block = 512B, on other internets they say 1 block = 1kiB.  1kiB seems to work for me.  don't sue me if it doesn't for you
	BLOCKDEVICE_SIZE=$(($blocks/1024))
}
