#!/bin/sh

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
