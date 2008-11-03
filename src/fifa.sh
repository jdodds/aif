#!/bin/bash

###### Set some default variables or get them from the setup script ######
TITLE="Flexible Installer Framework for Arch linux"
LOG="/dev/tty7"



###### Miscalleaneous functions ######

usage ()
{
	#NOTE: you can't use dia mode here yet because lib-ui isn't sourced yet.  But cli is ok for this anyway.
	msg="$0 <procedurename>\n
If the procedurename starts with 'http://' it will be wget'ed.  Otherwise it's assumed to be a procedure in the VFS tree
If the procedurename is prefixed with '<modulename>/' it will be loaded from user module <modulename>.  See README\n
Available procedures on the filesystem:
`find /home/arch/fifa/core/procedures -type f`\n
`find /home/arch/fifa/user/*/procedures -type f`" 
	echo -e "$msg"

}

##### TMP functions that we need during early bootstrap but will be overidden with decent functions by libraries ######


notify ()
{
	echo -e "$@"
}


log ()
{
	 echo -e "[LOG] `date +"%Y-%m-%d %H:%M:%S"` $@"
	 echo -e "[LOG] `date +"%Y-%m-%d %H:%M:%S"` $@" >$LOG
}


###### Core functions ######


# $1 module name
load_module ()
{
	[ -z "$1" ] && die_error "load_module needs a module argument"
	log "Loading module $1 ..."
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
		log "Loading procedure $2 ..."
		procedure=/home/arch/fifa/runtime/procedure-downloaded-`basename $2`
		wget "$2" -q -O $procedure >/dev/null || die_error "Could not download procedure $2" 
	else
		log "Loading procedure $1/procedures/$2 ..."
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
	log "Loading library $1/libs/$2 ..."
	lib=/home/arch/fifa/user/"$1"/libs/"$2"
	[ "$1" = core ] && lib=/home/arch/fifa/core/libs/"$2"
	source $lib || die_error "Something went wrong while sourcing library $lib"
}


execute ()
{
	[ -z "$1" -o -z "$2" ] && die_error "Use the execute function like this: execute <type> <name> with type=phase/worker"
	[ "$1" != phase -a "$1" != worker ] && die_error "execute's first argument must be a valid type (phase/worker)"
	[ "$1" = phase ]  && log "******* Executing phase $2"
	[ "$1" = worker ] && log "*** Executing worker $2"
	if type -t $1_$2 | grep -q function
	then
		PWD_BACKUP=`pwd`
		$1_$2
		ret=$?
		cd $PWD_BACKUP
	else
		die_error "$1 $2 is not defined!"
	fi

	return $ret
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


# use this function to stop the installation procedure.
# $1 exit code (optional)
stop_installer ()
{
	log "-------------- STOPPING INSTALLATION ----------"
	exit $1
}


###### perform actual logic ######
echo "Welcome to $TITLE"
log "################## START OF INSTALLATION ##################"
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
