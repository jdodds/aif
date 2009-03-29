#!/bin/bash

# auto_network(). taken from setup. edited
# configures network on host system according to installer
# settings if user wishes to do so
# $1 dhcp/fixed
# $2 http proxy (optional. defaults to '')
# $3 ftp proxy (optional. defaults to '')
# TODO: autonetwork must be a wrapper that checks $PROXY_HTTP, $PROXY_FTP and $S_DHCP and calls this function
target_configure_network()
{
	[ "$1" != dhcp -a "$1" != fixed ] && die_error "target_configure_network \$1 must be 'dhcp' or 'fixed'"
	PROXY_HTTP="$2"
	PROXY_FTP="$3"
	if [ "$1" = fixed ]; then
		sed -i "s#eth0=\"eth0#$INTERFACE=\"$INTERFACE#g"          ${var_TARGET_DIR}/etc/rc.conf
		sed -i "s#$INTERFACE 192.168.0.2#$INTERFACE $IPADDR#g"    ${var_TARGET_DIR}/etc/rc.conf
		sed -i "s#netmask 255.255.255.0#netmask $SUBNET#g"        ${var_TARGET_DIR}/etc/rc.conf
		sed -i "s#broadcast 192.168.0.255#broadcast $BROADCAST#g" ${var_TARGET_DIR}/etc/rc.conf
		if [ "$GW" != "" ]; then
			sed -i "s#gw 192.168.0.1#gw $GW#g"                ${var_TARGET_DIR}/etc/rc.conf
			sed -i "s#!gateway#gateway#g"                     ${var_TARGET_DIR}/etc/rc.conf
		fi
		echo "nameserver $DNS" >> ${var_TARGET_DIR}/etc/resolv.conf
	else
		sed -i "s#eth0=\"eth0.*#$INTERFACE=\"dhcp\"#g"            ${var_TARGET_DIR}/etc/rc.conf
	fi
	sed -i "s#INTERFACES=(eth0)#INTERFACES=($INTERFACE)#g"    ${var_TARGET_DIR}/etc/rc.conf

	if [ "$PROXY_HTTP" != "" ]; then
		echo "export http_proxy=$PROXY_HTTP" >> ${var_TARGET_DIR}/etc/profile.d/proxy.sh;
		chmod a+x ${var_TARGET_DIR}/etc/profile.d/proxy.sh
	fi

	if [ "$PROXY_FTP" != "" ]; then
		echo "export ftp_proxy=$PROXY_FTP" >> ${var_TARGET_DIR}/etc/profile.d/proxy.sh;
		chmod a+x ${var_TARGET_DIR}/etc/profile.d/proxy.sh
	fi
}
