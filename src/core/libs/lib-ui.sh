#!/bin/sh
# TODO: lot's of implementation work still open in this library. especially the dialog & $var_UI_TYPE stuff


# Taken from setup.  we store dialog output in a file.  TODO: can't we do this with variables? ASKDEV
ANSWER="/home/arch/aif/runtime/.dialog-answer"
DIA_MENU_TEXT="Use the UP and DOWN arrows to navigate menus.  Use TAB to switch between buttons and ENTER to select."


### Functions that your code can use. Cli/dialog mode is fully transparant.  This library takes care of it ###


# display error message and die
die_error ()
{
	[ -n "$LOGFILE" ] && debug "die_error: ERROR: $@" > $LOGFILE
	notify "ERROR: $@"
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
        type=msg
        [ -n "$3" ] && type=$3
        debug "show_warning '$1': $2 ($type)"
        if [ "$var_UI_TYPE" = dia ]
        then
                _dia_DIALOG --title "$1" --exit-label "Continue" --${type}box "$2" 18 70 || die_error "dialog could not show --${type}box $2. often this means a file does not exist"
        else
                echo "WARNING: $1"
                [ "${type}" = msg  ] && echo -e "$2"
                [ "${type}" = text ] && cat $2 || die_error "Could not cat $2"
        fi

        return 0
}
 
 
#notify user
notify ()   
{
	debug "notify: $@"
        if [ "$var_UI_TYPE" = dia ]
        then
                _dia_DIALOG --msgbox "$@" 20 50
        else
                echo -e "$@"
        fi
}


# like notify, but user does not need to confirm explicitly when in dia mode
infofy ()
{
	debug "infofy: $@"
	if [ "$var_UI_TYPE" = dia ]
	then
		_dia_DIALOG --infobox "$@" 20 50
	else
		echo -e "$@"
	fi
}


# logging of stuff
log ()
{
	str="[LOG] `date +"%Y-%m-%d %H:%M:%S"` $@"
	if [ "$var_UI_TYPE" = dia ]
	then
		echo -e "$str" >$LOG
	else
		echo -e "$str"
	fi

	echo -e "$str" >> $LOGFILE
}


debug ()
{
        str="[DEBUG] $@"
        if [ "$DEBUG" = "1" ]
        then
		if [ "$var_UI_TYPE" = dia ]
		then
			echo -e "$str" > $LOG
		else
			echo -e "$str"
		fi
		echo -e "$str" >> $LOGFILE
	fi
}


# taken from setup
printk()
{
    case $1 in
        "on")  echo 4 >/proc/sys/kernel/printk ;;
        "off") echo 0 >/proc/sys/kernel/printk ;;
    esac
}


# TODO: pass disks as argument to decouple backend logic
# Get a list of available disks for use in the "Available disks" dialogs. This
# will print the disks as follows, getting size info from hdparm:
#   /dev/sda: 640133 MBytes (640 GB)
#   /dev/sdb: 640135 MBytes (640 GB)
_getavaildisks()
{
    # NOTE: to test as non-root, stick in a 'sudo' before the hdparm call
    for i in $(finddisks); do echo -n "$i: "; hdparm -I $i | grep -F '1000*1000' | sed "s/.*1000:[ \t]*\(.*\)/\1/"; echo "\n"; done
}


ask_checklist () #TODO
{
	true
}



# TODO: we should have a wrapper around this function that keeps trying until the user entered a valid numeric?, maybe a wrapper that wraps all functions
# ask for a number.
# $1 question
# $2 lower limit (optional)
# $3 upper limit (optional)
# TODO: implement a default number
# echo's the number the user said
# returns 1 if the user cancelled or did not enter a numeric, 0 otherwise 
ask_number ()
{
	[ -z "$1" ] && die_error "ask_number needs a question!"
	[ -n "$2" ] && [[ $2 = *[^0-9]* ]] && die_error "ask_number \$2 must be a number! not $2"
	[ -n "$3" ] && [[ $3 = *[^0-9]* ]] && die_error "ask_number \$3 must be a number! not $3"
	[ "$var_UI_TYPE" = dia ] && { _dia_ask_number "$1" "$2" "$3" ; return $? ; }
	[ "$var_UI_TYPE" = cli ] && { _cli_ask_number "$1" "$2" "$3" ; return $? ; }
}

  
# ask the user to choose something
# $1 default item (set to 'no' for none)
# $2 title
# shift;shift; $@ list of options. first tag. then name. (eg tagA itemA "tag B" 'item B' )
# the response will be echoed to stdout. but also $ANSWER_OPTION will be set. take that because the former method seems to not work.
# $? if user cancelled. 0 otherwise
ask_option ()
{
	[ "$var_UI_TYPE" = dia ] && { _dia_ask_option "$@" ; return $? ; }
	[ "$var_UI_TYPE" = cli ] && { _cli_ask_option "$@" ; return $? ; }
}  


# ask the user a password. return is stored in $PASSWORD or $<TYPE>_PASSWORD
# $1 type (optional.  eg 'svn', 'ssh').
ask_password ()
{
	[ "$var_UI_TYPE" = dia ] && { _dia_ask_password "$@" ; return $? ; }
	[ "$var_UI_TYPE" = cli ] && { _cli_ask_password "$@" ; return $? ; }
}


# ask for a string.
# $1 question
# $2 default (optional)
# echo's the string the user gave.
# returns 1 if the user cancelled, 0 otherwise
ask_string ()
{
	[ -z "$1" ] && die_error "ask_string needs a question!"
	[ "$var_UI_TYPE" = dia ] && { _dia_ask_string "$1" "$2" ; return $? ; }
	[ "$var_UI_TYPE" = cli ] && { _cli_ask_string "$1" "$2" ; return $? ; }
}


# ask a yes/no question.
# $1 question
# returns 0 if response is yes/y (case insensitive).  1 otherwise
# TODO: support for default answer
ask_yesno ()
{
	[ -z "$1" ] && die_error "ask_yesno needs a question!"
	[ "$var_UI_TYPE" = dia ] && { _dia_ask_yesno "$@" ; return $? ; }
	[ "$var_UI_TYPE" = cli ] && { _cli_ask_yesno "$@" ; return $? ; }
}





# follow the progress of something by showing it's log, updating real-time
# $1 title
# $2 logfile
follow_progress ()
{
	[ -z "$1" ] && die_error "follow_progress needs a title!"
	[ -z "$2" ] && die_error "follow_progress needs a logfile to follow!"
	[ "$var_UI_TYPE" = dia ] && { _dia_follow_progress "$1" "$2" ; return $? ; }
	[ "$var_UI_TYPE" = cli ] && { _cli_follow_progress "$1" "$2" ; return $? ; }
}






### Internal functions, supposed to be only used internally in this library ###


# DIALOG() taken from setup
# an el-cheapo dialog wrapper
#
# parameters: see dialog(1)
# returns: whatever dialog did
_dia_DIALOG()
{
	dialog --backtitle "$TITLE" --aspect 15 "$@"
	return $?
}


_dia_ask_checklist () #TODO: implement this
{
	_dia_DIALOG --checklist "$1" $list
}


_dia_ask_number ()
{
	#TODO: i'm not entirely sure this works perfectly. what if user doesnt give anything or wants to abort?
	while true
	do
		str="$1"
		[ -n "$2" ] && str2="min $2"
		[ -n "$3" ] && str2="$str2 max $3"
		[ -n "$str2" ] && str="$str ( $str2 )"
		_dia_DIALOG --inputbox "$str" 8 65 "$4" 2>$ANSWER
		ret=$?
		ANSWER_NUMBER=`cat $ANSWER`
		if [[ $ANSWER_NUMBER = *[^0-9]* ]] #TODO: handle exit state
		then
			show_warning "$ANSWER_NUMBER is not a number! try again."
		else
			break
		fi
	done
	echo "$ANSWER_NUMBER"
	debug "_dia_ask_number: user entered: $ANSWER_NUMBER"
	[ -z "$ANSWER_NUMBER" ] && return 1
	return $?
}

_dia_ask_option ()
{
	DEFAULT=""
	[ "$1" != 'no' ] && DEFAULT="--default-item $1"
	[ -z "$2" ] && die_error "ask_option \$2 must be the title"
	[ -z "$6" ] && debug "_dia_ask_option args: $@" && die_error "ask_option makes only sense if you specify at least 2 things (with tag and name)"
 
 	DIA_MENU_TITLE=$2
 	shift 2
	_dia_DIALOG $DEFAULT --colors --title " $DIA_MENU_TITLE " --menu "$DIA_MENU_TEXT" 16 55 8 "$@" 2>$ANSWER
	ret=$?
	ANSWER_OPTION=`cat $ANSWER`
	echo $ANSWER_OPTION
	debug "dia_ask_option: User choose $ANSWER_OPTION"
	return $ret
}


_dia_ask_password ()
{
	if [ -n "$1" ]
	then
		type_l=`tr '[:upper:]' '[:lower:]' <<< $1`
		type_u=`tr '[:lower:]' '[:upper:]' <<< $1`
	else
		type_l=
		type_u=
	fi

	_dia_DIALOG --passwordbox  "Enter your $type_l password" 8 65 "$2" 2>$ANSWER
	ret=$?
	[ -n "$type_u" ] && read ${type_u}_PASSWORD < $ANSWER
	[ -z "$type_u" ] && read           PASSWORD < $ANSWER
	cat $ANSWER
	debug "_dia_ask_password: user entered <<hidden>>"
	return $ret
}


_dia_ask_string ()
{
	_dia_DIALOG --inputbox "$1" 8 65 "$2" 2>$ANSWER
	ret=$?
	ANSWER_STRING=`cat $ANSWER`
	echo $ANSWER_STRING
	debug "_dia_ask_string: user entered $ANSWER_STRING"
	return $ret
}


_dia_ask_yesno ()
{
	height=$((`echo -e "$1" | wc -l` +7))
	dialog --yesno "$1" $height 55 # returns 0 for yes, 1 for no
	ret=$?
	[ $ret -eq 0 ] && debug "dia_ask_yesno: User picked YES"
	[ $ret -gt 0 ] && debug "dia_ask_yesno: User picked NO"
	return $ret
}


_dia_follow_progress ()
{
	title=$1
	logfile=$2
	_dia_DIALOG --title "$1" --no-kill --tailboxbg "$2" 18 70 2>$ANSWER
}




_cli_ask_number ()
{
	#TODO: i'm not entirely sure this works perfectly. what if user doesnt give anything or wants to abort?
	while true
	do
		str="$1"
		[ -n "$2" ] && str2="min $2"
		[ -n "$3" ] && str2="$str2 max $3"
		[ -n "$str2" ] && str="$str ( $str2 )"
		echo "$str"
		read ANSWER_NUMBER
		if [[ $ANSWER_NUMBER = *[^0-9]* ]]
		then
			show_warning "$ANSWER_NUMBER is not a number! try again."
		else
			break
		fi
	done
	echo "$ANSWER_NUMBER"
	debug "cli_ask_number: user entered: $ANSWER_NUMBER"
	[ -z "$ANSWER_NUMBER" ] && return 1
	return 0
}


_cli_ask_option ()
{
	#TODO: strip out color codes
	#TODO: if user entered incorrect choice, ask him again
	DEFAULT=""
	[ "$1" != 'no' ] && DEFAULT=$1
	[ -z "$2" ] && die_error "ask_option \$2 must be the title"
	[ -z "$6" ] && debug "_cli_ask_option args: $@" && die_error "ask_option makes only sense if you specify at least 2 things (with tag and name)"

 	CLI_MENU_TITLE=$2
 	shift 2

	echo "$CLI_MENU_TITLE"
	while [ -n "$1" ]
	do
		echo "$1 ] $2"
		shift 2
	done
	echo "CANCEL ] CANCEL"
	[ -n "$DEFAULT" ] && echo -n " > [ $DEFAULT ] "
	[ -z "$DEFAULT" ] && echo -n " > "
	read ANSWER_OPTION
	[ -z "$ANSWER_OPTION" -a -n "$DEFAULT" ] && ANSWER_OPTION="$DEFAULT"
	debug "cli_ask_option: User choose $ANSWER_OPTION"
	echo "$ANSWER_OPTION"
	[ "$ANSWER_OPTION" = CANCEL ] && return 1
	return 0
}


_cli_ask_password ()
{
}


_cli_ask_string ()   #TODO: implement default answer
{
	echo -n "$@: "
	read ANSWER_STRING
	echo "$ANSWER_STRING"
	debug "cli_ask_string: User entered: $ANSWER_STRING"
	[ -z "$ANSWER_STRING" ] && return 1
	return 0
}


_cli_ask_yesno ()
{
	echo -n "$1 (y/n): "
	read answer
	answer=`tr '[:upper:]' '[:lower:]' <<< $answer`
	if [ "$answer" = y -o "$answer" = yes ]
	then
		debug "cli_ask_yesno: User picked YES"
		return 0
	else
		debug "cli_ask_yesno: User picked NO"
		return 1
	fi
}


_cli_follow_progress ()
{
	title=$1
	logfile=$2
	echo "Title: $1"
	tail -f $2
	#TODO: don't block anymore when it's done
}
