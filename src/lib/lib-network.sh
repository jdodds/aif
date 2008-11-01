#!/bin/bash

# auto_network(). taken from setup
# configures network on host system according to installer
# settings if user wishes to do so
#
auto_network()
{
	if [ $S_DHCP -ne 1 ]; then
		sed -i "s#eth0=\"eth0#$INTERFACE=\"$INTERFACE#g" ${var_TARGET_DIR}/etc/rc.conf
		sed -i "s# 192.168.0.2 # $IPADDR #g" ${var_TARGET_DIR}/etc/rc.conf
		sed -i "s# 255.255.255.0 # $SUBNET #g" ${var_TARGET_DIR}/etc/rc.conf
		sed -i "s# 192.168.0.255\"# $BROADCAST\"#g" ${var_TARGET_DIR}/etc/rc.conf
		sed -i "s#eth0)#$INTERFACE)#g" ${var_TARGET_DIR}/etc/rc.conf
		if [ "$GW" != "" ]; then
			sed -i "s#gw 192.168.0.1#gw $GW#g" ${var_TARGET_DIR}/etc/rc.conf
			sed -i "s#!gateway#gateway#g" ${var_TARGET_DIR}/etc/rc.conf
		fi
		echo "nameserver $DNS" >> ${var_TARGET_DIR}/etc/resolv.conf
	else
		sed -i "s#eth0=\"eth0.*#$INTERFACE=\"dhcp\"#g" ${var_TARGET_DIR}/etc/rc.conf
	fi

	if [ "$PROXY_HTTP" != "" ]; then
		echo "export http_proxy=$PROXY_HTTP" >> ${var_TARGET_DIR}/etc/profile.d/proxy.sh;
		chmod a+x ${var_TARGET_DIR}/etc/profile.d/proxy.sh
	fi

	if [ "$PROXY_FTP" != "" ]; then
		echo "export ftp_proxy=$PROXY_FTP" >> ${var_TARGET_DIR}/etc/profile.d/proxy.sh;
		chmod a+x ${var_TARGET_DIR}/etc/profile.d/proxy.sh
	fi
}
