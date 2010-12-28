#!/bin/bash

# configures network on host system according to installer settings
# if some variables are not set, we handle that transparantly
# however, at least $DHCP must be set, so we know what do to
# we assume that you checked whether networking has been setup before calling us
target_configure_network()
{
	source $RUNTIME_DIR/aif-network-settings 2>/dev/null || return 1
	if [ "$DHCP" = 0 ] ; then
		sed -i "s/#eth0=\"eth0/eth0=\"eth0/g"                                                 ${var_TARGET_DIR}/etc/rc.conf || return 1
		sed -i "s/^eth0=\"dhcp/#eth0=\"dhcp/g"                                                ${var_TARGET_DIR}/etc/rc.conf || return 1
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
		sed -i "s/^eth0=\"eth0/#eth0=\"eth0/g"                                                ${var_TARGET_DIR}/etc/rc.conf || return 1
		sed -i "s/#eth0=\"dhcp/eth0=\"dhcp/g"                                                 ${var_TARGET_DIR}/etc/rc.conf || return 1
		sed -i "s#eth0=\"dhcp#${INTERFACE:-eth0}=\"dhcp#g"                                    ${var_TARGET_DIR}/etc/rc.conf || return 1
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
