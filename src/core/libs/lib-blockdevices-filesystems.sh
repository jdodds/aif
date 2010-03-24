#!/bin/bash

# FORMAT DEFINITIONS:

# -- formats used to interface with this library --
# these files will persist during the entire aif session (and even after stopping aif)
# so you can use them to retrieve data from them (or use functions in this library to do that for you)
# $TMP_PARTITIONS
#    one line per partition, blockdevice + partioning string for sfdisk.  See docs for function partition for more info.
# $TMP_BLOCKDEVICES
#    one line per blockdevice, multiple fs'es in 1 'fs-string'
#    $TMP_BLOCKDEVICES entry.
#    <blockdevice> type label/no_label <FS-string>/no_fs
#    FS-string:
#    type;recreate(yes/no);mountpoint;mount?(target,runtime,no);opts;label;params[|FS-string|...] where opts/params have _'s instead of whitespace if needed
#    NOTE: the 'mount?' for now just matters for the location (if 'target', the target path gets prepended and mounted in the runtime system)
#    NOTE: filesystems that span multiple underlying filesystems/devices (eg lvm VG) should specify those in params, separated by colons.  \
#          the <blockdevice> in the beginning doesn't matter much, it can be pretty much any device, or not existent, i think.  But it's probably best to make it one of the devices listed in params
#          no '+' characters allowed for devices in $fs_params (eg use the real names)


# -- ADDITIONAL INTERNAL FORMATS --
# $TMP_FILESYSTEMS: each filesystem on a separate line, so block devices can appear multiple times be on multiple lines (eg LVM volumegroups with more lvm LV's)
# part part_type part_label fs_type fs_create fs_mountpoint fs_mount fs_opts fs_label fs_params



modprobe -q dm-crypt || show_warning modprobe 'Could not modprobe dm-crypt. no support for disk encryption'
modprobe -q aes-i586 || modprobe -q aes-x86-64 || show_warning modprobe 'Could not modprobe aes-i586 or aes-x86-64. no support for disk encryption'

TMP_DEV_MAP=$RUNTIME_DIR/aif-dev.map
TMP_FSTAB=$RUNTIME_DIR/aif-fstab
TMP_PARTITIONS=$RUNTIME_DIR/aif-partitions
TMP_FILESYSTEMS=$RUNTIME_DIR/aif-filesystems # Only used internally by this library.  Do not even think about using this as interface to this library.  it won't work
TMP_BLOCKDEVICES=$RUNTIME_DIR/aif-blockdata



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


# taken from setup #TODO: we should be able to not need this function. although it may still be useful. but maybe we shouldn't tie it to $var_TARGET_DIR, and let the user specify the base point as $1
# Disable swap and umount all mounted filesystems for the target system in the correct order. (eg first $var_TARGET_DIR/a/b/c, then $var_TARGET_DIR/a/b, then $var_TARGET_DIR/a until lastly $var_TARGET_DIR
target_umountall()
{
	infofy "Disabling all swapspace..." disks
	swapoff -a >/dev/null 2>&1
	declare target=${var_TARGET_DIR//\//\\/} # escape all slashes otherwise awk complains
	for mountpoint in $(mount | awk "/\/$target/ {print \$3}" | sort | tac )
	do
		infofy "Unmounting mountpoint $mountpoint" disks
		umount $mountpoint >/dev/null 2>$LOG
	done
}

# tells you which blockdevice is configured for the specific mountpoint
# $1 mountpoint
get_device_with_mount () {
	ANSWER_DEVICE=`grep ";$1;" $TMP_BLOCKDEVICES 2>/dev/null | cut -d ' ' -f1`
	[ -n "$ANSWER_DEVICE" ] # set correct exit code
}

# gives you a newline separated list of the blockdevice that hosts a certain filesystem, and below it, all underlying blockdevices supporting it, with also the blockdevice type.
# example:
# get_anchestors_mount ';/;' (suppose '/' is a filesystem on top of lvm on top of dm_crypt, you will get something like):
# /dev/mapper/cryptpool-cryptroot lvm-lv
# /dev/mapper/cryptpool lvm-vg
# /dev/mapper/sda2crypt+ lvm-pv
# /dev/mapper/sda2crypt dm_crypt
# /dev/sda2 raw
# $1 a "recognizer": a string that will match the filesystem section uniquely (using egrep), such as ';<mountpoint>;' or other specific attributes of the hosted filesystem(s)
get_anchestors_mount () {
	debug 'FS' "Finding anchestor for: $1"
	local buffer=
	read block type leftovers <<< `egrep "$1" $TMP_BLOCKDEVICES 2>/dev/null`
	[ -z "$type" ] && return 1
	buffer="$block $type"
	if [ $type != 'raw' ]
	then
		if [ $type == lvm-lv ]
		then
			lv=`echo $block | sed 's/.*-//'` # /dev/mapper/cryptpool-cryptroot -> cryptroot. TODO: this may give unexpected behavior of LV has a '-' in its name
			recognizer="lvm-lv;(yes|no);no_mountpoint;[^;]{1,};[^;]{1,};$lv;[^;]{1,}"
		elif [ $type == lvm-vg ]
		then
			recognizer="lvm-vg;(yes|no);no_mountpoint;[^;]{1,};[^;]{1,};`basename $block`;[^;]{1,}"
		elif [ $type == lvm-pv ]
		then
			# here we cheat a bit: we cannot match the FS section because usually we don't give a PV recognizable attributes, but since we name a PV as blockdevice + '+' we can match the blockdevice
			recognizer="^${block/+/} .* lvm-pv;"
		elif [ $type == dm_crypt ]
		then
			recognizer="dm_crypt;(yes|no);no_mountpoint;[^;]{1,};[^;]{1,};`basename $block`;[^;]{1,}"
		fi
		get_anchestors_mount "$recognizer" && buffer="$buffer
$ANSWER_DEVICES"
	fi
	ANSWER_DEVICES=$buffer
	debug 'FS' "Found anchestors: $ANSWER_DEVICES"
	[ -n "$ANSWER_DEVICES" ]
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
    #scsi/sata devices, and virtio blockdevices (/dev/vd*)
    for dev in $(ls | egrep '^[sv]d'); do
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


# parameters: device file
# outputs:    LABEL on success
#             nothing on failure
# returns:    nothing
getlabel()
{
	[ -z "$1" ] && die_error "getlabel needs an argument"
	[ "${1%%/[hs]d?[0-9]}" != "${1}" ] && echo "$(blkid -s LABEL -o value ${1})"
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
	rm $TMP_DEV_MAP &>/dev/null #TODO: this doesn't exist? is this a problem? ASKDEV
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
# $2 a string of the form: <partsize in MiB>:<fstype>[:+] (the + is bootable flag)
partition()
{
	debug 'FS' "Partition called like: partition '$1' '$2'"
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
	# format: each line=1 part.  <start> <size> <id> <bootable>[ <c,h,s> <c,h,s>]

	read -r -a fsspecs <<< "$STRING"  # split up like this otherwise '*' will be globbed. which usually means an entry containing * is lost

	for fsspec in "${fsspecs[@]}"; do
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

	sfdisk_input=$(printf "$sfdisk_input") # convert \n to newlines

	# invoke sfdisk
	debug 'FS' "Partition calls: sfdisk $DEVICE -uM >$LOG 2>&1 <<< $sfdisk_input"
	printk off
	sfdisk -D $DEVICE -uM >$LOG 2>&1 <<EOF
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


# go over each disk in $TMP_PARTITIONS and partition it
process_disks ()
{
	while read disk scheme
	do
		process_disk $disk "$scheme" || return $?
	done < $TMP_PARTITIONS
}


process_disk ()
{
	infofy "Partitioning $1" disks
	partition $1 "$2"
}

# $1 fs_string
parse_filesystem_string ()
{
	fs="$1"
	fs_type=`       cut -d ';' -f 1 <<< $fs`
	fs_create=`     cut -d ';' -f 2 <<< $fs`
	fs_mountpoint=` cut -d ';' -f 3 <<< $fs`
	fs_mount=`      cut -d ';' -f 4 <<< $fs`
	fs_opts=`       cut -d ';' -f 5 <<< $fs`
	fs_label=`      cut -d ';' -f 6 <<< $fs`
	fs_params=`     cut -d ';' -f 7 <<< $fs`
}


generate_filesystem_list ()
{
	echo -n > $TMP_FILESYSTEMS
	while read part part_type part_label fs_string
	do
		if [ "$fs_string" != no_fs ]
		then
			for fs in `sed 's/|/ /g' <<< $fs_string` # this splits multiple fs'es up, or just takes the one if there is only one (lvm vg's can have more then one lv)
			do
				parse_filesystem_string "$fs"
				echo "$part $part_type $part_label $fs_type $fs_create $fs_mountpoint $fs_mount $fs_opts $fs_label $fs_params" >> $TMP_FILESYSTEMS
			done
		fi
	done < $TMP_BLOCKDEVICES

}


# process all entries in $TMP_BLOCKDEVICES, create all blockdevices and filesystems and mount them correctly
process_filesystems ()
{
	debug 'FS' "process_filesystems Called.  checking all entries in $TMP_BLOCKDEVICES"
	rm -f $TMP_FSTAB
	generate_filesystem_list
	returncode=0

	# phase 1: create all blockdevices and filesystems in the correct order (for each fs, the underlying block/lvm/devicemapper device must be available so dependencies must be resolved. for lvm:first pv's, then vg's, then lv's etc)
	# don't let them mount yet. we take care of all that ourselves in the next phase

	infofy "Phase 1: Creating filesystems & blockdevices" disks
	done_filesystems=
	for i in `seq 1 10`
	do
		open_items=0
		while read part part_type part_label fs_type fs_create fs_mountpoint fs_mount fs_opts fs_label fs_params
		do
			fs_id="$part $fs_type $fs_mountpoint $fs_opts $fs_label $fs_params"
			if [ "$fs_create" = yes ]
			then
				if check_is_in "$fs_id" "${done_filesystems[@]}"
				then
					debug 'FS' "$fs_id ->Already done"
				else
					# We can't always do -b on the lvm VG. because the devicefile sometimes doesn't exist for a VG. vgdisplay to the rescue!
					if [ "$part_type" = lvm-vg ] && vgdisplay $part | grep -q 'VG Name' # $part is a lvm VG and it exists. note that vgdisplay exists 0 when the requested vg doesn't exist.
					then
						debug 'FS' "$fs_id ->Still need to do it: Making the filesystem on a vg volume"
						infofy "Making $fs_type filesystem on $part" disks
						process_filesystem $part $fs_type $fs_create $fs_mountpoint no_mount $fs_opts $fs_label $fs_params && done_filesystems+=("$fs_id") || returncode=1
					elif [ "$part_type" != lvm-pv -a -b "$part" ] # $part is not a lvm PV and it exists
					then
						debug 'FS' "$fs_id ->Still need to do it: Making the filesystem on a non-pv volume"
						infofy "Making $fs_type filesystem on $part" disks
						process_filesystem $part $fs_type $fs_create $fs_mountpoint no_mount $fs_opts $fs_label $fs_params && done_filesystems+=("$fs_id") || returncode=1
					elif [ "$part_type" = lvm-pv ] && pvdisplay ${fs_params//:/ } >/dev/null # $part is a lvm PV. all needed lvm pv's exist. note that pvdisplay exits 5 as long as one of the args doesn't exist
					then
						debug 'FS' "$fs_id ->Still need to do it: Making the filesystem on a pv volume"
						infofy "Making $fs_type filesystem on $part" disks
						process_filesystem ${part/+/} $fs_type $fs_create $fs_mountpoint no_mount $fs_opts $fs_label $fs_params && done_filesystems+=("$fs_id") || returncode=1
					else
						debug 'FS' "$fs_id ->Cannot do right now..."
						open_items=1
					fi
				fi
			fi
		done < $TMP_FILESYSTEMS
		[ $open_items -eq 0 ] && break
	done
	[ $open_items -eq 1 ] && show_warning "Filesystem/blockdevice processor problem" "Warning: Could not create all needed filesystems.  Either the underlying blockdevices didn't became available in 10 iterations, or process_filesystem failed" && returncode=1



	# phase 2: mount all filesystems in the vfs in the correct order. (also swapon where appropriate)

	infofy "Phase 2: Mounting filesystems" disks
	while read part part_type part_label fs_type fs_create fs_mountpoint fs_mount fs_opts fs_label fs_params
	do
		if [ "$fs_mountpoint" != no_mountpoint ]
		then
			infofy "Mounting $part ($fs_type) on $fs_mountpoint" disks
			process_filesystem $part $fs_type no $fs_mountpoint $fs_mount $fs_opts $fs_label $fs_params || returncode=1
		elif [ "$fs_type" = swap ]
		then
			infofy "Swaponning $part" disks
			process_filesystem $part $fs_type no $fs_mountpoint $fs_mount $fs_opts $fs_label $fs_params || returncode=1
		fi
	done < <(sort -t \  -k 6 $TMP_FILESYSTEMS)

	BLOCK_ROLLBACK_USELESS=0
	[ $returncode -eq 0 ] && infofy "Done processing filesystems/blockdevices" disks 1 && return 0
	return $returncode
}


# Roll back all "filesystems" (normal ones and dm-mapper based stuff) specified in $BLOCK_DATA.  Not partitions.  Doesn't restore data after you erased it, of course.
rollback_filesystems ()
{
	infofy "Rolling back filesystems..." disks
	generate_filesystem_list
	local warnings=
	rm -f $TMP_FSTAB

	# phase 1: destruct all mounts in the vfs and swapoff swap volumes who are listed in $BLOCK_DATA
	# re-order list so that we umount in the correct order. eg first umount /a/b/c, then /a/b. we sort alphabetically, which has the side-effect of sorting by stringlength, hence by vfs dependencies.

	infofy "Phase 1: Umounting all specified mountpoints" disks
	done_umounts= # We translate some devices back to their original (eg /dev/sda3+ -> /dev/sda3 for lvm PV's). No need to bother user twice for such devices.
	while read part part_type part_label fs_type fs_create fs_mountpoint fs_mount fs_opts fs_label fs_params
	do
		if [ "$fs_type" = swap ]
		then
			infofy "(Maybe) Swapoffing $part" disks
			swapoff $part &>/dev/null # could be that it was not swappedon yet.  that's not a problem at all.
		elif [ "$fs_mountpoint" != no_mountpoint ]
		then
			part_real=${part/+/}
			if ! check_is_in "$part_real" "${done_umounts[@]}"
			then
				infofy "(Maybe) Umounting $part_real" disks
				if mount | grep -q "^$part_real " # could be that this was not mounted yet. no problem, we can just skip it then.
				then
					if umount $part_real >$LOG
					then
						done_umounts+=("$part_real")
					else
						warnings="$warnings\nCould not umount umount $part_real .  Probably device is still busy.  See $LOG"
						show_warning "Umount failure" "Could not umount umount $part_real .  Probably device is still busy.  See $LOG" #TODO: fix device busy things
					fi
				fi
			fi
		fi
	done < <(sort -t \  -k 6 -r $TMP_FILESYSTEMS)


	# phase 2: destruct blockdevices listed in $BLOCK_DATA if they would exist already, in the correct order (first lvm LV, then VG, then PV etc)
	# targets are device-mapper devices such as any lvm things, dm_crypt devices, etc and lvm PV's.

	# Possible approach 1 (not implemented): for each target in $TMP_BLOCKDEVICES, check that it has no_fs or has a non-lvm/dm_crypt fs. (egrep -v ' lvm-pv;| lvm-vg;| lvm-lv;| dm_crypt;' ) and clean it 
	#                      -> requires updating of underlying block device string when you clean something, on a copy of .block_data etc. too complicated
	# Approach 2 : iterate over all targets in $TMP_BLOCKDEVICES as much as needed, until a certain limit, and in each loop check what can be cleared by looking at the real, live usage of / dependencies on the partition.
	#                      -> easier (implemented)


	infofy "Phase 2: destructing relevant blockdevices" disks
	for i in `seq 1 10`
	do
		open_items=0
		while read part part_type part_label fs_string
		do

			real_part=${part/+/}

			# do not destroy a blockdevice if it hosts one or more filesystems that were set to not recreate
			# fs_string = one or more "$fs_type;$fs_create;$fs_mountpoint;target;$fs_opts;$fs_label;$fs_params", separated by ':'
			# there is probably a nice regex to check this but i'm bad at regexes.
			if echo "$fs_string" | grep -q ';yes;/' || echo "$fs_string" | grep -q ';yes;no_mountpoint'
			then
				infofy "Skipping destruction of $part ($part_type) because one of the filesystems on it contains data you want to keep"
				# TODO: it's possible that if we don't clear a blockdevice here because there is something on it with valuable data, that this blockdevice itself is hosted on some other blockdevice (eg lvm VG,PV or dm_crypt), \
				#       that blockdevice cannot be cleared as well because it depends on this one, so after 10 iterations the user will get a warning that not everything is cleared.  so we should fix this someday.
			elif [ "$part_type" = dm_crypt ] # Can be in use for: lvm-pv or raw. we don't need to care about raw (it will be unmounted so it can be destroyed)
			then
				if [ -b $real_part ] && cryptsetup status $real_part &>/dev/null # don't use 'isLuks' it only works for the "underlying" device (eg in /dev/sda1 -> luksOpen -> /dev/mapper/foo, isLuks works only on the former. status works on the latter too)
				then
					if pvdisplay $real_part &>/dev/null
					then
						debug 'FS' "$part ->Cannot do right now..."
						open_items=1
					else
						infofy "Attempting destruction of device $part (type $part_type)" disks
						if ! cryptsetup luksClose $real_part &>$LOG
						then
							warnings="$warnings\nCould not cryptsetup luksClose $real_part"
							show_warning "process_filesystems blockdevice destruction" "Could not cryptsetup luksClose $real_part"
						fi
					fi
				else
					debug 'FS' "Skipping destruction of device $part (type $part_type) because it doesn't exist"
				fi
			elif [ "$part_type" = lvm-pv ] # Can be in use for: lvm-vg
			then
				if [ -b $real_part ] && pvdisplay $real_part &>/dev/null
				then
					if vgdisplay -v 2>/dev/null | grep -q $real_part # check if it's in use
					then
						debug 'FS' "$part ->Cannot do right now..."
						open_items=1
					else
						infofy "Attempting destruction of device $part (type $part_type)" disks
						if ! pvremove $real_part &>$LOG
						then
							warnings="$warnings\nCould not pvremove $part"
							show_warning "process_filesystems blockdevice destruction" "Could not pvremove $part"
						fi
					fi
				else
					debug 'FS' "Skipping destruction of device $part (type $part_type) because it doesn't exist"
				fi
			elif [ "$part_type" = lvm-vg ] #Can be in use for: lvm-lv
			then
				if vgdisplay $part 2>/dev/null | grep -q 'VG Name' # workaround for non-existing lvm VG device files
				then
					open_lv=`vgdisplay -c $part 2>/dev/null | cut -d ':' -f6`
					if [ $open_lv -gt 0 ]
					then
						debug 'FS' "$part ->Cannot do right now..."
						open_items=1
					else
						infofy "Attempting destruction of device $part (type $part_type)" disks
						if ! vgremove $part &>$LOG # we shouldn't need -f because we clean up the lv's first.
						then
							warnings="$warnings\nCould not vgremove $part"
							show_warning "process_filesystems blockdevice destruction" "Could not vgremove $part"
						fi
					fi
				else
					debug 'FS' "Skipping destruction of device $part (type $part_type) because it doesn't exist"
				fi
			elif [ "$part_type" = lvm-lv ] #Can be in use for: dm_crypt or raw. we don't need to care about raw (it will be unmounted so it can be destroyed)
			then
				if lvdisplay $part &>/dev/null && ! vgdisplay $part 2>/dev/null | grep -q 'VG Name' # it exists: lvdisplay works, and it's not a volume group (you can do lvdisplay $volumegroup)
				then
					if cryptsetup isLuks $part &>/dev/null
					then
						debug 'FS' "$part ->Cannot do right now..."
						open_items=1
					else
						infofy "Attempting destruction of device $part (type $part_type)" disks
						if ! lvremove -f $part &>$LOG
						then
							warnings="$warnings\nCould not lvremove -f $part"
							show_warning "process_filesystems blockdevice destruction" "Could not lvremove -f $part"
						fi
					fi
				else
					debug 'FS' "Skipping destruction of device $part (type $part_type) because it doesn't exist"
				fi
			else
				die_error "Unrecognised partition type $part_type for partition $part.  This should never happen. please report this"
			fi
		done < <(egrep '\+|mapper' $TMP_BLOCKDEVICES) #TODO: improve regex
		[ $open_items -eq 0 ] && break
	done

	if [ $open_items -eq 1 ]
	then
		warnings="$warnings\nCould not destruct all filesystems/blockdevices.  It appears some depending filesystems/blockdevices could not be cleared in 10 iterations"
		show_warning "Filesystem/blockdevice processor problem" "Warning: Could not destruct all filesystems/blockdevices.  It appears some depending filesystems/blockdevices could not be cleared in 10 iterations"
	fi
	[ -n "$warnings" ] && infofy "Rollback failed" disks 1 && show_warning "Rollback problems" "Some problems occurred while rolling back: $warnings.\n Thisk needs to be fixed before retrying disk/filesystem creation or restarting the installer" && return 1
	infofy "Rollback succeeded" disks 1
	done_filesystems=
	BLOCK_ROLLBACK_USELESS=1
	return 0
}


# make a filesystem on a blockdevice and mount if needed.
# $1 partition
# $2 fs_type
# $3 fs_create     (optional. defaults to yes)
# $4 fs_mountpoint (optional. defaults to no_mountpoint)
# $5 fs_mount      (optional. defaults to no_mount)
# $6 fs_opts       (optional. defaults to no_opts)
# $7 fs_label      (optional. defaults to no_label or for lvm volumes who need a label (VG's and LV's) vg1,vg2,lv1 etc).  Note that if there's no label for a VG you probably did something wrong, because you probably want LV's on it so you need a label for the VG.
# $8 fs_params     (optional. defaults to no_params)

process_filesystem ()
{
	[ "$2" != lvm-lv ] && [ -z "$1" -o ! -b "$1" ] && die_error "process_filesystem needs a partition as \$1" # Don't do this for lv's.  It's a hack to workaround non-existence of VG device files.
	[ -z "$2" ]              && die_error "process_filesystem needs a filesystem type as \$2"
	debug 'FS' "process_filesystem $@"
	local ret=0

        part=$1
        fs_type=$2
	fs_create=${3:-yes}
	fs_mountpoint=${4:-no_mountpoint}
	fs_mount=${5:-no_mount}
	fs_opts=${6:-no_opts}
	fs_label=${7:-no_label}
	fs_params=${8:-no_params}
	[ "$fs_mountpoint" = no_mountpoint ] && fs_mountpoint=
	[ "$fs_mount"      = no_mount      ] && fs_mount=
	[ "$fs_opts"       = no_opts       ] && fs_opts=
	[ "$fs_label"      = no_label      ] && fs_label=
	[ "$fs_params"     = no_params     ] && fs_params=

	# Create the FS
	if [ "$fs_create" = yes ]
	then
		if ! program=`get_filesystem_program $fs_type`
		then
			show_warning "process_filesystem error" "Cannot determine filesystem program for $fs_type on $part.  Not creating this FS"
			return 1
		fi
		[ -z "$fs_label" ] && [ "$fs_type" = lvm-vg -o "$fs_type" = lvm-pv ] && fs_label=default #TODO. implement the incrementing numbers label for lvm vg's and lv's

		#TODO: health checks on $fs_params etc
		case ${fs_type} in #TODO: implement label, opts etc decently
			xfs)      mkfs.xfs -f $part           $opts >$LOG 2>&1; ret=$? ;;
			jfs)      yes | mkfs.jfs $part        $opts >$LOG 2>&1; ret=$? ;;
			reiserfs) yes | mkreiserfs $part      $opts >$LOG 2>&1; ret=$? ;;
			ext2)     mke2fs "$part"              $opts >$LOG 2>&1; ret=$? ;;
			ext3)     mke2fs -j $part             $opts >$LOG 2>&1; ret=$? ;;
			ext4)     mkfs.ext4 $part             $opts >$LOG 2>&1; ret=$? ;; #TODO: installer.git uses mke2fs -t ext4 -O dir_index,extent,uninit_bg , which is best?
			vfat)     mkfs.vfat $part             $opts >$LOG 2>&1; ret=$? ;;
			swap)     mkswap $part                $opts >$LOG 2>&1; ret=$? ;;
			dm_crypt) [ -z "$fs_params" ] && fs_params='-c aes-xts-plain -y -s 512';
			          fs_params=${fs_params//_/ }
                      infofy "Please enter your passphrase to encrypt the device (with confirmation)"
			          cryptsetup $fs_params $opts luksFormat -q $part >$LOG 2>&1 < /dev/tty ; ret=$? #hack to give cryptsetup the approriate stdin. keep in mind we're in a loop (see process_filesystems where something else is on stdin)
                      infofy "Please enter your passphrase to unlock the device"
			          cryptsetup       luksOpen $part $fs_label >$LOG 2>&1 < /dev/tty; ret=$? || ( show_warning 'cryptsetup' "Error luksOpening $part on /dev/mapper/$fs_label" ) ;;
			lvm-pv)   pvcreate $fs_opts $part              >$LOG 2>&1; ret=$? ;;
			lvm-vg)   # $fs_params: ':'-separated list of PV's
			          vgcreate $fs_opts $fs_label ${fs_params//:/ }      >$LOG 2>&1; ret=$? ;;
			lvm-lv)   # $fs_params = size string (eg '5G')
			          lvcreate -L $fs_params $fs_opts -n $fs_label `sed 's#/dev/mapper/##' <<< $part`   >$LOG 2>&1; ret=$? ;; #$opts is usually something like -L 10G # Strip '/dev/mapper/' part because device file may not exist.  TODO: do i need to activate them?
			# don't handle anything else here, we will error later
		esac
		BLOCK_ROLLBACK_USELESS=0
		[ "$ret" -gt 0 ] && { show_warning "process_filesystem error" "Error creating filesystem $fs_type on $part."; return 1; }
		sleep 2
	fi

	# Mount it, if requested.  Note that it's your responsability to figure out if you want this or not before calling me.  This will only work for 'raw' filesystems (ext,reiser,xfs, swap etc. not lvm stuff,dm_crypt etc)
	if [ "$fs_mount" = runtime -o "$fs_mount" = target ]
	then
		BLOCK_ROLLBACK_USELESS=0
		if [ "$fs_type" = swap ]
		then
			debug 'FS' "swaponning $part"
			swapon $part >$LOG 2>&1 || ( show_warning 'Swapon' "Error activating swap: swapon $part"  ; ret=1 )
			fs_mountpoint="swap" # actually it's a hack to set the mountpoint in this (late) stage. this could be cleaner..
		else
			[ "$fs_mount" = runtime ] && dst=$fs_mountpoint
			[ "$fs_mount" = target  ] && dst=$var_TARGET_DIR$fs_mountpoint
			debug 'FS' "mounting $part on $dst"
			mkdir -p $dst &>/dev/null # directories may or may not already exist
			mount -t $fs_type $part $dst >$LOG 2>&1 || ( show_warning 'Mount' "Error mounting $part on $dst" ; ret=1 )
		fi
	fi


	# Add to temp fstab, if not already there.
	if [ -n "$fs_mountpoint" -a "$fs_mount" = target ]
	then
		case "$PART_ACCESS" in
			label)
				local _label="$(getlabel $part)"
				if [ -n "${_label}" ]; then
					part="LABEL=${_label}"
				fi
				;;
			uuid)
				local _uuid="$(getuuid $part)"
				if [ -n "${_uuid}" ]; then
					part="UUID=${_uuid}"
				fi
				;;
		esac
		if ! grep -q "$part $fs_mountpoint $fs_type defaults 0 " $TMP_FSTAB 2>/dev/null #$TMP_FSTAB may not exist yet
		then
			echo -n "$part $fs_mountpoint $fs_type defaults 0 " >> $TMP_FSTAB
			if [ "$fs_type" = "swap" ]; then
				echo "0" >>$TMP_FSTAB
			else
				echo "1" >>$TMP_FSTAB
			fi
		fi
	fi

	return $ret

#TODO: if target has LVM volumes, copy /etc/lvm/backup to /etc on target (or maybe it can be regenerated with a command, i should look that up)

}


# $1 filesystem type
get_filesystem_program ()
{
	[ -z "$1" ] && die_error "get_filesystem_program needs a filesystem id as \$1"
	[ $1 = swap     ] && echo mkswap     && return 0
	[ $1 = ext2     ] && echo mkfs.ext2  && return 0
	[ $1 = ext3     ] && echo mkfs.ext3  && return 0
	[ $1 = ext4     ] && echo mkfs.ext4  && return 0
	[ $1 = reiserfs ] && echo mkreiserfs && return 0
	[ $1 = xfs      ] && echo mkfs.xfs   && return 0
	[ $1 = jfs      ] && echo mkfs.jfs   && return 0
	[ $1 = vfat     ] && echo mkfs.vfat  && return 0
	[ $1 = lvm-pv   ] && echo pvcreate   && return 0
	[ $1 = lvm-vg   ] && echo vgcreate   && return 0
	[ $1 = lvm-lv   ] && echo lvcreate   && return 0
	[ $1 = dm_crypt ] && echo cryptsetup && return 0
	return 1
}


# $1 blockdevice
# $2 unit: B, KiB, kB, MiB, MB, GiB or GB.  defaults to B (we follow IEEE 1541-2002 )
# output will be in $BLOCKDEVICE_SIZE
get_blockdevice_size ()
{
	[ -b "$1" ] || die_error "get_blockdevice_size needs a blockdevice as \$1 ($1 given)"
	unit=${2:-B}
	allowed_units=(B KiB kB MiB MB GiB GB)
	if ! check_is_in $unit "${allowed_units[@]}"
	then
		die_error "Unrecognized unit $unit!"
	fi

	# NOTES about older, deprecated methods:
	# - BLOCKDEVICE_SIZE=$(hdparm -I $1 | grep -F '1000*1000' | sed "s/^.*:[ \t]*\([0-9]*\) MBytes.*$/\1/") # if you do this on a partition, you get the size of the entire disk ! + hdparm only supports sata and ide. not scsi.
	# - unreliable method: on some interwebs they say 1 block = 512B, on other internets they say 1 block = 1kiB.  1kiB seemed to work for me.
	# blocks=`fdisk -s $1` || show_warning "Fdisk problem" "Something failed when trying to do fdisk -s $1"
	# BLOCKDEVICE_SIZE=$(($blocks/1024))

	bytes=$((`fdisk -l $1 2>/dev/null | sed -n '2p' | cut -d' ' -f5`))
	[ $unit = B   ] && BLOCKDEVICE_SIZE=$bytes
	[ $unit = KiB ] && BLOCKDEVICE_SIZE=$((bytes/2**10)) # /1024
	[ $unit = kB  ] && BLOCKDEVICE_SIZE=$((bytes/10**3)) # /1000
	[ $unit = MiB ] && BLOCKDEVICE_SIZE=$((bytes/2**20)) # ...
	[ $unit = MB  ] && BLOCKDEVICE_SIZE=$((bytes/10**6))
	[ $unit = GiB ] && BLOCKDEVICE_SIZE=$((bytes/2**30))
	[ $unit = GB  ] && BLOCKDEVICE_SIZE=$((bytes/10**9))
}


# $1 blockdevice (ex: /dev/md0 or /dev/sda1)
# return true when blockdevice is an md raid, otherwise return a unset value
mdraid_is-raid ()
{
    local israid
    if [ -z $1 ]; then
        # Don't call mdadm on empty blockdevice parameter!
        israid=""
    elif [ "$(mdadm --query $1 | cut -d':' -f2)" == " is not an md array" ]; then
        israid=""
    else
        israid=true
    fi
    echo $israid
}

# $1 md raid blockdevice (ex: /dev/md0)
# return the array member device which is slave 0 in the given array
# ex: /dev/md0 is an array with /dev/sda1, /dev/sdb1,
# so we would return /dev/sda1 as slave 0
#
# This procedure is used to determine the grub value for root, ex: (hd0,0)
mdraid_slave0 ()
{
    echo "/dev/"$(ls -ldgGQ /sys/class/block/$(basename $1)/md/rd0 | cut -d'"' -f4 | cut -d'-' -f2)
}

# $1 md raid blockdevice (ex: /dev/md0)
# return a list of array members from given md array
# ex: /dev/md0 has slaves: "/dev/sda1 /dev/sdb2 /dev/sdc2"
mdraid_all-slaves ()
{
    local slave=
    local slaves=
    for slave in $(ls /sys/class/block/$(basename $1)/slaves/); do
        slaves=$slaves"/dev/"$slave" "
    done
    echo $slaves
}
