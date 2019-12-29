# bypass/nac_bypass

## Requirements
The basic requirement for an NAC bypass is access to a device that has already been authenticated. This device is used to log into the network and then smuggle in network packages from a different device. This involves placing the attacker’s system between the network switch and the authenticated device. One way to do this is with a Raspberry Pi and two network adapters.

## Installation

The NACkered script and our nac_bypass_setup.sh solution were written and tested on Debian-based Linux distributions, but both should be executable on other Linux distributions as well. The following software packages are required:

1. Install tools, on Debian-like distros: `bridge-utils` `macchanger` `arptables` `ebtables` `iptables` `net-tools` `tcpdump`
2. Load kernel module: `modprobe br_netfilter`
3. Persist kernel module: `br_netfilter`into `/etc/modules`

For arptables, iptables and ebtables, make sure not to use Netfilter xtable tools (nft), or the script will not work as desired.

The nac_bypass_setup.sh script has the following parameters:

```
nac_bypass_setup.sh v0.6.4 usage:
    -1 <eth>    network interface plugged into switch
    -2 <eth>    network interface plugged into victim machine
    -a          autonomous mode
    -c          start connection setup only
    -g <MAC>    set gateway MAC address (GWMAC) manually
    -h          display this help
    -i          start initial setup only
    -r          reset all settings
    -R          enable port redirection for Responder.py
    -S          enable port redirection for OpenSSH and start the service
```

The parameters `-1` and `-2` define which network adapters will be used. You can also edit them directly in the script: `-a` suppresses the output of the script’s log and debugging information and no manual interaction is required when running it. The parameters `-R` and `-S` activate port forwarding for the use of SSH and Responder. The parameters `-c`, `-i` and `-r` only initiate certain sequences within the script.

## Use

The legitimate device, client, is not initially connected to the network switch. Now the script is started on the attacker device, bypass. Bypass and attacker are one physical device. The attacker figure symbolizes actions carried out by the attacker on the NAC bypass device. The first step is the initial configuration: To start with, unwanted services, such as NetworkManager, are stopped, IPv6 is disabled and any DNS configurations are initialized. Next, the bridge is configured and started. To ensure bridging works as desired, the kernel has to be configured to forward EAPOL frames. Without this adjustment, 802.1X authentication will not be carried out.

Once the configuration is complete, the network cables can be connected and the bridge’s switch side is now enabled as a passive forwarder. The bypass device forwards all network traffic back and forth between the switch and the client but cannot send any packets itself. The client should now be authenticated with the network switch and can log into the network successfully.

All network traffic passes through the bridge and can be analyzed accordingly. This is done to capture Kerberos and SMB packets with tcpdump – as these are normally found in several places on a Windows network, making it possible to see the network configuration, such as the client’s IP and MAC address. This information is used to automatically configure the client side of the bridge. However, the bypass’s connection to the network remains blocked to ensure that network packets from the attacker device find their way onto the network and are detected. If packets from the attacker are sent onto the network later, an ebtables rule will overwrite the MAC address, meaning that the packets will appear as if they originated from the client. The same procedure is implemented using iptables rules at IP level, so that outgoing TCP, UDP and ICMP packets also have the same IP address as the client. Finally, the attacker is able to connect to the network and can carry out actions from their own device.

If port forwarding has been enabled for SSH and Responder, the bridge forwards all requests for the respective ports to the attacker’s services. From there, a Responder instance can be run to carry out multicast poisoning and to perform authentication for protocols such as SMB, FTP, or HTTP. This instance can be reached from the network using the client’s IP address.

## Bypassing NAC in an infinite loop

The scenario described above is only possible if the attacker is in possession of a legitimate device. But if the attacker only has physical access to a building and its rooms and does not have their own device, additional steps are necessary. If a room has a network installation – e.g. a meeting room or shared workspace – the bypass device can still be installed. However, it must be noted that the NAC bypass setup is agile and can respond to changes such as switching devices. With a shared workspace, for example, User1 connects their device to the docking station in the morning. The hidden bypass device installs its configuration on User1’s device. As soon as they leave the shared workspace, the bypass device resets to the initial state and waits for new devices. If User2 connects their device to the docking station, the bypass device is no longer allowed to run with User1’s configuration. Instead, it must use User2’s credentials to connect to the network.

The bypass device therefore checks network connectivity at certain intervals and then responds to status changes and then invokes the appropriate NAC bypass procedure. We created a simple implementation of this check with the awareness.sh script, which checks an adapter’s network status every five seconds and responds accordingly when the status changes.

First, the basic setup for the NAC bypass is configured. Next, a loop is started to monitor the state of the network interface. The second part of the NAC bypass setup is then executed as soon as the interface is activated. If the network connection is lost, the configuration is reset and initialized. Configurable cycles are also set between the status changes to avoid premature configuration changes when network connectivity is lost temporarily, for example. This script allows a bypass device to respond to device switching; this can be done without any manual intervention over an extended period of time by placing the device in an appropriate room.

## Next Steps

The awareness.sh script responds to status changes and modifies the NAC bypass configuration accordingly. All other actions must be carried out manually at present using the likes of SSH on the device. This SSH service is only available on the victim’s network, however. One of the next steps is the planned integration of an additional management interface using a WLAN or cellular network adapter. This adapter could then be used to establish an autonomous connection, allowing the attacker to access the device without having to be physically on the premises or network. The awareness script could also be enhanced to include modules that ensure more autonomy. For example, communication via a command and control server (C2) can be configured to receive commands or extract data.