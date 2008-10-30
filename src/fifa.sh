#!/bin/bash


###### Set some default variables or get them from the setup script ######
TITLE="Flexible Installer Framework for Arch linux"
eval `grep ^LOG= /arch/setup`
PACMAN_RUNTIME=pacman
PACMAN="pacman --root $DESTDIR --config /tmp/pacman.conf --noconfirm"



###### Miscalleaneous functions ######

usage ()
{
	echo "$0 <profilename>"
	echo "If the profilename starts with 'http://' it will be wget'ed.  Otherwise it's assumed to be a profile file like /home/arch/fifa/profile-<profilename>"
	echo "If you wrote your own profile, you can also save it yourself as /home/arch/fifa/profile-custom or something like that"
	echo "Available profiles:"
	ls -l /home/arch/fifa/profile-*
	echo "Extra info:"
	echo "There is a very basic but powerfull workflow defined by variables, phases and workers.  Depending on the profile you choose (or write yourself), these will differ."
	echo "they are very recognizable and are named like this:"
	echo " - variable -> var_<foo>"
	echo " - phase    -> phase_<bar> (a function that calls workers and maybe does some stuff by itself.  There are 4 phases: preparation, basics, system, finish. (executed in that order)"
	echo " - worker   -> worker_<baz> ( a worker function, called by a phase. implements some specific logic. eg runtime_packages, prepare_disks, package_list etc)"
	echo "If you specify a profile name other then base, the base profile will be sourced first, then the specific profile.  This way you only need to override specific things."
	echo "Notes:"
	echo " - you _can_ override _all_ variables and functions in this script, but you should be able to achieve your goals by overriding things of these 3 classes)"
	echo " - you _must_ specify a profile, to avoid errors. take 'base' if unsure"
	echo " - don't edit the base profile (or any other that comes by default), rather make your own"
}


die_error ()
{
	echo "ERROR: $@"
	exit 2
}


load_profile()
{
	#TODO: http support
	echo "Loading profile $1 ..."
	profile=/home/arch/fifa/profile-"$1"
	[ -f "$profile" ] && source "$profile" || die_error "Something went wrong while sourcing profile $profile"
}


execute ()
{
	[ -z "$1" -o -z "$2" ] && die_error "Use the execute function like this: execute <type> <name> with type=phase/worker"
	[ "$1" != phase -a "$1" != worker ] && die_error "execute's first argument must be a valid type (phase/worker)"
	[ "$1" = phase ]  && echo "******* Executing phase $2"
	[ "$1" = worker ] && echo "*** Executing worker $2"
	if type -t $1_$2 | grep -q function
	then
		PWD_BACKUP=`pwd`
		$1_$2
		cd $PWD_BACKUP
	else
		die_error "$1 $2 is not defined!"
	fi
}




###### perform actual logic ######
echo "Welcome to $TITLE"
[ -z "$1" ] && usage && exit 1

mount -o remount,rw / &>/dev/null 

[ "$1" != base ] && load_profile base
load_profile $1

execute phase preparation
execute phase basics
execute phase system
execute phase finish

