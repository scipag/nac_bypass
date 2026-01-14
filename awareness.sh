#!/bin/bash

# -----
# Name: awareness.sh
# scip AG - Michael Schneider
# -----

## Variables
VERSION="0.1.1-1746786622"

BRINT=br0 # bridge interface
SWINT=eth0 # network interface plugged into switch
COMPINT=eth1 # network interface plugged into victim machine
STATE_INTERFACE=0
STATE_COUNTER=0
THRESHOLD_UP=3
THRESHOLD_DOWN=5
TIMER="5s"

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")

## display usage hints
Usage() {
  echo -e "$0 v$VERSION usage:"
  echo "    -h          display this help"
  echo "    -1 <eth>    network interface plugged into switch"
  echo "    -2 <eth>    network interface plugged into victim machine"
  exit 0
}

## display version info
Version() {
  echo -e "$0 v$VERSION"
  exit 0
}

## Check if we got all needed parameters
CheckParams() {
  while getopts ":1:2:g:t:T:hRS" opts
    do
      case "$opts" in
        "1")
          SWINT=$OPTARG
          # --- use both this argument for current and subsequent script ---
          passthrough_args+=("-${opts}" "${OPTARG}")
          ;;
        "2")
          COMPINT=$OPTARG
          # --- use both this argument for current and subsequent script ---
          passthrough_args+=("-${opts}" "${OPTARG}")
          ;;
        # --- Options to be passed through without parameter ---
        R|S)
          passthrough_args+=("-${opts}")
          ;;
        # --- Options to be passed through with a parameter ---
        g|t|T)
          passthrough_args+=("-${opts}" "${OPTARG}")
          ;;
        "h")
          Usage
          ;;
        *)
          Usage
          ;;
      esac
  done
}

## Main
CheckParams $@

## Run Initial Configuration
bash "${SCRIPT_DIR}/nac_bypass_setup.sh" -a -i "${passthrough_args[@]}"

## Loop
while true
do
    NETWORK_STATE_INTERFACE=`cat "/sys/class/net/$COMPINT/carrier"`
 
    if [ "$NETWORK_STATE_INTERFACE" -ne "$STATE_INTERFACE" ]; then

        STATE_COUNTER=0

        if [ "$NETWORK_STATE_INTERFACE" -eq 1 ]; then
            echo "[!] $COMPINT \(Target supplicant interface\) is now up!"
        else
            echo "[!] $COMPINT \(Target supplicant interface\) is now down!"
        fi
    else

        if [ "$STATE_COUNTER" -eq "$THRESHOLD_UP" ] && [ "$NETWORK_STATE_INTERFACE" -eq 1 ]; then
            echo "[!!] Set new config"
            bash "${SCRIPT_DIR}/nac_bypass_setup.sh" -a -c "${passthrough_args[@]}"
 
        elif [ "$STATE_COUNTER" -eq "$THRESHOLD_DOWN" ] && [ "$NETWORK_STATE_INTERFACE" -eq 0 ]; then
            echo "[!!] Reset config"
            bash "${SCRIPT_DIR}/nac_bypass_setup.sh" -a -r
            bash "${SCRIPT_DIR}/nac_bypass_setup.sh" -a -i "${passthrough_args[@]}"
        fi

        echo "[*] Waiting"
        ((STATE_COUNTER++))
    fi

    STATE_INTERFACE=$NETWORK_STATE_INTERFACE
    sleep $TIMER
done