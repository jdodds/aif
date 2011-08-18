#!/bin/bash

# target_prepare_pacman():
# configures pacman to run from live environment, but working on target system.
# syncs for the first time on destination system
# Enables all reposities specified by TARGET_REPOSITORIES
# returns: 1 on error
target_prepare_pacman() {   
	# Setup a pacman.conf in /tmp
	echo "[options]" > /tmp/pacman.conf
	echo "CacheDir = ${var_TARGET_DIR}/var/cache/pacman/pkg" >> /tmp/pacman.conf
	# construct real directory names from pseudonyms like (2 array elements):
	# core file:///repo/$repo/$arch
	# ideally, we would query those from pacman (which is also who interprets
	# these), but pacman does not support something like that, so we do it a bit
	# uglier.  See https://bugs.archlinux.org/task/25568
	arch=$(uname -m)
	for line in $(echo ${TARGET_REPOSITORIES[@]} | tr ' ' '\n' | grep -B 1 'file://' | grep -v '\-\-'); do
		if ! echo $line | grep -q '^file://'; then
			repo=$line
		else
			cachedir=$(echo $line | sed -e "s#file://##;s#\$repo#$repo#;s#\$arch#$arch#")
			[ -d $cachedir ] || die_error "You specified $line (->$cachedir) as a directory to be used as repository, but it does not exist"
			echo "CacheDir = $cachedir" >> /tmp/pacman.conf
		fi
	done
	echo "Architecture = auto" >> /tmp/pacman.conf

    for i in `seq 0 $((${#TARGET_REPOSITORIES[@]}/2-1))`
	do
		repo=${TARGET_REPOSITORIES[$(($i*2))]}
		location=${TARGET_REPOSITORIES[$(($i*2+1))]}
		add_pacman_repo target $repo $location || return 1
	done

	if [ -n "$MIRROR" ]; then
		configure_mirrorlist runtime || return 1
	fi

	# Set up the necessary directories for pacman use
	for dir in var/cache/pacman/pkg var/lib/pacman
	do
		if [ ! -d "${var_TARGET_DIR}/$dir" ]
		then
			mkdir -m 755 -p "${var_TARGET_DIR}/$dir" || return 1
		fi
	done

	inform "Refreshing package database..."
	$PACMAN_TARGET -Sy >$LOG 2>&1 || return 1
	return 0
}


# $1 target/runtime
list_pacman_repos ()
{
	[ "$1" != runtime -a "$1" != target ] && die_error "list_pacman_repos needs target/runtime argument"
	[ "$1" = target  ] && conf=/tmp/pacman.conf
	[ "$1" = runtime ] && conf=/etc/pacman.conf
	grep '\[.*\]' $conf | grep -v options | grep -v '^#' | sed 's/\[//g' | sed 's/\]//g'
}

# returns all repositories you could possibly use (core, extra, testing, community, ...)
list_possible_repos ()
{
	grep -B 1 'Include = /etc/' /etc/pacman.conf | grep '\[' | sed 's/#*\[\(.*\)\]/\1/'
}


# $1 target/runtime
# $2 repo name
# $3 string
# automatically knows that if $3 contains the word 'mirrorlist', it should save
# as 'Include = $3', otherwise as 'Server = $3' (for both local and remote)
add_pacman_repo ()
{
	[ "$1" != runtime -a "$1" != target ] && die_error "add_pacman_repo needs target/runtime argument"
	[ -z "$3" ] && die_error "target_add_repo needs \$2 repo-name and \$3 string (eg Server = ...)"
	repo=$2
	if echo "$3" | grep -q 'mirrorlist'; then
		location="Include = $3"
	else
		location="Server = $3"
	fi
	[ "$1" = target  ] && conf=/tmp/pacman.conf
	[ "$1" = runtime ] && conf=/etc/pacman.conf
	cat << EOF >> $conf

[$repo]
$location
EOF
}

# not sorted
list_package_groups ()
{
	$PACMAN_TARGET -Sg
}


# List the packages in one or more repos or groups. output is one or more lines, each line being like this:
# <repo/group name> packagename [version, if $1=repo] [installed]
# lines are sorted by packagename, per repo, repos in the order you gave them to us.
# $1 repo or group
# $2 one or more repo or group names
list_packages ()
{
	[ "$1" = repo -o "$1" = group ] || die_error "list_packages \$1 must be repo or group. not $1!"
	[ "$1" = repo  ] && $PACMAN_TARGET -Sl $2
	[ "$1" = group ] && $PACMAN_TARGET -Sg $2
}

# find out the group to which one or more packages belong
# arguments: packages
# output format: multiple lines, each line like:
# <pkgname> <group>
# order is the same as the input
which_group ()
{
	PACKAGE_GROUPS=`LANG=C $PACMAN_TARGET -Si "$@" | awk '/^Name/{ printf("%s ",$3) } /^Group/{ print $3 }'`
}

# get group and packagedesc for packages
# arguments: packages
# output format: multiple lines, each line like:
# <pkgname> <version> <group> <desc>
# order is the same as the input
# note that space is used as separator, but desc is the only thing that will contain spaces.
pkginfo ()
{
	PACKAGE_INFO=`LANG=C $PACMAN_TARGET -Si "$@" | awk '/^Name/{ printf("%s ",$3) } /^Version/{ printf("%s ",$3) } /^Group/{ printf("%s", $3) } /^Description/{ for(i=3;i<=NF;++i) printf(" %s",$i); printf ("\n")}' | awk '!x[$1]++'`
}

# $1 target/runtime
configure_mirrorlist () {
	local file
	[ "$1" != runtime -a "$1" != target ] && die_error "configure_mirrorlist needs target/runtime argument"
	# add installer-selected mirror to the top of the mirrorlist, unless it's already at the top. previously added mirrors are kept (a bit lower), you never know..
	[ "$1" = 'runtime' ] && file="$var_MIRRORLIST"
	[ "$1" = 'target' ] && file="${var_TARGET_DIR}/$var_MIRRORLIST"
	if [ -n "$MIRROR" ]; then
		if ! grep "^Server =" -m 1 "$file" | grep "$MIRROR"
		then
			debug 'PACMAN PROCEDURE' "Adding choosen mirror ($MIRROR) to $file"
			mirrorlist=`awk "BEGIN { printf(\"# Mirror selected during installation\nServer = "$MIRROR"\n\n\") } 1 " "$file"` || return $?
			echo "$mirrorlist" > "$file" || return $?
		fi
	fi
	return 0
}

