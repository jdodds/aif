#!/bin/bash


###### Set some default variables or get them from the setup script ######
TITLE="Flexible Installer Framework for Arch linux"
LOG="/dev/tty7"



###### Miscalleaneous functions ######

usage ()
{
	if [ "$var_UI_TYPE" = dia ]
	then
		DIALOG --msgbox "$0 <profilename>\n
		If the profilename starts with 'http://' it will be wget'ed.  Otherwise it's assumed to be a profile saved on disk.  See README\n
		Available profiles:\n
		`ls -l /home/arch/fifa/profile-*`" 14 65
	else
		echo "$0 <profilename>"
		echo "If the profilename starts with 'http://' it will be wget'ed.  Otherwise it's assumed to be a profile saved on disk.  See README"
		echo "Available profiles:"
		ls -l /home/arch/fifa/profile-*
	fi
}


##### "These functions would fit more in lib-ui, but we need them immediately" functions ######


# display error message and die
die_error ()
{
	if [ "$var_UI_TYPE" = dia ]
	then
		DIALOG --msgbox "Error: $@" 0 0
	else
		echo "ERROR: $@"
	fi
	exit 2
}


# display warning message
# $1 title
# $2 item to show
# $3 type of item.  msg or text if it's a file. (optional. defaults to msg)
show_warning ()
{
	[ -z "$1" ] && die_error "show_warning needs a title"
	[ -z "$2" ] && die_error "show_warning needs an item to show"
	[ -n "$3" -a "$3" != msg -a "$3" != text ] && die_error "show_warning \$3 must be text or msg"
	[ -z "$3" ] && 3=msg
	if [ "$var_UI_TYPE" = dia ]
	then
		dialog --title "$1" --exit-label "Continue" --$3box "$2" 18 70 || die_error "dialog could not show --$3box $2. often this means a file does not exist"
	else
		echo "WARNING: $1"
		[ "$3" = msg ] && echo $2
		[ "$3" = text ] && cat $2 || die_error "Could not cat $2"
	fi
}


#notify user
notify ()
{
	if [ "$var_UI_TYPE" = dia ]
	then
		DIALOG --msgbox "$@" 20 50
	else
		echo "$@"
	fi
}


###### Core functions ######

load_profile()
{
	[ -z "$1" ] && die_error "load_profile needs a profile argument"
	notify "Loading profile $1 ..."
	if [[ $1 =~ ^http:// ]]
	then
		profile=/home/arch/fifa/profile-downloaded-`basename $1`
		wget $1 -q -O $profile >/dev/null || die_error "Could not download profile $1" 
	else
		profile=/home/arch/fifa/profile-$1
	fi
	[ -f "$profile" ] && source "$profile" || die_error "Something went wrong while sourcing profile $profile"
}


load_library ()
{
	[ -z "$1" ] && die_error "load_library needs a library argument"
	for library in $@
	do
		notify "Loading library $library ..."
		source $library || die_error "Something went wrong while sourcing library $library"
	done
}


execute ()
{
	[ -z "$1" -o -z "$2" ] && die_error "Use the execute function like this: execute <type> <name> with type=phase/worker"
	[ "$1" != phase -a "$1" != worker ] && die_error "execute's first argument must be a valid type (phase/worker)"
	[ "$1" = phase ]  && notify "******* Executing phase $2"
	[ "$1" = worker ] && notify "*** Executing worker $2"
	if type -t $1_$2 | grep -q function
	then
		PWD_BACKUP=`pwd`
		$1_$2
		cd $PWD_BACKUP
	else
		die_error "$1 $2 is not defined!"
	fi
}


start_process ()
{
	execute phase preparation
	execute phase basics
	execute phase system
	execute phase finish
}



###### perform actual logic ######
echo "Welcome to $TITLE"
[ -z "$1" ] && usage && exit 1

mount -o remount,rw / &>/dev/null 

load_library /home/arch/fifa/lib/lib-*.sh

[ "$1" != base ] && load_profile base
load_profile $1

# Set pacman vars.  allow profiles to have set $var_TARGET_DIR (TODO: look up how delayed variable substitution works. then we can put this at the top again)
# flags like --noconfirm should not be specified here.  it's up to the profile to decide the interactivity
PACMAN=pacman
PACMAN_TARGET="pacman --root $var_TARGET_DIR --config /tmp/pacman.conf"

start_process

exit 0