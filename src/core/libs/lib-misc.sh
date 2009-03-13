#!/bin/bash


# run a process in the background, and log it's stdout and stderr to a specific logfile
# returncode is stored in $<identifier>_exitcode
# pid of the backgrounded wrapper process is stored in BACKGROUND_PID (this is _not_ the pid of $2)
# $1 identifier -> WARNING: do never ever use -'s or other fancy characters here. only numbers, letters and _ please. (because $<identifier>_exitcode must be a valid bash variable!)
# $2 command (will be eval'ed)
# $3 logfile
run_background ()
{
	[ -z "$1" ] && die_error "run_background: please specify an identifier to keep track of the command!"
	[ -z "$2" ] && die_error "run_background needs a command to execute!"
	[ -z "$3" ] && die_error "run_background needs a logfile to redirect output to!"

	debug 'MISC' "run_background called. identifier: $1, command: $2, logfile: $3"
	( \
		touch $RUNTIME_DIR/aif-$1-running
		debug 'MISC' "run_background starting $1: $2 >>$3 2>&1"
		[ -f $3 ] && echo -e "\n\n\n" >>$3
		echo "STARTING $1 . Executing $2 >>$3 2>&1\n" >> $3;
		var_exit=${1}_exitcode
		eval "$2" >>$3 2>&1
		read $var_exit <<< $?
		debug 'MISC' "run_background done with $1: exitcode (\$$1_exitcode): ${!var_exit} .Logfile $3"
		echo >> $3   
		rm -f $RUNTIME_DIR/aif-$1-running
	) &
	BACKGROUND_PID=$!

	sleep 2
}


# wait until a process is done
# $1 identifier. WARNING! see above
# $2 pid of a process to kill when done (optional). useful for dialog --no-kill --tailboxbg's pid.
wait_for ()
{
	[ -z "$1" ] && die_error "wait_for needs an identifier to known on which command to wait!"

	while [ -f $RUNTIME_DIR/aif-$1-running ]
	do
		sleep 1
	done

	[ -n "$2" ] && kill $2
}


# $1 needle
# $2 set (array) haystack
check_is_in ()
{
	[ -z "$1" ] && die_error "check_is_in needs a non-empty needle as \$1 and a haystack as \$2!(got: check_is_in '$1' '$2'" # haystack can be empty though
	NEEDLE=$1
	HAYSTACK=$2

	local pattern="$NEEDLE" element
	shift
	for element
	do
		[[ $element = $pattern ]] && return 0
	done
	return 1
}


# cleans up file in the runtime directory who can be deleted, make dir first if needed
cleanup_runtime ()
{
	mkdir -p $RUNTIME_DIR || die_error "Cannot create $RUNTIME_DIR"
	rm -rf $RUNTIME_DIR/aif-dia* &>/dev/null
}


dohwclock() {
	infofy "Syncing hardwareclock to systemclock ..."
	if [ "$HARDWARECLOCK" = "UTC" ]; then
		HWCLOCK_PARAMS="$HWCLOCK_PARAMS --utc"
	else
		HWCLOCK_PARAMS="$HWCLOCK_PARAMS --localtime"
	fi

	[ ! -d /var/lib/hwclock ] && mkdir -p /var/lib/hwclock
	if [ ! -f /var/lib/hwclock/adjtime ]; then
		echo "0.0 0 0.0" > /var/lib/hwclock/adjtime # what the hell is this for???
	fi
	hwclock $HWCLOCK_PARAMS #tpowa does it without, but i would add --noadjtime here
}

target_configure_initial_keymap_font ()
{
	[ -n "$var_KEYMAP"      ] && sed -i "s/^KEYMAP=.*/KEYMAP=\"$var_KEYMAP\"/"                ${var_TARGET_DIR}/etc/rc.conf
	[ -n "$var_CONSOLEFONT" ] && sed -i "s/^CONSOLEFONT=.*/CONSOLEFONT=\"$var_CONSOLEFONT\"/" ${var_TARGET_DIR}/etc/rc.conf
}