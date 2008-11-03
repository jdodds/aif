#!/bin/bash
# TODO: we should be able to get away with not defining the "These functions would fit more in lib-ui, but we need them immediately" functions in lib-ui, but just sourcing lib-ui very early

###### Set some default variables or get them from the setup script ######
TITLE="Flexible Installer Framework for Arch linux"
LOG="/dev/tty7"



###### Miscalleaneous functions ######

usage ()
{
	msg="$0 <procedurename>\n
If the procedurename starts with 'http://' it will be wget'ed.  Otherwise it's assumed to be a procedure in the VFS tree\n
If the procedurename is prefixed with '<modulename>/' it will be loaded from user module <modulename>.  See README\n
Available procedures on the filesystem:\n
`find /home/arch/fifa/core/procedures -type f`\n
`find /home/arch/fifa/user/*/procedures -type f`" 
	if [ "$var_UI_TYPE" = dia ]
	then
		DIALOG --msgbox "$msg" 14 65
	else
		echo "$msg"
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


# $1 module name
load_module ()
{
	[ -z "$1" ] && die_error "load_module needs a module argument"
	notify "Loading module $1 ..."
	path=/home/arch/fifa/user/"$1"
	[ "$1" = core ] && path=/home/arch/fifa/core
	
	for submodule in lib #procedure don't load procedures automatically!
	do	
		if [ ! -d "$path/${submodule}s" ]
		then
			# ignore this problem for not-core modules
			[ "$1" = core ] && die_error "$path/${submodule}s does not exist. something is horribly wrong with this installation"
		else
			shopt -s nullglob
			for i in "$path/${submodule}s"/*
			do
				load_${submodule} "$1" "`basename "$i"`"
			done
		fi
	done
			
}


# $1 module name 
# $2 procedure name
load_procedure()
{
	[ -z "$1" ] && die_error "load_procedure needs a module as \$1 and procedure as \$2"
	[ -z "$2" ] && die_error "load_procedure needs a procedure as \$2"
	if [ "$1" = 'http:' ]
	then
		notify "Loading procedure $2 ..."
		procedure=/home/arch/fifa/runtime/procedure-downloaded-`basename $2`
		wget "$2" -q -O $procedure >/dev/null || die_error "Could not download procedure $2" 
	else
		notify "Loading procedure $1/procedures/$2 ..."
		procedure=/home/arch/fifa/user/"$1"/procedures/"$2"
		[ "$1" = core ] && procedure=/home/arch/fifa/core/procedures/"$2"
	fi
	[ -f "$procedure" ] && source "$procedure" || die_error "Something went wrong while sourcing procedure $procedure"
}


# $1 module name   
# $2 library name
load_lib ()
{
	[ -z "$1" ] && die_error "load_library needs a module als \$1 and library as \$2"
	[ -z "$2" ] && die_error "load_library needs a library as \$2"
	notify "Loading library $1/libs/$2 ..."
	lib=/home/arch/fifa/user/"$1"/libs/"$2"
	[ "$1" = core ] && lib=/home/arch/fifa/core/libs/"$2"
	source $lib || die_error "Something went wrong while sourcing library $lib"
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
		ret=$?
		cd $PWD_BACKUP
	else
		die_error "$1 $2 is not defined!"
	fi

	return $?
}


depend_module ()
{
	load_module "$1"
}


depend_procedure ()
{
	load_procedure "$1" "$2"
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

# note that we allow procedures like http://foo/bar. module -> http:, procedure -> http://foo/bar. 
if [[ $1 =~ ^http:// ]]
then
	module=http
	procedure="$1"
elif grep -q '\/' <<< "$1"
then
	#user specified module/procedure
	module=`dirname "$1"`
	procedure=`basename "$1"`
else
	module=core
	procedure="$1"
fi

load_module core
[ "$module" != core -a "$module" != http ] && load_module "$module"

load_procedure "$module" "$procedure"

# Set pacman vars.  allow procedures to have set $var_TARGET_DIR (TODO: look up how delayed variable substitution works. then we can put this at the top again)
# flags like --noconfirm should not be specified here.  it's up to the procedure to decide the interactivity
PACMAN=pacman
PACMAN_TARGET="pacman --root $var_TARGET_DIR --config /tmp/pacman.conf"

start_process

exit 0
