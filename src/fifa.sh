#!/bin/bash

###### Set some default variables or get them from the setup script ######
TITLE="Flexible Installer Framework for Arch linux"
LOG="/dev/tty7"
LOGFILE=/home/arch/fifa/runtime/fifa.log #TODO: maybe we could use a flag to en/disable logging to a file.


###### Miscalleaneous functions ######

usage ()
{
	#NOTE: you can't use dia mode here yet because lib-ui isn't sourced yet.  But cli is ok for this anyway.
	msg="$0 <procedurename>\n
If the procedurename starts with 'http://' it will be wget'ed.  Otherwise it's assumed to be a procedure in the VFS tree
If the procedurename is prefixed with '<modulename>/' it will be loaded from user module <modulename>.  See README\n
Available procedures on the filesystem:
`find /home/arch/fifa/core/procedures -type f`\n
`find /home/arch/fifa/user/*/procedures -type f 2>/dev/null`" 
	echo -e "$msg"

}

##### TMP functions that we need during early bootstrap but will be overidden with decent functions by libraries ######


notify ()
{
	echo -e "$@"
}


log ()
{
	str="[LOG] `date +"%Y-%m-%d %H:%M:%S"` $@"
	echo -e "$str"
	echo -e "$str" > $LOG
	echo -e "$str" >> $LOGFILE
}


debug ()
{
	str="[DEBUG] $@"
	if [ "$DEBUG" = "1" ]
	then
		echo -e "$str"
		echo -e "$str" > $LOG
		echo -e "$str" >> $LOGFILE
	fi
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


# $1 phase/worker
# $2 phase/worker name
# $3... extra args for phase/worker (optional)
execute ()
{
	[ -z "$1" -o -z "$2" ] && die_error "Use the execute function like this: execute <type> <name> with type=phase/worker"
	[ "$1" != phase -a "$1" != worker ] && die_error "execute's first argument must be a valid type (phase/worker)"
	PWD_BACKUP=`pwd`
	object=$1_$2

	if [ "$1" = worker ]
	then
		log "*** Executing worker $2"
		if type -t $object | grep -q function
		then
			shift 2
			$object "$@"
			ret=$?
			exit_var=exit_$object
			read $exit_var <<< $ret # maintain exit status of each worker
		else
			die_error "$object is not defined!"
		fi
	elif [ "$1" = phase ]
	then
		log "******* Executing phase $2"
		exit_var=exit_$object
		read $exit_var <<< 0
		# TODO: for some reason the hack below does not work (tested in virtualbox), even though it really should.  Someday I must get indirect array variables working and clean this up...
		# debug "\$1: $1, \$2: $2, \$object: $object, \$exit_$object: $exit_object"
		# debug "declare: `declare | grep -e "^${object}=" | cut -d"=" -f 2-`"
		# props to jedinerd at #bash for this hack.
		# eval phase=$(declare | grep -e "^${object}=" | cut -d"=" -f 2-)
		#debug "\$phase: $phase - ${phase[@]}"
		unset phase
		[ "$2" = preparation ] && phase=( "${phase_preparation[@]}" )
		[ "$2" = basics      ] && phase=( "${phase_basics[@]}" )
		[ "$2" = system      ] && phase=( "${phase_system[@]}" )
		[ "$2" = finish      ] && phase=( "${phase_finish[@]}" )
		# worker_str contains the name of the worker and optionally any arguments
		for worker_str in "${phase[@]}"
		do
			debug "Loop iteration.  \$worker_str: $worker_str"
			execute worker $worker_str || read $exit_var <<< $? # assign last failing exit code to exit_phase_<phasename>, if any.
		done
		ret=${!exit_var}
	fi

	debug "$1 $2 exit state was $ret" #TODO: why are $1 and $2 empty here? Something to do with the recursion maybe?  Also, exit codes for phases are not shown :/
	cd $PWD_BACKUP
	return $ret
}


# check if a phase/worker executed sucessfully
# returns 0 if ok, the phase/workers' exit state otherwise (and returns 1 if not executed yet)
# $1 phase/worker
# $2 phase/worker name
ended_ok ()
{
	[ -z "$1" -o -z "$2" ] && die_error "Use the ended_ok function like this: ended_ok <type> <name> with type=phase/worker"
	[ "$1" != phase -a "$1" != worker ] && die_error "ended_ok's first argument must be a valid type (phase/worker)"
	object=$1_$2
	exit_var=exit_$object
	debug "Exit state of $object was: ${!exit_var} (if empty. it's not executed yet)"
	[ "${!exit_var}" = '0' ] && return 0
	[ "${!exit_var}" = '' ] && return 1
	return ${!exit_var}
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


show_report () #TODO: abstract UI method (cli/dia)
{
	echo "Execution Report:"
	echo "-----------------"
	for phase in preparation basics system finish
	do
		object=phase_$phase
		exit_var=exit_$object
		ret=${!exit_var}
		echo -n "Phase $phase: "
		[ "$ret" = "0" ] && echo "Success" || echo "Failed"
		eval phase_array=$(declare | grep -e "^${object}=" | cut -d"=" -f 2-)
		for worker_str in "${phase_array[@]}"
		do
			worker=${worker_str%% *}
			exit_var=exit_worker_$worker
			ret=${!exit_var}
			echo -n " > Worker $worker: "
			[ "$ret" = "0" ] && echo "Success" || echo "Failed"
		done
	done
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
