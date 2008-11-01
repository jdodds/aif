#!/bin/sh

# procedural code from quickinst functionized and fixed.
# there were functions like this in the setup script too, with some subtle differences.  see below
# NOTE: why were the functions in the setup called CHROOT_mount/umount? this is not chrooting ?
target_special_fs ()
{
	[ "$1" = on -o "$1" = off ] || die_error "special_fs needs on/off argument"
	if [ "$1" = on ]
	then
		# mount proc/sysfs first, so mkinitrd can use auto-detection if it wants
		! [ -d $var_TARGET_DIR/proc ] && mkdir $var_TARGET_DIR/proc
		! [ -d $var_TARGET_DIR/sys ] && mkdir $var_TARGET_DIR/sys
		! [ -d $var_TARGET_DIR/dev ] && mkdir $var_TARGET_DIR/dev
		#mount, if not mounted yet
		mount | grep -q "$var_TARGET_DIR/proc" || mount -t proc none $var_TARGET_DIR/proc || die_error "Could not mount $var_TARGET_DIR/proc" #NOTE:  setup script uses mount -t proc proc ? what's best?
		mount | grep -q "$var_TARGET_DIR/sys"  || mount -t sysfs none $var_TARGET_DIR/sys || die_error "Could not mount $var_TARGET_DIR/sys" # NOTE: setup script uses mount -t sysfs sysfs ? what's best?
		mount | grep -q "$var_TARGET_DIR/dev"  || mount -o bind /dev $var_TARGET_DIR/dev  || die_error "Could not mount $var_TARGET_DIR/dev"
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
	notify "Disabling swapspace, unmounting already mounted disk devices..."
	swapoff -a >/dev/null 2>&1
	umount $(mount | grep -v "${var_TARGET_DIR} " | grep "${var_TARGET_DIR}" | sed 's|\ .*||g') >/dev/null 2>&1
	umount $(mount | grep "${var_TARGET_DIR} " | sed 's|\ .*||g') >/dev/null 2>&1
}


# literally taken from setup script
finddisks() {
    workdir="$PWD"
    cd /sys/block 
    # ide devices 
    for dev in $(ls | egrep '^hd'); do
        if [ "$(cat $dev/device/media)" = "disk" ]; then
            echo "/dev/$dev"
            [ "$1" ] && echo $1
        fi
    done  
    #scsi/sata devices
    for dev in $(ls | egrep '^sd'); do
        # TODO: what is the significance of 5?
        if ! [ "$(cat $dev/device/type)" = "5" ]; then
            echo "/dev/$dev"
            [ "$1" ] && echo $1
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

# taken from setup. slightly optimized. TODO: fix identation + can be improved more
findpartitions() {
	workdir="$PWD"
	for devpath in $(finddisks)
	do
		disk=$(echo $devpath | sed 's|.*/||')
		cd /sys/block/$disk   
		for part in $disk*
		do
			# check if not already assembled to a raid device
			if ! [ "$(cat /proc/mdstat 2>/dev/null | grep $part)" -o "$(fstype 2>/dev/null </dev/$part | grep "lvm2")" \ 
			    -o "$(sfdisk -c /dev/$disk $(echo $part | sed -e "s#$disk##g") 2>/dev/null | grep "5")" ]
			then
				if [ -d $part ]
				then  
					echo "/dev/$part"  
					[ "$1" ] && echo $1
				fi
			fi
		done
	done
	# include any mapped devices
	for devpath in $(ls /dev/mapper 2>/dev/null | grep -v control)
	do
		echo "/dev/mapper/$devpath"
		[ "$1" ] && echo $1
	done
	# include any raid md devices
	for devpath in $(ls -d /dev/md* | grep '[0-9]' 2>/dev/null)
	do
		if grep -qw $(echo $devpath /proc/mdstat | sed -e 's|/dev/||g')
		then
			echo "$devpath"
			[ "$1" ] && echo $1
		fi
	done
	# inlcude cciss controllers
	if [ -d /dev/cciss ]
	then
		cd /dev/cciss
		for dev in $(ls | egrep 'p')
		do
			echo "/dev/cciss/$dev"
			[ "$1" ] && echo $1
		done
	fi
	# inlcude Smart 2 controllers
	if [ -d /dev/ida ]
	then
		cd /dev/ida
		for dev in $(ls | egrep 'p')
		do
			echo "/dev/ida/$dev"
			[ "$1" ] && echo $1
		done
	fi
	
	cd "$workdir"
}


# taken from setup
get_grub_map() {
	rm /tmp/dev.map
	$var_TARGET_DIR/sbin/grub --no-floppy --device-map /tmp/dev.map >/tmp/grub.log 2>&1 <<EOF
quit
EOF
}


# TODO: $1 is what??
# taken from setup. slightly edited.
mapdev() {
    partition_flag=0
    device_found=0
    devs=$( grep -v fd /tmp/dev.map | sed 's/ *\t/ /' | sed ':a;$!N;$!ba;s/\n/ /g')
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
    fi
}

# _mkfs() taken from setup code and slightly improved.
# Create and mount filesystems in our destination system directory.
#
# args:
#  $1 domk: Whether to make the filesystem or use what is already there  (yes/no)
#  $2 device: Device filesystem is on
#  $3 fstype: type of filesystem located at the device (or what to create)
#  $4 dest: Mounting location for the destination system
#  $5 mountpoint: Mount point inside the destination system, e.g. '/boot'

# returns: 1 on failure
_mkfs() {
    local _domk=$1
    local _device=$2
    local _fstype=$3
    local _dest=$4
    local _mountpoint=$5

    # we have two main cases: "swap" and everything else.
    if [ "${_fstype}" = "swap" ]; then
        swapoff ${_device} >/dev/null 2>&1
        if [ "${_domk}" = "yes" ]; then
            mkswap ${_device} >$LOG 2>&1 || show_warning "Error creating swap: mkswap ${_device}" && return 1
        fi
        swapon ${_device} >$LOG 2>&1 || show_warning "Error activating swap: swapon ${_device}"  &&  return 1
    else
        # make sure the fstype is one we can handle
        local knownfs=0
        for fs in xfs jfs reiserfs ext2 ext3 vfat; do
            [ "${_fstype}" = "${fs}" ] && knownfs=1 && break
        done
        
        [ $knownfs -eq 0 ] && show_warning "unknown fstype ${_fstype} for ${_device}"  && return 1
        # if we were tasked to create the filesystem, do so
        if [ "${_domk}" = "yes" ]; then
            local ret
            case ${_fstype} in
                xfs)      mkfs.xfs -f ${_device} >$LOG 2>&1; ret=$? ;;
                jfs)      yes | mkfs.jfs ${_device} >$LOG 2>&1; ret=$? ;;
                reiserfs) yes | mkreiserfs ${_device} >$LOG 2>&1; ret=$? ;;
                ext2)     mke2fs "${_device}" >$LOG 2>&1; ret=$? ;;
                ext3)     mke2fs -j ${_device} >$LOG 2>&1; ret=$? ;;
                vfat)     mkfs.vfat ${_device} >$LOG 2>&1; ret=$? ;;
                # don't handle anything else here, we will error later
            esac
            [ $ret != 0 ] && show_warning "Error creating filesystem ${_fstype} on ${_device}" && return 1
            sleep 2
        fi
        # create our mount directory
        mkdir -p ${_dest}${_mountpoint}
        # mount the bad boy
        mount -t ${_fstype} ${_device} ${_dest}${_mountpoint} >$LOG 2>&1
	[ $? != 0 ] && show_warning "Error mounting ${_dest}${_mountpoint}" && return 1
    fi

    # add to temp fstab
    local _uuid="$(getuuid ${_device})"
    if [ -n "${_uuid}" ]; then
        _device="UUID=${_uuid}"
    fi
    echo -n "${_device} ${_mountpoint} ${_fstype} defaults 0 " >>/tmp/.fstab

    if [ "${_fstype}" = "swap" ]; then
        echo "0" >>/tmp/.fstab
    else
        echo "1" >>/tmp/.fstab
    fi
}


# auto_fstab(). taken from setup
# preprocess fstab file
# comments out old fields and inserts new ones
# according to partitioning/formatting stage
#
auto_fstab()
{
    if [ "$S_MKFS" = "1" -o "$S_MKFSAUTO" = "1" ]; then
        if [ -f /tmp/.fstab ]; then
            # comment out stray /dev entries
            sed -i 's/^\/dev/#\/dev/g' $var_TARGET_DIR/etc/fstab
            # append entries from new configuration
            sort /tmp/.fstab >>$var_TARGET_DIR/etc/fstab
        fi
    fi
}
