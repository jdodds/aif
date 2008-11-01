#!/bin/bash

# auto_network(). taken from setup
# configures network on host system according to installer
# settings if user wishes to do so
#
auto_network()
{
    # exit if network wasn't configured in installer
    if [ $S_NET -eq 0 ]; then
        return 1
    fi

    ask_yesno "Do you want to use the network settings from the installer in rc.conf and resolv.conf?\n\nIf you used Proxy settings, they will be written to /etc/profile.d/proxy.sh" || return 1

    if [ $S_DHCP -ne 1 ]; then
        sed -i "s#eth0=\"eth0#$INTERFACE=\"$INTERFACE#g" ${TARGET_DIR}/etc/rc.conf
        sed -i "s# 192.168.0.2 # $IPADDR #g" ${TARGET_DIR}/etc/rc.conf
        sed -i "s# 255.255.255.0 # $SUBNET #g" ${TARGET_DIR}/etc/rc.conf
        sed -i "s# 192.168.0.255\"# $BROADCAST\"#g" ${TARGET_DIR}/etc/rc.conf
        sed -i "s#eth0)#$INTERFACE)#g" ${TARGET_DIR}/etc/rc.conf
        if [ "$GW" != "" ]; then
            sed -i "s#gw 192.168.0.1#gw $GW#g" ${TARGET_DIR}/etc/rc.conf
            sed -i "s#!gateway#gateway#g" ${TARGET_DIR}/etc/rc.conf
        fi
        echo "nameserver $DNS" >> ${TARGET_DIR}/etc/resolv.conf
    else
        sed -i "s#eth0=\"eth0.*#$INTERFACE=\"dhcp\"#g" ${TARGET_DIR}/etc/rc.conf
    fi
    if [ "$PROXY_HTTP" != "" ]; then
        notify "export http_proxy=$PROXY_HTTP" >> ${TARGET_DIR}/etc/profile.d/proxy.sh;
        chmod a+x ${TARGET_DIR}/etc/profile.d/proxy.sh
    fi
    if [ "$PROXY_FTP" != "" ]; then
        notify "export ftp_proxy=$PROXY_FTP" >> ${TARGET_DIR}/etc/profile.d/proxy.sh;
        chmod a+x ${TARGET_DIR}/etc/profile.d/proxy.sh
    fi
}
