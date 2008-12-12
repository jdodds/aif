#!/bin/sh


# FORMAT DEFINITIONS:

# MAIN FORMAT FOR $TMP_BLOCKDEVICES (format used to interface with this library): one line per blockdevice, multiple fs'es in 1 'fs-string'
# $TMP_BLOCKDEVICES entry.
# <blockdevice> type label/no_label <FS-string>/no_fs
# FS-string:
# type;recreate(yes/no);mountpoint;mount?(target,runtime,no);opts;label;params[|FS-string|...] where opts/params have _'s instead of whitespace if needed
# NOTE: the 'mount?' for now just matters for the location (if 'target', the target path gets prepended and mounted in the runtime system)


# ADDITIONAL INTERNAL FORMAT FOR $TMP_FILESYSTEMS: each filesystem on a separate line, so block devices can appear multiple times be on multiple lines (eg LVM volumegroups with more lvm LV's)
# part part_type part_label fs_type fs_create fs_mountpoint fs_mount fs_opts fs_label fs_params



#TODO: this should be fixed on the installcd.
modprobe dm-crypt || show_warning modprobe 'Could not modprobe dm-crypt. no support for disk encryption'
modprobe aes-i586 || show_warning modprobe 'Could not modprobe aes-i586. no support for disk encryption'



TMP_DEV_MAP=/home/arch/aif/runtime/dev.map
TMP_FSTAB=/home/arch/aif/runtime/.fstab
TMP_PARTITIONS=/home/arch/aif/runtime/.partitions
TMP_FILESYSTEMS=/home/arch/aif/runtime/.filesystems # Only used internally by this library.  Do not even think about using this as interface to this library.  it won't work
TMP_BLOCKDEVICES=/home/arch/aif/runtime/.blockdata



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
	debug "Partition calls: sfdisk $DEVICE -uM >$LOG 2>&1 <<< $sfdisk_input"
	printk off
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


# file layout:
#TMP_PARTITIONS
# disk partition-scheme

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


generate_filesystem_list ()
{
	echo -n > $TMP_FILESYSTEMS
	while read part part_type part_label fs_string
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
	done < $TMP_BLOCKDEVICES

}


# process all entries in $TMP_BLOCKDEVICES, create all blockdevices and filesystems and mount them correctly, destroying what's necessary first.
process_filesystems ()
{
	debug "process_filesystems Called.  checking all entries in $TMP_BLOCKDEVICES"
	rm -f $TMP_FSTAB
	generate_filesystem_list

	# phase 1: destruct all mounts in the vfs that are about to be reconstructed. (and also swapoff where appropriate)
	# re-order list so that we umount in the correct order. eg first umount /a/b/c, then /a/b. we sort alphabetically, which has the side-effect of sorting by stringlength, hence by vfs dependencies.
	# TODO: this is not entirely correct: what if something is mounted in a previous run that is now not anymore in $TMP_BLOCKDEVICES ? that needs to be cleaned up too.

	sort -t \  -k 6 $TMP_FILESYSTEMS | tac | while read part part_type part_label fs_type fs_create fs_mountpoint fs_mount fs_opts fs_label fs_params
	do
		if [ "$fs_type" = swap ]
		then
			infofy "(Maybe) Swapoffing $part" disks
			swapoff $part &>/dev/null # could be that it was not swappedon yet.  that's not a problem at all.
		elif [ "$fs_mountpoint" != no_mount ]
		then
			part_real=${part/+/}
			infofy "(Maybe) Umounting $part_real" disks
			if mount | grep -q "^$part_real " # could be that this was not mounted yet. no problem, we can just skip it then.  NOTE: umount part, not mountpoint. some other part could be mounted in this place, we don't want to affect that.
			then
				umount $part_real >$LOG || show_warning "Umount failure" "Could not umount umount $part_real .  Probably device is still busy.  See $LOG" #TODO: fix device busy things
			fi
		fi
	done

#	devs_avail=1
#	while [ $devs_avail = 1 ]
#	do
#		devs_avail=0
#		for part in `findpartitions`
#		do
#			if entry=`grep ^$part $TMP_BLOCKDEVICES`
#			then
#				process_filesystem "$entry" && sed -i "/^$part/d" $TMP_BLOCKDEVICES && debug "$part processed and removed from $TMP_BLOCKDEVICES"
#				devs_avail=1
#			fi
#		done
#	done
#	entries=`wc -l $TMP_BLOCKDEVICES`
#	if [ $entries -gt 0 ]
#	then
#		die_error "Could not process all entries because not all available blockdevices became available.  Unprocessed:`awk '{print \$1}' $TMP_BLOCKDEVICES`"
#	else
#		debug "All entries processed..."
#	fi


	# phase 2: destruct blockdevices if they would exist already (destroy any lvm things, dm_crypt devices etc in the correct order)
	# in theory devices with same names could be stacked on each other with different dependencies.  I hope that's not the case for now.  In the future maybe we should destruct things we need and who are in /etc/mtab or something.
	# targets for destruction: /dev/mapper devices and lvm PV's who contain no fs, or a non-lvm/dm_crypt fs. TODO: improve regexes
	# after destructing. the parent must be updated to reflect the vanished child.

	# NOTE: an alternative approach could be to just go over all /dev/mapper devices or normal devices that are lvm PV's (by using finddisks etc instead of $TMP_BLOCKDEVICES, or even better by using finddisks and only doing it if they are in $TMP_BLOCKDEVICES  ) and attempt to destruct.
	#  do that a few times and the ones that blocked because something else on it will probable have become freed and possible to destruct

	# TODO: do this as long as devices in this list remains and exist physically
	# TODO: abort when there still are physical devices listed, but we tried to destruct them already, give error

	egrep '\+|mapper' $TMP_BLOCKDEVICES | egrep -v ' lvm-pv;| lvm-vg;| lvm-lv;| dm_crypt;' | while read part part_type part_label fs
	do
		real_part=${part/+/}
		if [ -b "$real_part" ]
		then
			infofy "Attempting destruction of device $part (type $part_type)" disks
			[ "$part_type" = lvm-pv   ] && ( pvremove             $part || show_warning "process_filesystems blockdevice destruction" "Could not pvremove $part")
			[ "$part_type" = lvm-vg   ] && ( vgremove -f          $part || show_warning "process_filesystems blockdevice destruction" "Could not vgremove -f $part")
			[ "$part_type" = lvm-lv   ] && ( lvremove -f          $part || show_warning "process_filesystems blockdevice destruction" "Could not lvremove -f $part")
			[ "$part_type" = dm_crypt ] && ( cryptsetup luksClose $part || show_warning "process_filesystems blockdevice destruction" "Could not cryptsetup luksClose $part")
		else
			debug "Skipping destruction of device $part (type $part_type) because it doesn't exist"
		fi
	done


	# TODO: phase 3: create all blockdevices and filesystems in the correct order (for each fs, the underlying block/lvm/devicemapper device must be available so dependencies must be resolved. for lvm:first pv's, then vg's, then lv's etc)

	while read part part_type part_label fs_type fs_create fs_mountpoint fs_mount fs_opts fs_label fs_params
	do
		if [ -b "$part" -a "$fs_create" = yes ]
		then
			infofy "Making $fs_type filesystem on $part" disks
			# don't ask to mount. we take care of all that ourselves in the next phase
			process_filesystem $part $fs_type $fs_create $fs_mountpoint no_mount $fs_opts $fs_label $fs_params
		fi
	done < $TMP_FILESYSTEMS


	# phase 4: mount all filesystems in the vfs in the correct order. (also swapon where appropriate)
	sort -t \  -k 6 $TMP_FILESYSTEMS | while read part part_type part_label fs_type fs_create fs_mountpoint fs_mount fs_opts fs_label fs_params
	do
		if [ "$fs_mountpoint" != no_mountpoint ]
		then
			infofy "Mounting $part" disks
			process_filesystem $part $fs_type no $fs_mountpoint $fs_mount $fs_opts $fs_label $fs_params
		elif [ "$fs_type" = swap ]
		then
			infofy "Swaponning $part" disks
			process_filesystem $part $fs_type no $fs_mountpoint $fs_mount $fs_opts $fs_label $fs_params
		fi
	done

	infofy "Done processing filesystems/blockdevices" disks 1
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
	[ -z "$1" -o ! -b "$1" ] && die_error "process_filesystem needs a partition as \$1"
	[ -z "$2" ]              && die_error "process_filesystem needs a filesystem type as \$2"
	debug "process_filesystem $@"
        part=$1
        fs_type=$2
	fs_create=${3:-yes}
	fs_mountpoint=${4:-no_mountpoint}
	fs_mount=${5:-no_mount}
	fs_opts=${6:-no_opts}
	fs_label=${7:-no_label}
	fs_params=${8:-no_params}

	# Create the FS
	if [ "$fs_create" = yes ]
	then
		if ! program=`get_filesystem_program $fs_type`
		then
			show_warning "process_filesystem error" "Cannot determine filesystem program for $fs_type on $part.  Not creating this FS"
			return 1
		fi
		[ "$fs_label" = no_label ] && [ "$fs_type" = lvm-vg -o "$fs_type" = lvm-pv ] && fs_label=default #TODO. implement the incrementing numbers label for lvm vg's and lv's

		ret=0
		#TODO: health checks on $fs_params etc
		case ${fs_type} in #TODO: implement label, opts etc decently
			xfs)      mkfs.xfs -f $part           $opts >$LOG 2>&1; ret=$? ;;
			jfs)      yes | mkfs.jfs $part        $opts >$LOG 2>&1; ret=$? ;;
			reiserfs) yes | mkreiserfs $part      $opts >$LOG 2>&1; ret=$? ;;
			ext2)     mke2fs "$part"              $opts >$LOG 2>&1; ret=$? ;;
			ext3)     mke2fs -j $part             $opts >$LOG 2>&1; ret=$? ;;
			vfat)     mkfs.vfat $part             $opts >$LOG 2>&1; ret=$? ;;
			swap)     mkswap $part                $opts >$LOG 2>&1; ret=$? ;;
			dm_crypt) [ -z "$fs_params" ] && fs_params='-c aes-xts-plain -y -s 512';
			          fs_params=${fs_params//_/ }
			          cryptsetup $fs_params $opts luksFormat -q $part >$LOG 2>&1 < /dev/tty ; ret=$? #hack to give cryptsetup the approriate stdin. keep in mind we're in a loop (see process_filesystems where something else is on stdin)
			          cryptsetup       luksOpen $part $fs_label >$LOG 2>&1 < /dev/tty; ret=$? || ( show_warning 'cryptsetup' "Error luksOpening $part on /dev/mapper/$fs_label" ) ;;
			lvm-pv)   pvcreate $opts $part              >$LOG 2>&1; ret=$? ;;
			lvm-vg)   # $fs_params: ':'-separated list of PV's
			          vgcreate $opts $_label ${fs_params//:/ }      >$LOG 2>&1; ret=$? ;;
			lvm-lv)   # $fs_params = size string (eg '5G')
			          lvcreate -L $fs_params $fs_opts -n $_label $part   >$LOG 2>&1; ret=$? ;; #$opts is usually something like -L 10G
			# don't handle anything else here, we will error later
		esac
		[ "$ret" -gt 0 ] && ( show_warning "process_filesystem error" "Error creating filesystem $fs_type on $part." ; return 1 )
		sleep 2
	fi

	# Mount it, if requested.  Note that it's your responsability to figure out if you want this or not before calling me.  This will only work for 'raw' filesystems (ext,reiser,xfs, swap etc. not lvm stuff,dm_crypt etc)
	if [ "$fs_mount" = runtime -o "$fs_mount" = target ]
	then
		if [ "$fs_type" = swap ]
		then
			debug "swaponning $part"
			swapon $part >$LOG 2>&1 || ( show_warning 'Swapon' "Error activating swap: swapon $part"  ;  return 1 )
		else
			[ "$fs_mount" = runtime ] && dst=$fs_mountpoint
			[ "$fs_mount" = target  ] && dst=$var_TARGET_DIR$fs_mountpoint
			debug "mounting $part on $dst"
			mkdir -p $dst &>/dev/null # directories may or may not already exist
			mount -t $fs_type $part $dst >$LOG 2>&1 || ( show_warning 'Mount' "Error mounting $part on $dst"  ;  return 1 )
			if [ "$fs_mount" = target -a $fs_mountpoint = '/' ]
			then
				PART_ROOT=$part
			fi
		fi
	fi


	# Add to temp fstab, if not already there.
	if [ $fs_mountpoint != no_mountpoint -a $fs_mount = target ]
	then
		local _uuid="$(getuuid $part)"
		if [ -n "${_uuid}" ]; then
			_device="UUID=${_uuid}"
		fi
		if ! grep -q "$part $fs_mountpoint $fs_type defaults 0 " $TMP_FSTAB 2>/dev/null #$TMP_FSTAB may not exist yet
		then
			echo -n "$part $fs_mountpoint $fs_type defaults 0 " >> $TMP_FSTAB
			if [ "$FSTYPE" = "swap" ]; then
				echo "0" >>$TMP_FSTAB
			else
				echo "1" >>$TMP_FSTAB
			fi
		fi
	fi

	return 0

#TODO: if target has LVM volumes, copy /etc/lvm/backup to /etc on target (or maybe it can be regenerated with a command, i should look that up)

}


# $1 filesystem type
get_filesystem_program ()
{
	[ -z "$1" ] && die_error "get_filesystem_program needs a filesystem id as \$1"
	[ $1 = swap     ] && echo mkswap     && return 0
	[ $1 = ext2     ] && echo mkfs.ext2  && return 0
	[ $1 = ext3     ] && echo mkfs.ext3  && return 0
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
# $2 standard SI for 1000*n, IEC for 1024*n (optional. defaults to SI)
# --> Note that if you do SI on a partition, you get the size of the entire disk, so for now you need IEC for single partitions
# output will be in $BLOCKDEVICE_SIZE in MB/MiB
get_blockdevice_size ()
{
	[ -b "$1" ] || die_error "get_blockdevice_size needs a blockdevice as \$1 ($1 given)"
	standard=${2:-SI}

	if [ "$standard" = SI ]
	then
		BLOCKDEVICE_SIZE=$(hdparm -I $1 | grep -F '1000*1000' | sed "s/^.*:[ \t]*\([0-9]*\) MBytes.*$/\1/")
	elif [ "$standard" = IEC ]
	then
		blocks=`fdisk -s $1` || show_warning "Fdisk problem" "Something failed when trying to do fdisk -s $1"
		#NOTE: on some interwebs they say 1 block = 512B, on other internets they say 1 block = 1kiB.  1kiB seems to work for me.  don't sue me if it doesn't for you
		BLOCKDEVICE_SIZE=$(($blocks/1024))
	fi
}
