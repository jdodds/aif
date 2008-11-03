#!/bin/sh
# TODO: lot's of implementation work still open in this library. especially the dialog stuff


# Taken from setup.  we store dialog output in a file.  TODO: can't we do this with variables?
ANSWER="/home/arch/fifa/runtime/.dialog-answer"



### Functions that your code can use. Cli/dialog mode is fully transparant.  This library takes care of it ###


# ask the user a password. return is stored in $PASSWORD or $<TYPE>_PASSWORD
# $1 type (optional.  eg 'svn', 'ssh').
ask_password ()
{
	[ "$var_UI_TYPE" = dia ] && { _dia_ask_password "$@" ; return $? ; }
	[ "$var_UI_TYPE" = cli ] && { _cli_ask_password "$@" ; return $? ; }
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


# ask for a string.
# $1 question
# echo's the string the user gave.
# returns 1 if the user cancelled, 0 otherwise
ask_string ()
{
	[ -z "$1" ] && die_error "ask_string needs a question!"
	[ "$var_UI_TYPE" = dia ] && { _dia_ask_string "$@" ; return $? ; }
	[ "$var_UI_TYPE" = cli ] && { _cli_ask_string "$@" ; return $? ; }
}


# TODO: we should have a wrapper around this function that keeps trying until the user entered a valid numeric?
# ask for a number.
# $1 question
# $2 lower limit (optional)
# $3 upper limit (optional)
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
# TODO: exact implementation, which arguments etc?
ask_option ()
{
	[ "$var_UI_TYPE" = dia ] && { _dia_ask_option "$@" ; return $? ; }
	[ "$var_UI_TYPE" = cli ] && { _cli_ask_option "$@" ; return $? ; }
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


# taken from setup
printk()
{
    case $1 in
        "on")  echo 4 >/proc/sys/kernel/printk ;;
        "off") echo 0 >/proc/sys/kernel/printk ;;
    esac
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


# geteditor(). taken from original setup code. prepended dia_ because power users just export $EDITOR on the cmdline.
# prompts the user to choose an editor
# sets EDITOR global variable
#
# TODO: clean this up
_dia_get_editor() {
    _dia_DIALOG --menu "Select a Text Editor to Use" 10 35 3 \
        "1" "nano (easier)" \
        "2" "vi" 2>$ANSWER   
    case $(cat $ANSWER) in   
        "1") EDITOR="nano" ;;
        "2") EDITOR="vi" ;;  
        *)   EDITOR="nano" ;;
    esac
}

# TODO: pass disks as argument to decouple backend logic
# Get a list of available disks for use in the "Available disks" dialogs. This
# will print the disks as follows, getting size info from hdparm:
#   /dev/sda: 640133 MBytes (640 GB)
#   /dev/sdb: 640135 MBytes (640 GB)
_dia_getavaildisks()
{
    # NOTE: to test as non-root, stick in a 'sudo' before the hdparm call
    for i in $(finddisks); do echo -n "$i: "; hdparm -I $i | grep -F '1000*1000' | sed "s/.*1000:[ \t]*\(.*\)/\1/"; echo "\n"; done
}


_dia_follow_progress ()
{
	title=$1
	logfile=$2
	_dia_DIALOG --title "$1" --no-kill --tailboxbg "$2" 18 70 2>$ANSWER
}


_dia_ask_yesno ()
{
	dialog --yesno "$1" 10 55 # returns 0 for yes, 1 for no
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

_cli_ask_yesno ()
{
	echo -n "$1 (y/n): "
	read answer
	answer=`tr '[:upper:]' '[:lower:]' <<< $answer`
	if [ "$answer" = y -o "$answer" = yes ]
	then
		return 0
	else
		return 1
	fi
}


_cli_ask_string ()   
{
	echo -n "$@: "
	read answ
	echo "$answ"
	[ -z "$answ" ] && return 1
	return 0
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
		read answ
		if [[ $answ = *[^0-9]* ]]
		then
			show_warning "$answ is not a number! try again."
		else
			break
		fi
	done
	echo "$answ"
	[ -z "$answ" ] && return 1
	return 0
}
	

_cli_ask_option ()
{
	die_error "_cli_ask_option Not yet implemented"
}


_cli_follow_progress ()
{
	title=$1
	logfile=$2
	echo "Title: $1"
	tail -f $2
}

