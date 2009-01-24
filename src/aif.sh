#!/bin/bash

###### Set some default variables ######
TITLE="Arch Linux Installation Framework"
LOG="/dev/tty7"
RUNTIME_DIR=/home/arch/aif/runtime
LOGFILE=$RUNTIME_DIR/aif.log


###### Miscalleaneous functions ######

usage ()
{
	#NOTE: you can't use dia mode here yet because lib-ui isn't sourced yet.  But cli is ok for this anyway.
	msg="aif -p <procedurename>  Select a procedure
    -i <dia/cli>         Override interface type (optional)
    -d                   Explicitly enable debugging (optional)
    -l                   Explicitly enable logging to file (optional)
    -h                   Help: show usage  (optional)\n
If the procedurename starts with 'http://' it will be wget'ed.  Otherwise it's assumed to be a procedure in the VFS tree
If the procedurename is prefixed with '<modulename>/' it will be loaded from user module <modulename>.\n
For more info, see the README which you can find in /home/arch/aif/docs\n
Available procedures on the filesystem:
`find /home/arch/aif/core/procedures -type f`\n
`find /home/arch/aif/user/*/procedures -type f 2>/dev/null`" 
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
	echo -e "$str" > $LOG
	[ "$LOG_TO_FILE" = 1 ] && echo -e "$str" >> $LOGFILE
}


debug ()
{
	str="[DEBUG] $@"
	if [ "$DEBUG" = "1" ]
	then
		echo -e "$str" > $LOG
		[ "$LOG_TO_FILE" = 1 ] && echo -e "$str" >> $LOGFILE
	fi
}


###### Core functions ######


# $1 module name
load_module ()
{
	[ -z "$1" ] && die_error "load_module needs a module argument"
	log "Loading module $1 ..."
	path=/home/arch/aif/user/"$1"
	[ "$1" = core ] && path=/home/arch/aif/core
	
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
		procedure=$RUNTIME_DIR/procedure-downloaded-`basename $2`
		wget "$2" -q -O $procedure >/dev/null || die_error "Could not download procedure $2" 
	else
		log "Loading procedure $1/procedures/$2 ..."
		procedure=/home/arch/aif/user/"$1"/procedures/"$2"
		[ "$1" = core ] && procedure=/home/arch/aif/core/procedures/"$2"
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
	lib=/home/arch/aif/user/"$1"/libs/"$2"
	[ "$1" = core ] && lib=/home/arch/aif/core/libs/"$2"
	source $lib || die_error "Something went wrong while sourcing library $lib"
}


# $1 phase/worker
# $2 phase/worker name
# $3... extra args for phase/worker (optional)
execute ()
{
	[ -z "$1" -o -z "$2" ] && debug "execute $@" && die_error "Use the execute function like this: execute <type> <name> with type=phase/worker"
	[ "$1" != phase -a "$1" != worker ] && debug "execute $@" && die_error "execute's first argument must be a valid type (phase/worker)"
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

	debug "Execute(): $object exit state was $ret"
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
	debug "Ended_ok? -> Exit state of $object was: ${!exit_var} (if empty. it's not executed yet)"
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


process_args ()
{
	true
}


start_installer ()
{
	log "################## START OF INSTALLATION ##################"
	cleanup_runtime
}


# use this function to stop the installation procedure.
# $1 exit code (optional)
stop_installer ()
{
	log "-------------- STOPPING INSTALLATION ----------"
	cleanup_runtime
	exit $1
}


###### perform actual logic ######
echo "Welcome to $TITLE"

mount -o remount,rw / &>/dev/null 


### Set configuration values ###
# note : you're free to use or ignore these in your procedure.  probably you want to use these variables to override defaults in your configure worker

#DEBUG: don't touch it. it can be set in the env
arg_ui_type=
LOG_TO_FILE=0
module=
procedure=


# TODO: you cannot override $var_OPTS_STRING, nor process_args. because profile not sourced yet
# we will hit '?)' and exit 5
# solutions? don't make $var_OPTS_STRING overridable, source correct profile as early as possible so process_args gets known.  remove the '?)' catchall (eg put it in the default process_args) so we don't hit it accidentially
# in that case -p needs to be the first option, but that's doable imho
# an alternative would be to provide an argumentstring for the profile. eg aif -p profile -a "-a a -b b -c c"

var_OPTS_STRING=":i:dlp:" # you can override this variable in your procedure.
while getopts $var_OPTS_STRING OPTION
do
	case $OPTION in
	i)
		[ -z "$OPTARG" ] && usage && exit 1 #TODO: check if it's necessary to do this. the ':' in $var_OPTS_STRING might be enough
		[ "$OPTARG" != cli -a "$OPTARG" = !dia ] && die_error "-i must be dia or cli"
		arg_ui_type=$OPTARG
		;;
	d)
		export DEBUG=1
		LOG_TO_FILE=1
		;;
	l)
		LOG_TO_FILE=1
		;;
	p)
		[ -z "$OPTARG" ] && usage && exit 1
		# note that we allow procedures like http://foo/bar. module -> http:, procedure -> http://foo/bar.
		if [[ $OPTARG =~ ^http:// ]]
		then
			module=http
			procedure="$OPTARG"
		elif grep -q '\/' <<< "$OPTARG"
		then
			#user specified module/procedure
			module=`dirname "$OPTARG"`
			procedure=`basename "$OPTARG"`
		else
			module=core
			procedure="$OPTARG"
		fi
		;;
	h)
		usage
		exit
		;;
	?)
		usage
		exit 5
		;;
	esac

	process_args $OPTION $OPTARG # you can override this function in your profile to parse additional arguments and/or override the behavior above
done

[ -z "$procedure" ] && usage && exit 5

load_module core
[ "$module" != core -a "$module" != http ] && load_module "$module"

load_procedure "$module" "$procedure"

# Set pacman vars.  allow procedures to have set $var_TARGET_DIR (TODO: look up how delayed variable substitution works. then we can put this at the top again)
# flags like --noconfirm should not be specified here.  it's up to the procedure to decide the interactivity
PACMAN=pacman
PACMAN_TARGET="pacman --root $var_TARGET_DIR --config /tmp/pacman.conf"

start_installer

start_process

stop_installer
