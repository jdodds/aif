#!/bin/sh


# run a process in the background, and log it's stdout and stderr to a specific logfile
# returncode is stored in $<identifier>_exitcode
# $1 identifier
# $2 command (will be eval'ed)
# $3 logfile
run_background ()
{
	[ -z "$1" ] && die_error "run_background: please specify an identifier to keep track of the command!"
	[ -z "$2" ] && die_error "run_background needs a command to execute!"
	[ -z "$3" ] && die_error "run_background needs a logfile to redirect output to!"

	debug "run_background called. identifier: $1, command: $2, logfile: $3"
	( \
		touch /home/arch/fifa/runtime/$1-running
		debug "run_background starting $1: $2 >>$3 2>&1"
		[ -f $3 ] && echo -e "\n\n\n" >>$3
		echo "STARTING $1 . Executing $2 >>$3 2>&1" >> $3; \
		echo >> $3; \
		eval "$2" >>$3 2>&1
		var_exit=${1}_exitcode
		read $var_exit <<< $? #TODO: bash complains about 'invalid key' or something iirc
		debug "run_background done with $1: exitcode (\$$1_exitcode): "${!var_exit}" .Logfile $3" #TODO ${!var_exit} doesn't show anything
		echo >> $3   
		rm -f /home/arch/fifa/runtime/$1-running
	) &

	sleep 2
}


# wait until a process is done
# $1 identifier
wait_for ()
{
	[ -z "$1" ] && die_error "wait_for needs an identifier to known on which command to wait!"

	while [ -f /home/arch/fifa/runtime/$1-running ]
	do
		#TODO: follow_progress dialog mode = nonblocking (so check and sleep is good), cli mode (tail -f )= blocking? (so check is probably not needed as it will be done)
		sleep 1
	done

	kill $(cat $ANSWER) #TODO: this may not work when mode = cli
}

