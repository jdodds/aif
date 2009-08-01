#!/bin/bash

# auto_network().
# configures network on host system according to installer settings
# if some variables are not set, we handle that transparantly
# $1 dhcp/fixed
# $2 http proxy (optional. defaults to '')
# $3 ftp proxy (optional. defaults to '')
target_configure_network()
{
	[ "$1" != dhcp -a "$1" != fixed ] && die_error "target_configure_network \$1 must be 'dhcp' or 'fixed'"
	PROXY_HTTP="$2"
	PROXY_FTP="$3"
	if [ "$1" = fixed ]; then
		sed -i "s#eth0=\"eth0#${INTERFACE:-eth0}=\"${INTERFACE:-eth0}#g"                      ${var_TARGET_DIR}/etc/rc.conf || return 1
		sed -i "s#${INTERFACE:-eth0} 192.168.0.2#${INTERFACE:-eth0} ${IPADDR:-192.168.0.2}#g" ${var_TARGET_DIR}/etc/rc.conf || return 1
		sed -i "s#netmask 255.255.255.0#netmask ${SUBNET:-255.255.255.0}#g"                   ${var_TARGET_DIR}/etc/rc.conf || return 1
		sed -i "s#broadcast 192.168.0.255#broadcast ${BROADCAST:-192.168.0.255}#g"            ${var_TARGET_DIR}/etc/rc.conf || return 1
		if [ -n "$GW" ]; then
			sed -i "s#gw 192.168.0.1#gw $GW#g"                                            ${var_TARGET_DIR}/etc/rc.conf || return 1
			sed -i "s#!gateway#gateway#g"                                                 ${var_TARGET_DIR}/etc/rc.conf || return 1
		fi
		if [ -n "$DNS" ]
		then
			echo "nameserver $DNS" >> ${var_TARGET_DIR}/etc/resolv.conf || return 1
		fi
	else
		sed -i "s#eth0=\"eth0.*#${INTERFACE:-eth0}=\"dhcp\"#g"                                ${var_TARGET_DIR}/etc/rc.conf || return 1
	fi
	sed -i "s#INTERFACES=(eth0)#INTERFACES=(${INTERFACE:-eth0})#g"                                ${var_TARGET_DIR}/etc/rc.conf || return 1

	if [ -n "$PROXY_HTTP" ]; then
		echo "export http_proxy=$PROXY_HTTP" >> ${var_TARGET_DIR}/etc/profile.d/proxy.sh || return 1
		chmod a+x ${var_TARGET_DIR}/etc/profile.d/proxy.sh || return 1
	fi

	if [ -n "$PROXY_FTP" ]; then
		echo "export ftp_proxy=$PROXY_FTP" >> ${var_TARGET_DIR}/etc/profile.d/proxy.sh || return 1
		chmod a+x ${var_TARGET_DIR}/etc/profile.d/proxy.sh || return 1
	fi
}
