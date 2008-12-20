#!/bin/bash

TMP_MKINITCPIO_LOG=$RUNTIME_DIR/mkinitcpio.log
TMP_PACMAN_LOG=$RUNTIME_DIR/pacman.log

# run_mkinitcpio() taken from setup. adapted a lot
# runs mkinitcpio on the target system, displays output
run_mkinitcpio()  
{
	target_special_fs on

	run_background mkinitcpio "chroot $var_TARGET_DIR /sbin/mkinitcpio -p kernel26" $TMP_MKINITCPIO_LOG
	follow_progress "Rebuilding initcpio images ..." $TMP_MKINITCPIO_LOG
	wait_for mkinitcpio

	target_special_fs off

	# alert the user to fatal errors
	[ $mkinitcpio_exitcode -ne 0 ] && show_warning "MKINITCPIO FAILED - SYSTEM MAY NOT BOOT" "$TMP_MKINITCPIO_LOG" text
	return $mkinitcpio_exitcode
}


# installpkg(). taken from setup. modified bigtime
# performs package installation to the target system
installpkg() {
	notify "Package installation will begin now.  You can watch the output in the progress window. Please be patient."
	target_special_fs on
	run_background pacman-installpkg "$PACMAN_TARGET -S $TARGET_PACKAGES" $TMP_PACMAN_LOG #TODO: There may be something wrong here. See http://projects.archlinux.org/?p=installer.git;a=commitdiff;h=f504e9ecfb9ecf1952bd8dcce7efe941e74db946 ASKDEV (Simo)
	follow_progress " Installing... Please Wait " $TMP_PACMAN_LOG

	wait_for pacman-installpkg
        

	local _result=''
	if [ ${pacman-installpkg_exitcode} -ne 0 ]; then
		_result="Installation Failed (see errors below)"
		echo -e "\nPackage Installation FAILED." >>$TMP_PACMAN_LOG
	else
		_result="Installation Complete"
		echo -e "\nPackage Installation Complete." >>$TMP_PACMAN_LOG
	fi

	show_warning "$_result" "$TMP_PACMAN_LOG" text || return 1

	target_special_fs off
	sync

	#return ${pacman-installpkg_exitcode} TODO: fix this. there is something wrong here
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
	infofy "Generating glibc base locales..."
	chroot ${var_TARGET_DIR} locale-gen >/dev/null
}