#!/bin/sh

set_clock()
{
	if [ -e /usr/bin/tz ]; then 
		tz
	else
		DIALOG --msgbox "Error:\ntz script not found, aborting clock setting" 0 0
	fi
}

set_keyboard()
{
	if [ -e /usr/bin/km ]; then 
		km
	else
		DIALOG --msgbox "Error:\nkm script not found, aborting keyboard and console setting" 0 0
	fi
}

configure_system()
{
	HWDETECT=""
	HWPARAMETER=""
	DSDT_ENABLE=""
	DIALOG --yesno "PRECONFIGURATION?\n-----------------\n\nDo you want to use 'hwdetect' for:\n'/etc/rc.conf' and '/etc/mkinitcpio.conf'?\n\nThis ensures consistent ordering of your hard disk controllers,\nnetwork and sound devices.\n\nIt is recommended to say 'YES' here." 18 70 && HWDETECT="yes"
	if [ "$HWDETECT" = "yes" ]; then
		if /usr/bin/vmware-detect; then 
			HWPARAMETER="$HWPARAMETER --vmware"
		fi
		grep -qw ide-legacy /proc/cmdline && HWPARAMETER="$HWPARAMETER --ide-legacy"
		DIALOG --defaultno --yesno "Do you need support for booting from usb devices?" 0 0 && HWPARAMETER="$HWPARAMETER --usb"
		DIALOG --defaultno --yesno "Do you need support for booting from firewire devices?" 0 0 && HWPARAMETER="$HWPARAMETER --fw"
		DIALOG --defaultno --yesno "Do you need support for booting from pcmcia devices?" 0 0 && HWPARAMETER="$HWPARAMETER --pcmcia"
		DIALOG --defaultno --yesno "Do you need support for booting from nfs shares?" 0 0 && HWPARAMETER="$HWPARAMETER --nfs"
		DIALOG --defaultno --yesno "Do you need support for booting from software raid arrays?" 0 0 && HWPARAMETER="$HWPARAMETER --raid"
		if [ -e $DESTDIR/lib/initcpio/hooks/raid-partitions ]; then
			DIALOG --defaultno --yesno "Do you need support for booting from software raid mdp/partition arrays?" 0 0 && HWPARAMETER="$HWPARAMETER --raid-partitions"
		fi
		if [ -e $DESTDIR/lib/initcpio/hooks/dmraid ]; then
			DIALOG --defaultno --yesno "Do you need support for booting from hardware dmraid arrays?" 0 0 && HWPARAMETER="$HWPARAMETER --dmraid"
		fi
		DIALOG --defaultno --yesno "Do you need support for booting from lvm2 volumes?" 0 0 && HWPARAMETER="$HWPARAMETER --lvm2"
		DIALOG --defaultno --yesno "Do you need support for booting from encrypted volumes?" 0 0 && HWPARAMETER="$HWPARAMETER --encrypt"
		DIALOG --defaultno --yesno "Do you need support for booting the kernel with a custom DSDT file?" 0 0 && DSDT_ENABLE=1
		if [ "$DSDT_ENABLE" = "1" ]; then
			while [ "$DSDT" = "" ]; do
				DIALOG --inputbox "Enter the custom DSDT file (with full path)" 8 65 "" 2>$ANSWER || return 1
				DSDT=$(cat $ANSWER)
				if [ -s "$DSDT" ]; then
					cp $DSDT $DESTDIR/lib/initcpio/custom.dsdt
					HWPARAMETER="$HWPARAMETER --dsdt"
				else
					DIALOG --msgbox "ERROR: You have entered a wrong file name, please enter again." 0 0
					DSDT=""
				fi
			done
		fi
		# add always keymap
		HWPARAMETER="$HWPARAMETER --keymap"
		HWDETECTHOSTCONTROLLER=""
		HWDETECTHOOKS=""
		HWDETECTRC=""
		HWDETECTHOSTCONTROLLER="$(hwdetect --hostcontroller $HWPARAMETER)"
		HWDETECTHOOKS="$(hwdetect --hooks-dir=$DESTDIR/lib/initcpio/install --hooks $HWPARAMETER)"
		HWDETECTRC="$(echo $(hwdetect --net --sound $HWPARAMETER)| sed -e 's#.*) ##g')"
		[ -n "$HWDETECTHOSTCONTROLLER" ] && sed -i -e "s/^MODULES=.*/$HWDETECTHOSTCONTROLLER/g" ${DESTDIR}/etc/mkinitcpio.conf
		[ -n "$HWDETECTHOOKS" ] && sed -i -e "s/^HOOKS=.*/$HWDETECTHOOKS/g" ${DESTDIR}/etc/mkinitcpio.conf
		[ -n "$HWDETECTRC" ] && sed -i -e "s/^MODULES=.*/$HWDETECTRC/g" ${DESTDIR}/etc/rc.conf
	fi
	if [ -s /tmp/.keymap ]; then
		DIALOG --yesno "Do you want to use the keymap: $(cat /tmp/.keymap | sed -e 's/\..*//g') in rc.conf?" 0 0 && sed -i -e "s/^KEYMAP=.*/KEYMAP=\"$(cat /tmp/.keymap | sed -e 's/\..*//g')\"/g" ${DESTDIR}/etc/rc.conf
	fi
	if [ -s /tmp/.font ]; then
		DIALOG --yesno "Do you want to use the consolefont: $(cat /tmp/.font | sed -e 's/\..*//g') in rc.conf?" 0 0 && sed -i -e "s/^CONSOLEFONT=.*/CONSOLEFONT=\"$(cat /tmp/.font | sed -e 's/\..*//g')\"/g" ${DESTDIR}/etc/rc.conf
	fi
	if [ -s  /tmp/.hardwareclock ]; then
		DIALOG --yesno "Do you want to use the hardwareclock: $(cat /tmp/.hardwareclock | sed -e 's/\..*//g') in rc.conf?" 0 0 && sed -i -e "s/^HARDWARECLOCK=.*/HARDWARECLOCK=\"$(cat /tmp/.hardwareclock | sed -e 's/\..*//g')\"/g" ${DESTDIR}/etc/rc.conf
	fi
	if [ -s  /tmp/.timezone ]; then
		DIALOG --yesno "Do you want to use the timezone: $(cat /tmp/.timezone | sed -e 's/\..*//g') in rc.conf?" 0 0 && sed -i -e "s#^TIMEZONE=.*#TIMEZONE=\"$(cat /tmp/.timezone | sed -e 's/\..*//g')\"#g" ${DESTDIR}/etc/rc.conf
	fi
	if [ "$S_NET" = "1" ]; then
		DIALOG --yesno "Do you want to use the previous network settings in rc.conf and resolv.conf?\nIf you used Proxy settings, they will be written to /etc/profile.d/proxy.sh" 0 0 && (
		if [ "$S_DHCP" != "1" ]; then 
			sed -i -e "s#eth0=\"eth0#$INTERFACE=\"$INTERFACE#g" ${DESTDIR}/etc/rc.conf
			sed -i -e "s# 192.168.0.2 # $IPADDR #g" ${DESTDIR}/etc/rc.conf
			sed -i -e "s# 255.255.255.0 # $SUBNET #g" ${DESTDIR}/etc/rc.conf
			sed -i -e "s# 192.168.0.255\"# $BROADCAST\"#g" ${DESTDIR}/etc/rc.conf
			sed -i -e "s#eth0)#$INTERFACE)#g" ${DESTDIR}/etc/rc.conf 
				if [ "$GW" != "" ]; then 
					sed -i -e "s#gw 192.168.0.1#gw $GW#g" ${DESTDIR}/etc/rc.conf 
					sed -i -e "s#!gateway#gateway#g" ${DESTDIR}/etc/rc.conf 
				fi 
			echo "nameserver $DNS" >> ${DESTDIR}/etc/resolv.conf 
		else  
			sed -i -e "s#eth0=\"eth0.*#$INTERFACE=\"dhcp\"#g" ${DESTDIR}/etc/rc.conf
		fi
		if [ "$PROXY_HTTP" != "" ]; then
			echo "export http_proxy=$PROXY_HTTP" >> ${DESTDIR}/etc/profile.d/proxy.sh;
			chmod a+x ${DESTDIR}/etc/profile.d/proxy.sh
		fi
		if [ "$PROXY_FTP" != "" ]; then
			echo "export ftp_proxy=$PROXY_FTP" >> ${DESTDIR}/etc/profile.d/proxy.sh;
			chmod a+x ${DESTDIR}/etc/profile.d/proxy.sh
		fi)
	fi
	[ "$EDITOR" ] || geteditor
	DONE=0
	FILE=""
	while [ "$EDITOR" != "" -a "$DONE" = "0" ]; do
		if [ -n "$FILE" ]; then
			DEFAULT="--default-item $FILE"
		else
			DEFAULT=""
		fi
		dialog $DEFAULT --backtitle "$TITLE" --menu "Configuration" 19 80 16 \
			"/etc/rc.conf" "System Config" \
			"/etc/fstab" "Filesystem Mountpoints" \
			"/etc/mkinitcpio.conf" "Initramfs Config" \
			"/etc/modprobe.conf" "Kernel Modules (for 2.6.x)" \
			"/etc/resolv.conf" "DNS Servers" \
			"/etc/hosts" "Network Hosts" \
			"/etc/hosts.deny" "Denied Network Services" \
			"/etc/hosts.allow" "Allowed Network Services" \
			"/etc/locale.gen" "Glibc Locales" \
			"Root-Password" "Set the root password" \
			"Pacman-Mirror" "Set the primary pacman mirror" \
			"_" "Return to Main Menu" 2>$ANSWER
		FILE=$(cat $ANSWER)

		if [ "$FILE" = "_" -o "$FILE" = "" ]; then
			mount -t proc none $DESTDIR/proc
			mount -t sysfs none $DESTDIR/sys
			mount -o bind /dev $DESTDIR/dev
			# all pacman output goes to /tmp/pacman.log, which we tail into a dialog
			( \
			touch /tmp/setup-mkinitcpio-running
			echo "Initramfs progress ..." > /tmp/initramfs.log; echo >> /tmp/initramfs.log
			chroot $DESTDIR /sbin/mkinitcpio -p kernel26 >>/tmp/initramfs.log 2>&1
			echo >> /tmp/initramfs.log
			rm -f /tmp/setup-mkinitcpio-running 
			) &
			sleep 2 
			dialog --backtitle "$TITLE" --title "Rebuilding initramfs images ..." --no-kill --tailboxbg "/tmp/initramfs.log" 18 70
			while [ -f /tmp/setup-mkinitcpio-running ]; do
				sleep 1
			done
			umount $DESTDIR/proc $DESTDIR/sys $DESTDIR/dev
			DONE=1 
		else
			if [ "$FILE" = "/etc/mkinitcpio.conf" ]; then
				DIALOG --msgbox "The mkinitcpio.conf file controls which modules will be placed into the initramfs for your system's kernel.\n\n- Non US keymap users should add 'keymap' to HOOKS= array\n- USB keyboard users should add 'usbinput' to HOOKS= array\n- If you install under VMWARE add 'BusLogic' to MODULES= array\n- raid, lvm2, encrypt are not enabled by default\n- 2 or more disk controllers, please specify the correct module\n  loading order in MODULES= array \n\nMost of you will not need to change anything in this file." 18 70
				HOOK_ERROR=""
			fi
			if ! [ "$FILE" = "Root-Password" -o "$FILE" = "Pacman-Mirror" ]; then
				if [ "$FILE" = "/etc/locale.gen" ]; then
				# enable glibc locales from rc.conf
					for i in $(grep "^LOCALE" ${DESTDIR}/etc/rc.conf | sed -e 's/.*="//g' -e's/\..*//g'); do
						sed -i -e "s/^#$i/$i/g" ${DESTDIR}/etc/locale.gen
					done
				fi
					$EDITOR ${DESTDIR}${FILE}
			else
				if [ "$FILE" = "Root-Password" ]; then
					ROOTPW=""
					while [ "$ROOTPW" = "" ]; do
						chroot ${DESTDIR} passwd root && ROOTPW=1
					done
				else
					SAMEMIRROR=""
					mirrorlist="${DESTDIR}/etc/pacman.d/mirrorlist"
					if [ "$MODE" = "ftp" -a "${SYNC_SERVER}" != "" ]; then
						DIALOG --yesno "Would you like to use the same MIRROR you used for installation?" 0 0&& SAMEMIRROR="yes"
					fi
					if ! [ "$SAMEMIRROR" = "yes" ]; then
						DIALOG --msgbox "WARNING:\n\n- Please keep in mind ftp.archlinux.org is throttled!\n- Please select another mirror to get full download speed." 18 70
						# this will find all mirrors in the mirrorlist, commented out or not
						PAC_MIRRORS=$(egrep -o '((ftp)|(http))://[^/]*' "${DESTDIR}/etc/pacman.d/mirrorlist" | sed 's|$| _|g')
						DIALOG --menu "Select the primary Pacman mirror" 14 55 7 $PAC_MIRRORS "Custom" "_" 2>$ANSWER || return 1
						PAC_SYNC_SERVER="$(cat $ANSWER)"
						if [ "$PAC_SYNC_SERVER" = "Custom" ]; then
							DIALOG --inputbox "Enter the full URL to packages, for example:\nhttp://server.org/archlinux/\$repo/os/$(uname -m)" 8 65 "http://" 2>$ANSWER || return 1
							PAC_SYNC_SERVER="$(cat $ANSWER)"
						fi
					else
						PAC_SYNC_SERVER="$(echo ${SYNC_URL} | sed 's/core/\$repo/g')"
					fi
					# comment out all existing mirrors
					sed -i -e 's/^Server/#Server/g' "$mirrorlist"
					# add our new entry at the end of the file
					echo "# Setup-configured entry" >> "$mirrorlist"
					echo Server = $(egrep -o "$PAC_SYNC_SERVER.*" "$mirrorlist") >> "$mirrorlist"
				fi
			fi
			if [ "$FILE" = "/etc/locale.gen" ]; then
				chroot ${DESTDIR} locale-gen
			fi
			if [ "$FILE" = "/etc/mkinitcpio.conf" ]; then
				for i in $(cat ${DESTDIR}/etc/mkinitcpio.conf | grep ^HOOKS | sed -e 's/"//g' -e 's/HOOKS=//g'); do 
					[ -e ${DESTDIR}/lib/initcpio/install/$i ] || HOOK_ERROR=1 
				done
				if [ "$HOOK_ERROR" = "1" ]; then
					DIALOG --msgbox "ERROR: Detected error in 'HOOKS=' line, please correct HOOKS= in /etc/mkinitcpio.conf!" 18 70
				fi
			fi
			if [ "$FILE" = "/etc/rc.conf" ]; then
				TIMEZONE=""
				eval $(grep "^TIMEZONE" ${DESTDIR}/etc/rc.conf)
				if [ "$TIMEZONE" != "" -a -e ${DESTDIR}/usr/share/zoneinfo/$TIMEZONE ]; then
					cp ${DESTDIR}/usr/share/zoneinfo/$TIMEZONE ${DESTDIR}/etc/localtime
					cp ${DESTDIR}/usr/share/zoneinfo/$TIMEZONE /etc/localtime
				fi
				if [ ! -f ${DESTDIR}/var/lib/hwclock/adjtime ]; then
						echo "0.0 0 0.0" > ${DESTDIR}/var/lib/hwclock/adjtime
				fi
				eval $(grep "^HARDWARECLOCK" ${DESTDIR}/etc/rc.conf)
				if [ "$HARDWARECLOCK" = "UTC" ]; then
					chroot ${DESTDIR} /sbin/hwclock --directisa --utc --hctosys
				else
					chroot ${DESTDIR} /sbin/hwclock --directisa --localtime --hctosys
				fi
				# ugly hack:
				for line in $(sort --reverse -t: -k3 /tmp/.parts); do
					PART=$(echo $line | cut -d: -f 1)
					FSTYPE=$(echo $line | cut -d: -f 2)
					MP=$(echo $line | cut -d: -f 3)
					if [ "$MP" != "swap" ]; then
						umount ${DESTDIR}${MP}
					fi
				done
				for line in $(sort -t: -k3 /tmp/.parts); do
					PART=$(echo $line | cut -d: -f 1)
					FSTYPE=$(echo $line | cut -d: -f 2)
					MP=$(echo $line | cut -d: -f 3)
					if [ "$MP" != "swap" ]; then
					mount -t ${FSTYPE} ${PART} ${DESTDIR}${MP}
					fi
				done
				# end of hack
			fi
		fi
	done
}

