#! /bin/sh

assure_pacman ()
{
	PACMAN=
	[ -f /tmp/usr/bin/pacman ] && PACMAN=/tmp/usr/bin/pacman
	[ -f /usr/bin/pacman ] && PACMAN=/usr/bin/pacman
	if [ "$PACMAN" = "" ]; then
		cd /tmp
		if [ "$INSTMODE" = "ftp" ]; then
			echo "Downloading pacman..."
			wget $PKGARG/pacman*.pkg.tar.gz
			if [ $? -gt 0 ]; then
				echo "error: Download failed"
				exit 1
			fi
			tar -xzf pacman*.pkg.tar.gz
		elif [ "$INSTMODE" = "cd" ]; then
			echo "Unpacking pacman..."
			tar -xzf $PKGARG/pacman*.pkg.tar.gz
		fi
	fi
	[ -f /tmp/usr/bin/pacman ] && PACMAN=/tmp/usr/bin/pacman
	[ "$PACMAN" = "" ] && return 1

}

write_pacman_conf_ftp ()
{
if [ "$INSTMODE" = "ftp" ]; then
	echo "[core]" >/tmp/pacman.conf
	echo "Server = $PKGARG" >>/tmp/pacman.conf
	mkdir -p $DESTDIR/var/cache/pacman/pkg /var/cache/pacman >/dev/null 2>&1
	rm -f /var/cache/pacman/pkg >/dev/null 2>&1
	ln -sf $DESTDIR/var/cache/pacman/pkg /var/cache/pacman/pkg >/dev/null 2>&1
fi
}


write_pacman_conf_cd ()
{

if [ "$INSTMODE" = "cd" ]; then
	PKGFILE=/tmp/packages.txt
	cp $PKGARG/packages.txt /tmp/packages.txt
	if [ ! -f $PKGFILE ]; then
		echo "error: Could not find package list: $PKGFILE"
		return 1
	fi
	echo "[core]" >/tmp/pacman.conf
	echo "Server = file://$PKGARG" >>/tmp/pacman.conf
	mkdir -p $DESTDIR/var/cache/pacman/pkg /var/cache/pacman >/dev/null 2>&1
	rm -f /var/cache/pacman/pkg >/dev/null 2>&1
	ln -sf $PKGARG /var/cache/pacman/pkg >/dev/null 2>&1
	PKGLIST=
	# fix pacman list!
	sed -i -e 's/-i686//g' -e 's/-x86_64//g' $PKGFILE
	for i in $(cat $PKGFILE | grep 'base/' | cut -d/ -f2); do
	  nm=${i%-*-*}
	  PKGLIST="$PKGLIST $nm"
	done
fi
}

what_is_this_for ()
{
! [ -d $DESTDIR/var/lib/pacman ] && mkdir -p $DESTDIR/var/lib/pacman
! [ -d /var/lib/pacman ] && mkdir -p /var/lib/pacman
# mount proc/sysfs first, so mkinitrd can use auto-detection if it wants
! [ -d $DESTDIR/proc ] && mkdir $DESTDIR/proc
! [ -d $DESTDIR/sys ] && mkdir $DESTDIR/sys
! [ -d $DESTDIR/dev ] && mkdir $DESTDIR/dev
mount -t proc none $DESTDIR/proc
mount -t sysfs none $DESTDIR/sys
mount -o bind /dev $DESTDIR/dev	
if [ "$INSTMODE" = "cd" ]; then
  $PACMAN -r $DESTDIR --config /tmp/pacman.conf -Sy $PKGLIST
fi

if [ "$INSTMODE" = "ftp" ]; then
  $PACMAN -r $DESTDIR --config /tmp/pacman.conf -Sy base
fi

umount $DESTDIR/proc $DESTDIR/sys $DESTDIR/dev
if [ $? -gt 0 ]; then
	echo
	echo "Package installation FAILED."
	echo
	exit 1
fi
}

quickinst_finished ()
{
echo 
echo "Package installation complete."
echo 
echo "Please install a bootloader.  Edit the appropriate config file for"
echo "your loader, and chroot into your system to install it into the"
echo "boot sector:"
echo "  # mount -o bind /dev $DESTDIR/dev"
echo "  # mount -t proc none $DESTDIR/proc"
echo "  # mount -t sysfs none $DESTDIR/sys"
echo "  # chroot $DESTDIR /bin/bash"
echo 
echo "For GRUB:"
echo "  # install-grub /dev/sda /dev/sdaX (replace with your boot partition)"
echo "  (or install manually by invoking the GRUB shell)"
echo "HINT XFS FILESYSTEM:" 
echo "If you have created xfs filesystems, freeze them before and unfreeze them after"
echo "installing grub (outside the chroot):"
echo "- freeze:"
echo "  # xfs_freeze -f $DESTDIR/boot"
echo "  # xfs_freeze -f $DESTDIR/"
echo "- unfreeze:"
echo "  # xfs_freeze -u $DESTDIR/boot"
echo "  # xfs_freeze -u $DESTDIR/"
echo 
echo "For LILO:"
echo "  # lilo"
echo
echo "Next step, initramfs setup:"
echo "Edit your /etc/mkinitcpio.conf and /etc/mkinitcpio.d/kernel26-fallback.conf"
echo "to fit your needs. After that run:" 
echo "# mkinitcpio -p kernel26"
echo 
echo "Then exit your chroot shell, edit $DESTDIR/etc/fstab and"
echo "$DESTDIR/etc/rc.conf, and reboot!"
echo 
}