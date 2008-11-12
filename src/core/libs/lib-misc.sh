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

	( \
		touch /home/arch/fifa/runtime/$1-running
		echo "$1 progress ..." > $3; \
		echo >> $3; \
		eval "$2" >>$3 2>&1
		read $1_exitcode <<< $?
		echo >> $3   
		rm -f /home/arch/fifa/runtime/$1-running
	) &

	sleep 2
}


# wait untill a process is done
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

