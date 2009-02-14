#!/bin/bash

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
# $@ repositories to enable (optional. default: core)
# returns: 1 on error
target_prepare_pacman() {   
	[ "$var_PKG_SOURCE_TYPE" = "cd" ] && local serverurl="${var_FILE_URL}"
	[ "$var_PKG_SOURCE_TYPE" = "ftp" ] && local serverurl="${var_SYNC_URL}"

	[ -z "$1" ] && repos=core
	[ -n "$1" ] && repos="$@"
	# Setup a pacman.conf in /tmp
	cat << EOF > /tmp/pacman.conf
[options]
CacheDir = ${var_TARGET_DIR}/var/cache/pacman/pkg
CacheDir = /src/core/pkg
EOF

for repo in $repos
do
	#TODO: this is a VERY, VERY dirty hack.  we fall back to ftp for any non-core repo because we only have core on the CD. also user maybe didn't pick a mirror yet
	if [ "$repo" != core ]
	then
		add_pacman_repo target ${repo} "Include = $var_MIRRORLIST"
	else
		add_pacman_repo target ${repo} "Server = ${serverurl/\/\$repo\//\/$repo\/}" # replace literal '/$repo/' in the serverurl string by "/$repo/" where $repo is our variable.
	fi
done
	# Set up the necessary directories for pacman use
	[ ! -d "${var_TARGET_DIR}/var/cache/pacman/pkg" ] && mkdir -m 755 -p "${var_TARGET_DIR}/var/cache/pacman/pkg"
	[ ! -d "${var_TARGET_DIR}/var/lib/pacman" ] && mkdir -m 755 -p "${var_TARGET_DIR}/var/lib/pacman"

	infofy "Refreshing package database..."
	$PACMAN_TARGET -Sy >$LOG 2>&1 || return 1 #TODO: make sure this also goes into the logfile. actually we should do this for many commands.
	return 0
}


# $1 target/runtime
list_pacman_repos ()
{
	[ "$1" != runtime -a "$1" != target ] && die_error "list_pacman_repos needs target/runtime argument"
	[ "$1" = target  ] && conf=/tmp/pacman.conf
	[ "$1" = runtime ] && conf=/etc/pacman.conf
	grep '\[.*\]' $conf | grep -v options | grep -v '^#' | sed 's/\[//g' | sed 's/\]//g'
}


# $1 target/runtime
# $2 repo name
# $3 string
add_pacman_repo ()
{
	[ "$1" != runtime -a "$1" != target ] && die_error "add_pacman_repo needs target/runtime argument"
	[ -z "$3" ] && die_error "target_add_repo needs \$2 repo-name and \$3 string (eg Server = ...)"
	[ "$1" = target  ] && conf=/tmp/pacman.conf
	[ "$1" = runtime ] && conf=/etc/pacman.conf
	cat << EOF >> $conf

[${2}]
${3}
EOF
}


# taken from quickinst. TODO: figure this one out ASKDEV
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

