#!/bin/sh


# run_mkinitcpio() taken from setup. adapted a lot
# runs mkinitcpio on the target system, displays output
run_mkinitcpio()  
{
	target_special_fs on

	run_background mkinitcpio "chroot $var_TARGET_DIR /sbin/mkinitcpio -p kernel26" /tmp/mkinitcpio.log
	follow_progress "Rebuilding initcpio images ..." /tmp/mkinitcpio.log
	wait_for mkinitcpio

	target_special_fs off

	# alert the user to fatal errors
	[ $(cat /tmp/.mkinitcpio-retcode) -ne 0 ] && show_warning "MKINITCPIO FAILED - SYSTEM MAY NOT BOOT" "/tmp/mkinitcpio.log" text
}


# installpkg(). taken from setup. modified bigtime
# performs package installation to the target system
installpkg() {
	notify "Package installation will begin now.  You can watch the output in the progress window. Please be patient."
	target_specialfs on
	run_background pacman-installpkg "$PACMAN_TARGET -S $PACKAGES" /tmp/pacman.log
	follow_progress " Installing... Please Wait " /tmp/pacman.log

	wait_for pacman-installpkg
        
	local _result=''
	if [ $(cat /tmp/.pacman-retcode) -ne 0 ]; then
		_result="Installation Failed (see errors below)"
		echo -e "\nPackage Installation FAILED." >>/tmp/pacman.log
	else
		_result="Installation Complete"
		echo -e "\nPackage Installation Complete." >>/tmp/pacman.log
	fi
	rm /tmp/.pacman-retcode

	show_warning "$_result" "/tmp/pacman.log" text || return 1     

	target_specialfs off

	sync

	return 0
}


# auto_locale(). taken from setup
# enable glibc locales from rc.conf and build initial locale DB
target_configure_inital_locale() 
{
    for i in $(grep "^LOCALE" ${var_TARGET_DIR}/etc/rc.conf | sed -e 's/.*="//g' -e's/\..*//g'); do
        sed -i -e "s/^#$i/$i/g" ${var_TARGET_DIR}/etc/locale.gen
    done
    target_locale-gen
}


target_locale-gen ()
{
	notify "Generating glibc base locales..."
	chroot ${var_TARGET_DIR} locale-gen >/dev/null
}