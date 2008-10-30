#!/bin/sh

donetwork() {
	INTERFACE=
	S_DHCP=
	ifaces=$(ifconfig -a | egrep "Ethernet" | cut -d' ' -f1 | sed 's|$| _|g')
	if [ "$ifaces" = "" ]; then
		DIALOG --yesno "Cannot find any ethernet interfaces. You probably haven't loaded\nyour network module yet.  You have two options:\n\n  1) Probe for the correct module now.\n  2) Switch to another VC (ALT-F2) and load your module\n     with the modprobe command, then switch back here (ALT-F1)\n     and continue.\n\nIf you know which module you need, you should do Step 2 and\nselect NO below.  If you don't know which module you need,\nchoose Step 1 by selecting YES below.\n\nProbe for network module?" 18 70
		if [ $? -eq 0 ]; then
			probenic
		if [ $? -gt 0 ]; then
			return 1
		fi
		fi
		ifaces=$(ifconfig -a | egrep "Ethernet" | cut -d' ' -f1 | sed 's|$| _|g')
		if [ "$ifaces" = "" ]; then
			DIALOG --msgbox "No network interfaces available." 0 0
			return 1
		fi
	fi
	while [ "$INTERFACE" = "" ]; do
		DIALOG --msgbox "Available Ethernet Interfaces:\n$(ifconfig -a | egrep "Ethernet" | sed 's# #_#g')\n\nIf your ethernet interface is not listed,\n1) Probe for the correct module now.\n2) Switch to another VC (ALT-F2) and load your module with\n   the modprobe command, then switch back here (ALT-F1)\n" 0 0
		dialog --backtitle "$TITLE" --extra-button --extra-label "Probe" --ok-label "Select" --menu "Select a network interface" 14 55 7 $ifaces 2>$ANSWER
		case $? in
			1) return 1 ;;
			0) INTERFACE=$(cat $ANSWER) ;;
			*) probenic ;;
		esac
		ifaces=$(ifconfig -a | egrep "Ethernet" | cut -d' ' -f1 | sed 's|$| _|g')
	done
	DIALOG --yesno "Do you want to use DHCP?" 0 0
	if [ $? -eq 0 ]; then
		DIALOG --infobox "Please wait.  Polling for DHCP server on $INTERFACE..." 0 0
		dhcpcd $INTERFACE >$LOG 2>&1 || DIALOG --msgbox "Failed to run dhcpcd." 0 0 || return 1
		sleep 10
		if [ ! $(ifconfig $INTERFACE | grep 'inet addr:') ]; then
			DIALOG --msgbox "DHCP request failed." 0 0 || return 1
		fi
		S_DHCP=1
	else
		NETPARAMETERS=""
		while [ "$NETPARAMETERS" = "" ]; do
			DIALOG --inputbox "Enter your IP address" 8 65 "192.168.0.2" 2>$ANSWER || return 1
			IPADDR=$(cat $ANSWER)
			DIALOG --inputbox "Enter your netmask" 8 65 "255.255.255.0" 2>$ANSWER || return 1
			SUBNET=$(cat $ANSWER)
			DIALOG --inputbox "Enter your broadcast" 8 65 "192.168.0.255" 2>$ANSWER || return 1
			BROADCAST=$(cat $ANSWER)
			DIALOG --inputbox "Enter your gateway (optional)" 8 65 "192.168.0.1" 8 65 2>$ANSWER || return 1
			GW=$(cat $ANSWER)
			DIALOG --inputbox "Enter your DNS server IP" 8 65 "192.168.0.1" 2>$ANSWER || return 1
			DNS=$(cat $ANSWER)
			DIALOG --inputbox "Enter your HTTP proxy server, for example:\nhttp://name:port\nhttp://ip:port\nhttp://username:password@ip:port\n\n Leave the field empty if no proxy is needed to install." 16 65 "" 2>$ANSWER || return 1
			PROXY_HTTP=$(cat $ANSWER)
			DIALOG --inputbox "Enter your FTP proxy server, for example:\nhttp://name:port\nhttp://ip:port\nhttp://username:password@ip:port\n\n Leave the field empty if no proxy is needed to install." 16 65 "" 2>$ANSWER || return 1
			PROXY_FTP=$(cat $ANSWER)
			DIALOG --yesno "Are these settings correct?\n\nIP address:         $IPADDR\nNetmask:            $SUBNET\nGateway (optional): $GW\nDNS server:         $DNS\nHTTP proxy server:  $PROXY_HTTP\nFTP proxy server:   $PROXY_FTP" 0 0
			case $? in
				1) ;;
				0) NETPARAMETERS="1" ;;
			esac
		done
		ifconfig $INTERFACE $IPADDR netmask $SUBNET broadcast $BROADCAST up >$LOG 2>&1 || DIALOG --msgbox "Failed to setup $INTERFACE interface." 0 0 || return 1
		if [ "$GW" != "" ]; then
			route add default gw $GW >$LOG 2>&1 || DIALOG --msgbox "Failed to setup your gateway." 0 0 || return 1
		fi
		if [ "$PROXY_HTTP" = "" ]; then
			unset http_proxy
		else
			export http_proxy=$PROXY_HTTP
		fi
		if [ "$PROXY_FTP" = "" ]; then
			unset ftp_proxy
		else
			export ftp_proxy=$PROXY_FTP
		fi
		echo "nameserver $DNS" >/etc/resolv.conf
	fi
	### Missing Proxy Configuration
	DIALOG --msgbox "The network is configured." 0 0
	S_NET=1
}

probenic() {
	workdir="$PWD"
	DIALOG --infobox "Looking for a matching ethernet module.  Please wait..." 0 0
	printk off

	cd /lib/modules/$(uname -r)/kernel/drivers/net
	if [ $? -gt 0 ]; then
		DIALOG --msgbox "No ethernet modules were found!" 0 0
		printk on
		cd "$workdir"
		return 1
	fi
	# modules with no modalias exported! status kernel 2.6.18
	NOTDETECTABLE="hp ne de4x5 wd cs89x0 eepro smc9194 seeq8005 ni52 ni65 ac3200 smc-ultra at1700 hp-plus depca eexpress 82596 de600 eth16i de620 lance ewrk3 e2100 lp486e 3c501 3c503 3c505 3c507 3c509 3c515 myri10ge"
	for mod in ${NOTDETECTABLE}; do
		modprobe $mod >/dev/null 2>&1
	done

	ifconfig -a | egrep "Ethernet" >/dev/null 2>&1
	if [ $? -gt 0 ]; then
		DIALOG --msgbox "No matching ethernet modules found." 0 0
	else
		DIALOG --msgbox "Probe succeeded.  Your network module is loaded." 0 0
	fi

	printk on
	cd "$workdir"
}

