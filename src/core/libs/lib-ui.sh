#!/bin/bash
# TODO: implement 'retry until user does it correctly' everywhere
# TODO: at some places we should check if $1 etc is only 1 word because we often depend on that
# TODO: standardize. eg everything $1= question/title, $2=default
# TODO: figure out something to make dia windows always big enough, yet fit nicely in the terminal


# Taken from setup.  we store dialog output in a file.  TODO: can't we do this with variables? ASKDEV
ANSWER=$RUNTIME_DIR/.dialog-answer
DIA_MENU_TEXT="Use the UP and DOWN arrows to navigate menus.  Use TAB to switch between buttons and ENTER to select."
DIA_SUCCESSIVE_ITEMS=$RUNTIME_DIR/.dia-successive-items

### Functions that your code can use. Cli/dialog mode is fully transparant.  This library takes care of it ###


# display error message and die
die_error ()
{
	debug "die_error: ERROR: $@"
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
                [ "${type}" = text ] && (cat $2 || die_error "Could not cat $2")
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
# $1 str
# $2 0/<listname> this infofy call is part of a successive list of things (eg repeat previous things, keep adding items to a list) (only needed for dia, cli does this by design).
#   You can keep several "lists of successive things" by grouping them with <listname>
#   this is somewhat similar to follow_progress.  Note that this list isn't cleared unless you set $3 to 1.  default 0. (optional).
# $3 0/1 this is the last one of the group of several things (eg clear buffer).  default 0. (optional)
infofy () #TODO: when using successive things, the screen can become full and you only see the old stuff, not the new
{
	successive=${2:-0}
	succ_last=${3:-0}
	debug "infofy: $1"
	if [ "$var_UI_TYPE" = dia ]
	then
		str="$1"
		if [ "$successive" != 0 ]
		then
			echo "$1" >> $DIA_SUCCESSIVE_ITEMS-$successive
			str=`cat $DIA_SUCCESSIVE_ITEMS-$successive`
		fi
		[ "$succ_last" = 1 ] && rm $DIA_SUCCESSIVE_ITEMS-$successive
		_dia_DIALOG --infobox "$str" 20 50
	else
		echo -e "$1"
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
		echo -e "$str" >$LOG
	fi

	[ "$LOG_TO_FILE" = 1 ] && echo -e "$str" >> $LOGFILE
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
			echo -e "$str" > $LOG
		fi
		[ "$LOG_TO_FILE" = 1 ] && echo -e "$str" >> $LOGFILE
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


# ask the user to make a selection from a certain group of things
# $1 question
# shift;shift; $@ list of options. first tag, then item then ON/OFF. if item == ^ or - it will not be shown in cli mode.
# for nostalgic reasons, you can set item to ^ for ON items and - for OFF items. afaik this doesn't have any meaning other then extra visual separation though
ask_checklist ()
{
	[ -z "$1" ] && die_error "ask_checklist needs a question!"
	[ -z "$4" ] && debug "ask_checklist args: $@" && die_error "ask_checklist makes only sense if you specify at least 1 thing (tag,item and ON/OFF switch)"
	[ "$var_UI_TYPE" = dia ] && { _dia_ask_checklist "$@" ; return $? ; }
	[ "$var_UI_TYPE" = cli ] && { _cli_ask_checklist "$@" ; return $? ; }
}


ask_datetime ()
{
	[ "$var_UI_TYPE" = dia ] && { _dia_ask_datetime "$@" ; return $? ; }
	[ "$var_UI_TYPE" = cli ] && { _cli_ask_datetime "$@" ; return $? ; }
}


# ask for a number.
# $1 question
# $2 lower limit (optional)
# $3 upper limit (optional)
# $4 default : TODO implement in cli
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
# $3 additional explanation (default: '')
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
# $3 exitcode to use when string is empty and there was no default, or default was ignored (1 default)
# echo's the string the user gave.
# returns 1 if the user cancelled, 0 otherwise
ask_string ()
{
	[ -z "$1" ] && die_error "ask_string needs a question!"
	[ "$var_UI_TYPE" = dia ] && { _dia_ask_string "$1" "$2" "$3"; return $? ; }
	[ "$var_UI_TYPE" = cli ] && { _cli_ask_string "$1" "$2" "$3"; return $? ; }
}


ask_timezone ()
{
	[ "$var_UI_TYPE" = dia ] && { _dia_ask_timezone "$@" ; return $? ; }
	[ "$var_UI_TYPE" = cli ] && { _cli_ask_timezone "$@" ; return $? ; }
}


# ask a yes/no question.
# $1 question
# $2 default answer yes/no (optional)
# returns 0 if response is yes/y (case insensitive).  1 otherwise
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


_dia_ask_checklist ()
{
	str=$1
	shift
	list=
	while [ -n "$1" ]
	do
		[ -z "$2" ] && die_error "no item given for element $1"
		[ -z "$3" ] && die_error "no ON/OFF switch given for element $1 (item $2)"
		[ "$3" != ON -a "$3" != OFF ] && die_error "element $1 (item $2) has status $3 instead of ON/OFF!"
		list="$list $1 $2 $3"
		shift 3
	done
	_dia_DIALOG --checklist "$str" 30 60 20 $list 2>$ANSWER
	ret=$?
	ANSWER_CHECKLIST=`cat $ANSWER`
	debug "_dia_ask_checklist: user checked ON: $ANSWER_CHECKLIST"
	return $ret
}


_dia_ask_datetime ()
{
	# display and ask to set date/time
	dialog --calendar "Set the date.\nUse <TAB> to navigate and arrow keys to change values." 0 0 0 0 0 2> $ANSWER || return 1
	local _date="$(cat $ANSWER)" # form like: 07/12/2008
	dialog --timebox "Set the time.\nUse <TAB> to navigate and up/down to change values." 0 0 2> $ANSWER || return 1
	local _time="$(cat $ANSWER)" # form like: 15:26:46
	debug "Date as specified by user $_date time: $_time"

	# DD/MM/YYYY hh:mm:ss -> MMDDhhmmYYYY.ss (date default format, set like date $ANSWER_DATETIME)  Not enabled because there is no use for it i think.
	# ANSWER_DATETIME=$(echo "$_date" "$_time" | sed 's#\(..\)/\(..\)/\(....\) \(..\):\(..\):\(..\)#\2\1\4\5\3\6#g')
	# DD/MM/YYYY hh:mm:ss -> YYYY-MM-DD hh:mm:ss ( date string format, set like date -s "$ANSWER_DATETIME")
	ANSWER_DATETIME="$(echo "$_date" "$_time" | sed 's#\(..\)/\(..\)/\(....\) \(..\):\(..\):\(..\)#\3-\2-\1 \4:\5:\6#g')"
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
			if [ -n "$3" -a $ANSWER_NUMBER -gt $3 ]
			then
				show_warning "$ANSWER_NUMBER is bigger then the maximum,$3! try again."
			elif [ -n "$2" -a $ANSWER_NUMBER -lt $2 ]
			then
				show_warning "$ANSWER_NUMBER is smaller then the minimum,$2! try again."
			else
				break
			fi
		fi
	done
	debug "_dia_ask_number: user entered: $ANSWER_NUMBER"
	[ -z "$ANSWER_NUMBER" ] && return 1
	return $ret
}


_dia_ask_option ()
{
	DEFAULT=""
	[ "$1" != 'no' ] && DEFAULT="--default-item $1"
	[ -z "$2" ] && die_error "ask_option \$2 must be the title"
	# $3 is optional more info
	[ -z "$5" ] && debug "_dia_ask_option args: $@" && die_error "ask_option makes only sense if you specify at least one option (with tag and name)" #nothing wrong with only 1 option.  it still shows useful info to the user
 
 	DIA_MENU_TITLE=$2
	EXTRA_INFO=$3
	shift 3
	_dia_DIALOG $DEFAULT --colors --title " $DIA_MENU_TITLE " --menu "$DIA_MENU_TEXT $EXTRA_INFO" 20 80 16 "$@" 2>$ANSWER
	ret=$?
	ANSWER_OPTION=`cat $ANSWER`
	debug "dia_ask_option: User choose $ANSWER_OPTION ($DIA_MENU_TITLE)"
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
	exitcode=${3:-1}
	_dia_DIALOG --inputbox "$1" 8 65 "$2" 2>$ANSWER
	ret=$?
	ANSWER_STRING=`cat $ANSWER`
	debug "_dia_ask_string: user entered $ANSWER_STRING"
	[ -z "$ANSWER_STRING" ] && return $exitcode
	return $ret
}


_dia_ask_timezone ()
{
	ANSWER_TIMEZONE=`tzselect` #TODO: implement nicer then this
}


_dia_ask_yesno ()
{
	height=$((`echo -e "$1" | wc -l` +7))
	str=$1
	#TODO: i think dialog doesnt support a default value for yes/no, so we need this workaround:
	[ -n "$2" ] && str="$str (default: $2)"
	dialog --yesno "$str" $height 55 # returns 0 for yes, 1 for no
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




_cli_ask_checklist ()
{
	str=$1
	shift
	output=
	while [ -n "$1" ]
	do
		[ -z "$2" ] && die_error "no item given for element $1"
		[ -z "$3" ] && die_error "no ON/OFF switch given for element $1 (item $2)"
		[ "$3" != ON -a "$3" != OFF ] && die_error "element $1 (item $2) has status $3 instead of ON/OFF!"
		item=$1
		[ "$2" != '-' -a "$2" != '^' ] && item="$1 ($2)"
		[ "$3" = ON  ] && ask_yesno "Enable $1 ?" yes && output="$output $1"
		[ "$3" = OFF ] && ask_yesno "Enable $1 ?" no  && output="$output $1" #TODO: for some reason, default is always N when asked to select packages
		shift 3
	done
	ANSWER_CHECKLIST=$output
	return 0
}


_cli_ask_datetime ()
{
	ask_string "Enter date [YYYY-MM-DD hh:mm:ss]"
	ANSWER_DATETIME=$ANSWER_STRING
	debug "Date as picked by user: $ANSWER_STRING"
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
	debug "cli_ask_number: user entered: $ANSWER_NUMBER"
	[ -z "$ANSWER_NUMBER" ] && return 1
	return 0
}


_cli_ask_option ()
{
	#TODO: strip out color codes
	#TODO: if user entered incorrect choice, ask him again
	DEFAULT=""
	[ "$1" != 'no' ] && DEFAULT=$1 #TODO: if user forgot to specify a default (eg all args are 1 pos to the left, we can end up in an endless loop :s)
	[ -z "$2" ] && die_error "ask_option \$2 must be the title"
	# $3 is optional more info
	[ -z "$5" ] && debug "_dia_ask_option args: $@" && die_error "ask_option makes only sense if you specify at least one option (with tag and name)" #nothing wrong with only 1 option.  it still shows useful info to the user

	MENU_TITLE=$2
	EXTRA_INFO=$3
	shift 3

	echo "$MENU_TITLE"
	[ -n "$EXTRA_INFO" ] && echo "$EXTRA_INFO"
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
	debug "cli_ask_option: User choose $ANSWER_OPTION ($MENU_TITLE)"
	[ "$ANSWER_OPTION" = CANCEL ] && return 1
	return 0
}


_cli_ask_password ()
{
	if [ -n "$1" ]
	then
		type_l=`tr '[:upper:]' '[:lower:]' <<< $1`
		type_u=`tr '[:lower:]' '[:upper:]' <<< $1`
	else
		type_l=
		type_u=
	fi

	echo -n "Enter your $type_l password: "
	stty -echo
	[ -n "$type_u" ] && read ${type_u}_PASSWORD
	[ -z "$type_u" ] && read PASSWORD
	stty echo
	echo
}


# $3 -z string behavior: always take default if applicable, but if no default then $3 is the returncode (1 is default)
_cli_ask_string ()
{
	exitcode=${3:-1}
	echo "$1: "
	[ -n "$2" ] && echo "(Press enter for default.  Default: $2)"
	echo -n ">"
	read ANSWER_STRING
	debug "cli_ask_string: User entered: $ANSWER_STRING"
	if [ -z "$ANSWER_STRING" ]
	then
		if [ -n "$2" ]
		then
			ANSWER_STRING=$2
		else
			return $exitcode
		fi
	fi
	return 0
}


_cli_ask_timezone ()
{
	ANSWER_TIMEZONE=`tzselect`
}


_cli_ask_yesno ()
{
	[ -z "$2"    ] && echo -n "$1 (y/n): "
	[ "$2" = yes ] && echo -n "$1 (Y/n): "
	[ "$2" = no  ] && echo -n "$1 (y/N): "

	read answer
	answer=`tr '[:upper:]' '[:lower:]' <<< $answer`
	if [ "$answer" = y -o "$answer" = yes ] || [ -z "$answer" -a "$2" = yes ]
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
