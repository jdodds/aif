#!/bin/sh

# taken and slightly modified from the quickinst script.
# don't know why one should need a static pacman because we already have a working one on the livecd.
assure_pacman_static ()
{
	PACMAN_STATIC=
	[ -f /tmp/usr/bin/pacman.static ] && PACMAN_STATIC=/tmp/usr/bin/pacman.static
	[ -f /usr/bin/pacman.static ] && PACMAN_STATIC=/usr/bin/pacman.static
	if [ "$PACMAN_STATIC" = "" ]; then
		cd /tmp
		if [ "$var_PKG_SOURCE_TYPE" = "ftp" ]; then
			echo "Downloading pacman..."
			wget $PKGARG/pacman*.pkg.tar.gz
			if [ $? -gt 0 ]; then
				echo "error: Download failed"
				exit 1
			fi
			tar -xzf pacman*.pkg.tar.gz
		elif [ "$var_PKG_SOURCE_TYPE" = "cd" ]; then
			echo "Unpacking pacman..."
			tar -xzf $PKGARG/pacman*.pkg.tar.gz
		fi
	fi
	[ -f /tmp/usr/bin/pacman.static ] && PACMAN_STATIC=/tmp/usr/bin/pacman.static
	if [ "$PACMAN_STATIC" = "" ]; then
		echo "error: Cannot find the pacman.static binary!"
		exit 1
	fi
}


# taken from the quickinst script. cd/ftp code merged together
target_write_pacman_conf ()
{
	PKGFILE=/tmp/packages.txt
	echo "[core]" >/tmp/pacman.conf
	if [ "$var_PKG_SOURCE_TYPE" = "ftp" ]
	then
		wget $PKG_SOURCE/packages.txt -O /tmp/packages.txt || die_error " Could not fetch package list from server"
		echo "Server = $PKGARG" >>/tmp/pacman.conf
	fi
	if [ "$var_PKG_SOURCE_TYPE" = "cd" ]
	then
		[ -f $PKG_SOURCE/packages.txt ] || die_error "error: Could not find package list: $PKGFILE"
		cp $PKG_SOURCE/packages.txt /tmp/packages.txt
		echo "Server = file://$PKGARG" >>/tmp/pacman.conf
	fi
	mkdir -p $var_TARGET_DIR/var/cache/pacman/pkg /var/cache/pacman &>/dev/null
	rm -f /var/cache/pacman/pkg &>/dev/null
	[ "$var_PKG_SOURCE_TYPE" = "ftp" ] && ln -sf $var_TARGET_DIR/var/cache/pacman/pkg /var/cache/pacman/pkg &>/dev/null
	[ "$var_PKG_SOURCE_TYPE" = "cd" ]  && ln -sf $PKGARG                       /var/cache/pacman/pkg &>/dev/null
}


# target_prepare_pacman() taken from setup. modified a bit
# configures pacman and syncs for the first time on destination system
#
# params: none
# returns: 1 on error
target_prepare_pacman() {   
	[ "$var_PKG_SOURCE_TYPE" = "cd" ] && local serverurl="${var_FILE_URL}"
	[ "$var_PKG_SOURCE_TYPE" = "ftp" ] && local serverurl="${var_SYNC_URL}"

	# Setup a pacman.conf in /tmp
	cat << EOF > /tmp/pacman.conf
[options]
CacheDir = ${var_TARGET_DIR}/var/cache/pacman/pkg
CacheDir = /src/core/pkg

[core]
Server = ${serverurl}
EOF

	# Set up the necessary directories for pacman use
	[ ! -d "${var_TARGET_DIR}/var/cache/pacman/pkg" ] && mkdir -m 755 -p "${var_TARGET_DIR}/var/cache/pacman/pkg"
	[ ! -d "${var_TARGET_DIR}/var/lib/pacman" ] && mkdir -m 755 -p "${var_TARGET_DIR}/var/lib/pacman"

	notify "Refreshing package database..."
	$PACMAN_TARGET -Sy >$LOG 2>&1 || return 1
	return 0
}


# taken from quickinst. TODO: figure this one out
pacman_what_is_this_for ()
{
	PKGLIST=
	# fix pacman list!
	sed -i -e 's/-i686//g' -e 's/-x86_64//g' $PKGFILE
	for i in $(cat $PKGFILE | grep 'base/' | cut -d/ -f2); do
		nm=${i%-*-*}
		PKGLIST="$PKGLIST $nm"
	done
	! [ -d $var_TARGET_DIR/var/lib/pacman ] && mkdir -p $var_TARGET_DIR/var/lib/pacman
	! [ -d /var/lib/pacman ] && mkdir -p /var/lib/pacman
}

