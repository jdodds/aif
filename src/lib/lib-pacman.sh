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
	[ "$var_PKG_SOURCE_TYPE" = "cd" ] && local serverurl="${FILE_URL}"
	[ "$var_PKG_SOURCE_TYPE" = "ftp" ] && local serverurl="${SYNC_URL}"

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



# select_mirror(). taken from setup.  TODO: get the UI code out of here
# Prompt user for preferred mirror and set $SYNC_URL
#
# args: none
# returns: nothing
select_mirror() { 
	notify "Keep in mind ftp.archlinux.org is throttled.\nPlease select another mirror to get full download speed."
	# FIXME: this regex doesn't honor commenting
	MIRRORS=$(egrep -o '((ftp)|(http))://[^/]*' "${MIRRORLIST}" | sed 's|$| _|g')
	_dia_DIALOG --menu "Select an FTP/HTTP mirror" 14 55 7 \
                  $MIRRORS \
                  "Custom" "_" 2>$ANSWER || return 1
    local _server=$(cat $ANSWER)
    if [ "${_server}" = "Custom" ]; then
        _dia_DIALOG --inputbox "Enter the full URL to core repo." 8 65 \
                "ftp://ftp.archlinux.org/core/os/i686" 2>$ANSWER || return 1
        SYNC_URL=$(cat $ANSWER)
    else
        # Form the full URL for our mirror by grepping for the server name in
        # our mirrorlist and pulling the full URL out. Substitute 'core' in  
        # for the repository name, and ensure that if it was listed twice we
        # only return one line for the mirror.
        SYNC_URL=$(egrep -o "${_server}.*" "${MIRRORLIST}" | sed 's/\$repo/core/g' | head -n1)
    fi
    echo "Using mirror: $SYNC_URL" >$LOG
}

# select_source(). taken from setup.  TODO: decouple ui
# displays installation source selection menu
# and sets up relevant config files
#
# params: none
# returns: nothing
select_source()   
{
    DIALOG --menu "Please select an installation source" 10 35 3 \
    "1" "CD-ROM or OTHER SOURCE" \
    "2" "FTP/HTTP" 2>$ANSWER

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
        DIALOG --msgbox "Packages included on this disk have been mounted to /src/core/pkg. If you wish to use your own packages from another source, manually mount them there." 0 0
        if [ ! -d /src/core/pkg ]; then
            DIALOG --msgbox "Package directory /src/core/pkg is missing!" 0 0
            return 1
        fi
        echo "Using CDROM for package installation" >$LOG
    else
        TITLE="Arch Linux FTP/HTTP Installation"
        DIALOG --msgbox "If you wish to load your ethernet modules manually, please do so now in another terminal." 12 65
         while true; do
            DIALOG --menu "FTP Installation" 10 35 3 \
            "0" "Setup Network" \
            "1" "Choose Mirror" \
            "2" "Return to Main Menu" 2>$ANSWER

            case "$(cat $ANSWER)" in
                "0")
                    donetwork ;;
                "1")
                    select_mirror ;;
                *)
                    break ;;
            esac
        done
   fi
   S_SRC=1
}
