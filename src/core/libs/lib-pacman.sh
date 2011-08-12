#!/bin/bash

# target_prepare_pacman():
# configures pacman to run from live environment, but working on target system.
# syncs for the first time on destination system
#
# $@ repositories to enable (optional. default: core)
# returns: 1 on error
target_prepare_pacman() {   
	[ "$var_PKG_SOURCE_TYPE" = "cd" ] && local serverurl="${var_FILE_URL}"
	[ "$var_PKG_SOURCE_TYPE" = "net" ] && local serverurl="${var_SYNC_URL}"

	[ -z "$1" ] && repos=core
	[ -n "$1" ] && repos="$@"
	# Setup a pacman.conf in /tmp
	cat << EOF > /tmp/pacman.conf
[options]
CacheDir = ${var_TARGET_DIR}/var/cache/pacman/pkg
CacheDir = /src/core/pkg
Architecture = auto
EOF

for repo in $repos
do
	#TODO: this is a VERY, VERY dirty hack.  we fall back to net for any non-core repo because we only have core on the CD. also user maybe didn't pick a mirror yet
	if [ "$repo" != core ]
	then
		add_pacman_repo target ${repo} "Include = $var_MIRRORLIST" || return 1
	else
		# replace literal '$repo' in the serverurl string by "$repo" where $repo is our variable.
		add_pacman_repo target ${repo} "Server = ${serverurl/\$repo/$repo}" || return 1
	fi
done
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


# $1 target/runtime
# $2 repo name
# $3 string
add_pacman_repo ()
{
	[ "$1" != runtime -a "$1" != target ] && die_error "add_pacman_repo needs target/runtime argument"
	[ -z "$3" ] && die_error "target_add_repo needs \$2 repo-name and \$3 string (eg Server = ...)"
	[ "$1" = target  ] && conf=/tmp/pacman.conf
	[ "$1" = runtime ] && conf=/etc/pacman.conf
	cat << EOF >> $conf

[${2}]
${3}
EOF
}

# not sorted
list_package_groups ()
{
	$PACMAN_TARGET -Sg
}


# List the packages in one or more repos or groups. output is one or more lines, each line being like this:
# <repo/group name> packagename [version, if $1=repo]
# lines are sorted by packagename
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
	PACKAGE_INFO=`LANG=C $PACMAN_TARGET -Si "$@" | awk '/^Name/{ printf("%s ",$3) } /^Version/{ printf("%s ",$3) } /^Group/{ printf("%s", $3) } /^Description/{ for(i=3;i<=NF;++i) printf(" %s",$i); printf ("\n")}'`
}

target_configure_mirrorlist () {
	# add installer-selected mirror to the top of the mirrorlist, unless it's already at the top. previously added mirrors are kept (a bit lower), you never know..
	if [ "$var_PKG_SOURCE_TYPE" = "net" -a -n "${var_SYNC_URL}" ]; then
		if ! grep "^Server =" -m 1 "${var_TARGET_DIR}/$var_MIRRORLIST" | grep "${var_SYNC_URL}"
		then
			debug 'PACMAN PROCEDURE' "Adding choosen mirror (${var_SYNC_URL}) to ${var_TARGET_DIR}/$var_MIRRORLIST"
			mirrorlist=`awk "BEGIN { printf(\"# Mirror used during installation\nServer = "${var_SYNC_URL}"\n\n\") } 1 " "${var_TARGET_DIR}/$var_MIRRORLIST"` || return $?
			echo "$mirrorlist" > "${var_TARGET_DIR}/$var_MIRRORLIST" || return $?
		fi
	fi
	return 0
}

