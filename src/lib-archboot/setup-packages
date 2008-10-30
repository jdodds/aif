#!/bin/sh

getsource() {
	S_SRC=0
	if [ "$MODE" = "cd" ]; then
		DIALOG --menu "You can either install packages from an Arch Linux CD, or you can switch to another VC and manually mount the source media under /src.  If you manually mount to /src, make sure the packages are available under /src/core-$(uname -m)/pkg.\n\n" \
			15 55 2 \
			"CD" "Mount the CD-ROM and install from there" \
			"SRC" "I have manually mounted the source media" 2>$ANSWER || return 1
		case $(cat $ANSWER) in
			"CD")
				select_cdrom
				;;
			"SRC")
				;;
		esac
		if [ ! -d /src/core-$(uname -m)/pkg ]; then
			DIALOG --msgbox "Package directory /src/core-$(uname -m)/pkg is missing!" 0 0
			return 1
		fi
	fi

	if [ "$MODE" = "ftp" ]; then
		select_mirror
	fi
	S_SRC=1
}

# select_mirror()
# Prompt user for preferred mirror and set $SYNC_URL
#
# args: none
# returns: nothing
select_mirror() {
	DIALOG --msgbox "Keep in mind ftp.archlinux.org is throttled.\nPlease select another mirror to get full download speed." 18 70
	# FIXME: this regex doesn't honor commenting
	MIRRORS=$(egrep -o '((ftp)|(http))://[^/]*' "${MIRRORLIST}" | sed 's|$| _|g')
	DIALOG --menu "Select an FTP/HTTP mirror" 14 55 7 \
		$MIRRORS \
		"Custom" "_" 2>$ANSWER || return 1
	local _server=$(cat $ANSWER)
	if [ "${_server}" = "Custom" ]; then
		DIALOG --inputbox "Enter the full URL to core repo." 8 65 \
			"ftp://ftp.archlinux.org/core/os/i686" 2>$ANSWER || return 1
			SYNC_URL=$(cat $ANSWER)
	else
		SYNC_URL=$(egrep -o "${_server}.*" "${MIRRORLIST}" | sed 's/\$repo/core/g')
	fi
}

prepare_pacman() {
	cd /tmp
	if [ "$MODE" = "cd" ]; then
		local serverurl="${FILE_URL}"
	elif [ "$MODE" = "ftp" ]; then
		local serverurl="${SYNC_URL}"
	fi
	# Setup a pacman.conf in /tmp
	cat << EOF > /tmp/pacman.conf
[options]
CacheDir = ${DESTDIR}/var/cache/pacman/pkg
CacheDir = /src/core-$(uname -m)/pkg

[core]
Server = ${serverurl}
EOF

	# Set up the necessary directories for pacman use
	[ ! -d "${DESTDIR}/var/cache/pacman/pkg" ] && mkdir -m 755 -p "${DESTDIR}/var/cache/pacman/pkg"
	[ ! -d "${DESTDIR}/var/lib/pacman" ] && mkdir -m 755 -p "${DESTDIR}/var/lib/pacman"

	DIALOG --infobox "Refreshing package database..." 6 45
	# FIXME: if sync fails. this function needs to fail.
	$PACMAN -Sy >$LOG 2>&1
}

selectpkg() {
	if ! [ "$S_SRC" = "1" ]; then
		DIALOG --msgbox "Error:\nYou must select Source first." 0 0
		return 1
	fi
	# Archboot setup CD Mode uses packages.txt!
	if [ "$MODE" = "cd" ]; then
		DIALOG --msgbox "Package selection is split into two stages.  First you will select package categories that contain packages you may be interested in.  Then you will be presented with a full list of packages in your selected categories, allowing you to fine-tune your selection.\n\nNOTE: It is recommended that you install the BASE category from this setup, SUPPORT contains additional useful packages for networking and filesystems, DEVEL contains software building tools." 18 70
		# set up our install location if necessary and sync up
		# so we can get package lists
		prepare_pacman 
		PKGS="/src/core-$(uname -m)/pkg/packages.txt"
		if ! [ -f /tmp/.pkgcategory ]; then
			CHKLIST="base ^ ON"
			for category in $(cat $PKGS | sed 's|/.*$||g' | uniq | grep -v base | grep -v kernels); do
				CHKLIST="$CHKLIST $category - OFF"
			done
		else
			CHKLIST=
			for i in $(cat /tmp/.pkgcategory | sed 's|\"||g'); do
				CHKLIST="$CHKLIST $i ^ ON"
			done
			for category in $(cat $PKGS | sed 's|/.*$||g' | uniq | grep -v kernels); do
				grep $category /tmp/.pkgcategory > /dev/null 2>&1 || CHKLIST="$CHKLIST $category - OFF"
			done
		fi
		DIALOG --checklist "Select Package Categories" 19 55 12 $CHKLIST 2>/tmp/.pkgcategory || return 1
		SELECTALL="no"
		DIALOG --yesno "Select all packages by default?" 0 0 && SELECTALL="yes"
		CHKLIST=
		for category in $(cat /tmp/.pkgcategory | sed 's|"||g'); do
			if [ "$category" = "x11-drivers" ]; then
				DIALOG --msgbox "NOTE:\n-------\nxf86-video-via and xf86-video-unichrome are disabled by default, please select the correct package you need and don't choose both! Else installation will fail!" 0 0
			fi
			tag="OFF"
			if [ "$SELECTALL" = "yes" ]; then
				tag="ON"
			fi
			list=$(cat $PKGS | grep "$category/" | grep -v 'xf86-video-unichrome' | grep -v 'xf86-video-via' | sed 's|^[a-z0-9-]*/||g' | sed "s|.pkg.tar.gz$| ($category) $tag|g" | sort)
			CHKLIST="$CHKLIST $list"
			tag="OFF"
			list=$(cat $PKGS | grep "$category/" | grep 'xf86-video-unichrome' | sed 's|^[a-z0-9-]*/||g' | sed "s|.pkg.tar.gz$| ($category) $tag|g" | sort)
			CHKLIST="$CHKLIST $list"
			list=$(cat $PKGS | grep "$category/" | grep 'xf86-video-via' | sed 's|^[a-z0-9-]*/||g' | sed "s|.pkg.tar.gz$| ($category) $tag|g" | sort)
			CHKLIST="$CHKLIST $list"
		done
		DIALOG --checklist "Select Packages to install.  Use SPACE to select." 19 60 12 $CHKLIST 2>/tmp/.pkglist || return 1
	fi
	# Use default ftp install routine from arch livecd
	if [ "$MODE" = "ftp" ]; then
		DIALOG --msgbox "Package selection is split into two stages.  First you will select package categories that contain packages you may be interested in.  Then you will be presented with a full list of packages with your categories already selected, allowing you to fine-tune.\n\nNOTE: The BASE category is always installed, and its packages will not appear in this menu." 18 70
		# set up our install location if necessary and sync up
		# so we can get package lists
		prepare_pacman 
		# category selection hasn't been done before
		if ! [ -f /tmp/.pkgcategory ]; then
			CATLIST=""
			for i in $($PACMAN -Sg | sed "s/^base$/ /g"); do
				CATLIST="${CATLIST} ${i} - OFF"
			done
		else
			# category selection was already run at least once
			CATLIST=""
			for i in $(cat /tmp/.pkgcategory | sed 's|\"||g'); do
				CATLIST="$CATLIST $i ^ ON"
			done
			for i in $($PACMAN -Sg | sed "s/^base$/ /g"); do
				grep $i /tmp/.pkgcategory > /dev/null 2>&1 || CATLIST="$CATLIST $i - OFF"
			done
		fi
		DIALOG --checklist "Select Package Categories" 19 55 12 $CATLIST 2>/tmp/.pkgcategory || return 1

		# mash up the package lists
		COREPKGS=$($PACMAN -Sl core | cut -d' ' -f2)

		# remove base packages from the selectable list
		for i in $($PACMAN -Sg base | tail +2); do
			COREPKGS=$(echo ${COREPKGS} | sed "s/\(^${i} \| ${i} \| ${i}$\)/ /g")
		done
		# assemble a list of pre-selected packages
		for i in $(cat /tmp/.pkgcategory | sed 's|"||g'); do
			CATPKGS="$CATPKGS $($PACMAN -Sg ${i} | tail +2)"
		done
		# put together the menu list
		PKGLIST=""
		for i in ${COREPKGS}; do
			# if the package was preselected, check it
			if [ -n "$(echo $CATPKGS | grep "\(^${i} \| ${i} \| ${i}$\)")" ]; then
				PKGLIST="$PKGLIST ${i} ^ ON"
			else
				PKGLIST="$PKGLIST ${i} - OFF"
			fi
		done
		DIALOG --checklist "Select Packages To Install." 19 60 12 $PKGLIST 2>/tmp/.pkglist || return 1
	fi
	S_SELECT=1
}

doinstall()
{
	# begin install
	rm -f /tmp/pacman.log
	# all pacman output goes to /tmp/pacman.log, which we tail into a dialog
	( \
		echo "Installing Packages..." >/tmp/pacman.log ; echo >>/tmp/pacman.log ; \
		touch /tmp/setup-pacman-running ; \
		$PACMAN -S $(echo $* | sed 's|"||g') >>/tmp/pacman.log 2>&1 ; \
		echo $? >/tmp/.pacman.retcode; \
		echo >>/tmp/pacman.log; \

		if [ "$(cat /tmp/.pacman.retcode)" -gt 0 ]; then
			echo "Package Installation FAILED." >>/tmp/pacman.log
		else
			echo "Package Installation Complete." >>/tmp/pacman.log
		fi
		rm /tmp/setup-pacman-running
	) &

	sleep 2
	dialog --backtitle "$TITLE" --title " Installing... Please Wait " \
	--no-kill --tailboxbg "/tmp/pacman.log" 18 70 2>/tmp/.pid
	while [ -f /tmp/setup-pacman-running ]; do
		sleep 1
	done
	kill $(cat /tmp/.pid)
	if [ "$(cat /tmp/.pacman.retcode)" -gt 0 ]; then
		result="Installation Failed (see errors below)"
		retcode=1
	else
		result="Installation Complete"
		retcode=0
	fi
	# disabled for now
	#dialog --backtitle "$TITLE" --title " $result " \
	#	--exit-label "Continue" --textbox "/tmp/pacman.log" 18 70
	# fix the stair-stepping that --tailboxbg leaves us with
	stty onlcr

	rm -f /tmp/.pacman.retcode
	return $retcode
}

installpkg() {
	if ! [ "$S_SRC" = "1" ]; then
		DIALOG --msgbox "Error:\nYou must select Source first." 0 0
		return 1
	fi
	if [ "$MODE" = "cd" ]; then
		if [ ! -f /tmp/.pkglist -o "$S_SELECT" != "1" ]; then
			DIALOG --msgbox "You must select packages first." 0 0
			return 1
		fi
	fi
	if [ "$S_MKFS" != "1" -a "$S_MKFSAUTO" != "1" ]; then
		getdest
	fi

	DIALOG --msgbox "Package installation will begin now.  You can watch the output in the progress window. Please be patient." 0 0
	if [ "$MODE" = "cd" ]; then
	LIST=
	# fix pacman list!
	sed -i -e 's/-i686//g' -e 's/-x86_64//g' /tmp/.pkglist
	for pkg in $(cat /tmp/.pkglist); do
		pkgname=${pkg%-*-*}
		LIST="$LIST $pkgname"
	done
	fi
	if [ "$MODE" = "ftp" ]; then
		LIST="base" # always install base
		for pkg in $(cat /tmp/.pkglist); do
			LIST="$LIST $pkg"
		done
	fi
	# for a CD install, we don't need to download packages first
	if [ "$MODE" = "ftp" ]; then
		DIALOG --infobox "Downloading packages.  See $LOG for output." 6 55
		$PACMAN -Sw $(echo $LIST | sed 's|"||g') >$LOG 2>&1
		if [ $? -gt 0 ]; then
			DIALOG --msgbox "One or more packages failed to download.  You can try again by re-selecting Install Packages from the main menu." 12 65
			return 1
		fi
	fi
	# mount proc/sysfs first, so initcpio can use auto-detection if it wants
	! [ -d $DESTDIR/proc ] && mkdir $DESTDIR/proc
	! [ -d $DESTDIR/sys ] && mkdir $DESTDIR/sys
	! [ -d $DESTDIR/dev ] && mkdir $DESTDIR/dev
	mount -t proc none $DESTDIR/proc
	mount -t sysfs none $DESTDIR/sys
	mount -o bind /dev $DESTDIR/dev
	doinstall $LIST
	 if [ $? -gt 0 ]; then
		DIALOG --msgbox "One or more packages failed to install.  You can try again by re-selecting Install Packages from the main menu." 12 65
		return 1
	fi
	dialog --backtitle "$TITLE" --title " $result " \
		--exit-label "Continue" --textbox "/tmp/pacman.log" 18 70
	if [ $? -gt 0 ]; then
		return 1
	fi
	S_INSTALL=1
	# add archboot addons if activated
	if [ -d /tmp/packages ]; then
		DO_ADDON=""
		DIALOG --yesno "Would you like to install your addons packages to installed system?" 0 0 && DO_ADDON="yes"
		if [ "$DO_ADDON" = "yes" ] ; then
			DIALOG --infobox "Installing the addons packages..." 0 0
			$PACMAN -U /tmp/packages/*
		fi
	fi
	umount $DESTDIR/proc $DESTDIR/sys $DESTDIR/dev
	sync
	# Modify fstab
	if [ "$S_MKFS" = "1" -o "$S_MKFSAUTO" = "1" ]; then
		if [ -f /tmp/.fstab ]; then
			# clean fstab first from /dev entries
			sed -i -e '/^\/dev/d' $DESTDIR/etc/fstab
			# clean /media from old floppy,cd,dvd entries
			rm -r $DESTDIR/media/cd*
			rm -r $DESTDIR/media/dvd*
			rm -r $DESTDIR/media/fl*
			# add floppy,cd and dvd entries first
			for i in $(ls -d /dev/cdro* | grep -v "0"); do
				k=$(echo $i | sed -e 's|/dev/||g')
				echo "$i /media/$k   auto    ro,user,noauto,unhide   0      0" >>$DESTDIR/etc/fstab
			# create dirs in /media
				mkdir -p $DESTDIR/media/$k
			done
			for i in $(ls -d /dev/dvd* | grep -v "0"); do
				k=$(echo $i | sed -e 's|/dev/||g')
				echo "$i /media/$k   auto    ro,user,noauto,unhide   0      0" >>$DESTDIR/etc/fstab
			# create dirs in /media
				mkdir -p $DESTDIR/media/$k
			done
			for i in $(ls -d /dev/fd[0-9] | grep -v "[0-9][0-9][0-9]"); do
				k=$(echo $i | sed -e 's|/dev/||g')
				echo "$i /media/$k   auto    user,noauto   0      0" >>$DESTDIR/etc/fstab
			# create dirs in /media
				mkdir -p $DESTDIR/media/$k
			done
			sort /tmp/.fstab >>$DESTDIR/etc/fstab
		fi
	fi
}

select_source()
{
	if ! [ $(which $DLPROG) ]; then
		DIALOG --menu "Please select an installation source" 10 35 3 \
		"1" "CD-ROM or OTHER SOURCE" 2>$ANSWER || return 1
	else
		DIALOG --menu "Please select an installation source" 10 35 3 \
		"1" "CD-ROM or OTHER SOURCE" \
		"2" "FTP/HTTP" 2>$ANSWER || return 1
	fi

	case $(cat $ANSWER) in
		"1")
			MODE="cd"
			;;
		"2")
			MODE="ftp"
			;;
	esac 

	if [ "$MODE" = "cd" ]; then
		TITLE="Arch Linux CDROM or OTHER SOURCE Installation"
		getsource
	else
		TITLE="Arch Linux FTP/HTTP Installation"
		DIALOG --msgbox "If you wish to load your ethernet modules manually, please do so now (consoles 1 thru 6 are active)." 12 65
		while $(/bin/true); do
		    DIALOG --menu "FTP Installation" 10 35 3 \
		    "0" "Setup Network" \
		    "1" "Choose Mirror" \
		    "2" "Return to Main Menu" 2>$ANSWER

		    case "$(cat $ANSWER)" in
			"0")
				donetwork ;;
			"1")
				getsource ;;
			 *)
				break ;;
		    esac
		done
	fi
}

