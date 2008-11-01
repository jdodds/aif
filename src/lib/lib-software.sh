#!/bin/sh


# run_mkinitcpio() taken from setup. adapted a bit.
# runs mkinitcpio on the target system, displays output
run_mkinitcpio()  
{
	target_special_fs on

	run_background mkinitcpio "chroot $TARGET_DIR /sbin/mkinitcpio -p kernel26" /tmp/mkinitcpio.log
	follow_progress "Rebuilding initcpio images ..." /tmp/mkinitcpio.log
	wait_for mkinitcpio

	target_special_fs off

	# alert the user to fatal errors
	[ $(cat /tmp/.mkinitcpio-retcode) -ne 0 ] && show_warning "MKINITCPIO FAILED - SYSTEM MAY NOT BOOT" "/tmp/mkinitcpio.log" text
}
