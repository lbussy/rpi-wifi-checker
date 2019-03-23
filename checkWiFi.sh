#!/bin/bash

# Copyright (C) 2018  Lee C. Bussy (@LBussy)

# This file is part of LBussy's Raspberry Pi WiFi Checker (rpi-wifi-checker).
#
# Raspberry Pi WiFi Checker is free software: you can redistribute it and/or
# modify it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the # License, or (at your
# option) any later version.
#
# Raspberry Pi WiFi Checker is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General
# Public License for more details.
#
# You should have received a copy of the GNU General Public License along with
# Raspberry Pi WiFi Checker. If not, see <https://www.gnu.org/licenses/>.

### User-editable settings ###
# Time (in seconds) in between tests when running in CRON or Daemon mode
declare -i LOOP
LOOP=600
# Total number of times to try and contact the router if first packet fails
# After this the interface is restarted
declare -i MAX_FAILURES
MAX_FAILURES=3
# Time (in seconds)to wait between failed attempts contacting the router
declare -i INTERVAL
INTERVAL=10
# Log file location
declare LOG_LOC
LOG_LOC="/var/log"
# Global variables declaration - No changes past this point
declare STDOUT STDERR SCRIPTPATH THISSCRIPT SCRIPTNAME WLAN INTERACT
declare -i fails=0

############
### Init
############

init() {
    # Change to current dir (assumed to be in a repo) so we can get the git info
    pushd . &> /dev/null || exit 1
    SCRIPTPATH="$( cd "$(dirname "$0")" || exit ; pwd -P )"
    cd "$SCRIPTPATH" || exit 1 # Move to where the script is
    
    THISSCRIPT="$(basename "$0")"
    SCRIPTNAME="${THISSCRIPT%%.*}"
    STDOUT="$SCRIPTNAME.log"
    STDERR="$SCRIPTNAME.log"
    
    # Get wireless lan device name and gateway
    WLAN=$(cat /proc/net/wireless | perl -ne '/(\w+):/ && print $1')
}

############
### Functions to catch/display errors during execution
############

warn() {
    local fmt="$1"
    command shift 2>/dev/null
    echo -e "$fmt"
    echo -e "${@}"
    echo -e "\n*** ERROR ERROR ERROR ERROR ERROR ***"
    echo -e "-------------------------------------"
    echo -e "See above lines for error message."
    echo -e "Setup NOT completed.\n"
}

die () {
    local st="$?"
    warn "$@"
    exit "$st"
}

############
### Check privilges and permissions
############

check_root() {
    local retval
    if [[ $EUID -ne 0 ]]; then
        sudo -n true 2> /dev/null
        retval="$?"
        if [[ "$retval" == "0" ]]; then
            echo -e "\nNot runing as root, relaunching correctly."
            sleep 2
            eval "sudo bash $SCRIPTPATH/$THISSCRIPT $*"
            exit $?
        else
            # sudo not available, give instructions
            echo -e "\nThis script must be run as root: sudo $SCRIPTPATH/$THISSCRIPT $*" 1>&2
            exit 1
        fi
    fi
}

############
### --help and --version functionality
############

# func_usage outputs to stdout the --help usage message.

func_usage () {
    echo -e "$THISSCRIPT"
    Usage: sudo ./"$THISSCRIPT"
}

# func_version outputs to stdout the --version message.
func_version () {
cat << EOF

"$THISSCRIPT"

Copyright (C) 2019 Lee C. Bussy (@LBussy)
This is free software: you can redistribute it and/or modify it
under the terms of the GNU General Public License as published
by the Free Software Foundation, either version 3 of the License,
or (at your option) any later version.
<https://www.gnu.org/licenses/>

There is NO WARRANTY, to the extent permitted by law.
EOF
}

help_ver() {
    local arg
    arg="$1"
    if [ -n "$arg" ]; then
        arg="${1//-}" # Strip out all dashes
        if [[ "$arg" == "h"* ]]; then func_usage; exit 0; fi
        if [[ "$arg" == "v"* ]]; then func_version; exit 0; fi
    fi
}

############
### Function: log() to add timestamps and log level
############

log() {
    local -i lvl
    local msg now name level
    lvl="$1" && local msg="$2"
    now=$(date '+%Y-%m-%d %H:%M:%S')
    name="${THISSCRIPT%.*}" && name=${name^^}
    case "$lvl" in
        2 )
            level="WARN"
        ;;
        3 )
            level="ERROR"
        ;;
        * )
            level="INFO"
        ;;
    esac
    logmsg="$now $name $level: $msg"
    # If we are interacive, send to tty (straight echo will break func here)
    [ "$INTERACT" == true ] && echo -e "$logmsg" > /dev/tty && return
    # Send "INFO to stdout else (WARN and ERROR) send to stderr
    if [ "$level" = "INFO" ]; then
        echo "$logmsg" >> "$LOG_LOC/$STDOUT"
    else
        echo "$logmsg" >> "$LOG_LOC/$STDERR"
    fi
}

############
### Return current wireless LAN gateway
############

func_getgateway() {
    local gateway
    # Get gateway address
    gateway=$(/sbin/ip route | grep -m 1 default | awk '{ print $3 }')
    ### Sometimes network is so hosed, gateway IP is missing from route
    if [ -z "$gateway" ]; then
        # Try to restart interface and get gateway again
        func_restart
        gateway=$(/sbin/ip route | grep -m 1 default | awk '{ print $3 }')
    fi
    echo "$gateway"
}

############
### Perform ping test
############

func_ping() {
    local retval
    while [ "$fails" -lt "$MAX_FAILURES" ]; do
        [ "$fails" -gt 0 ] && sleep "$INTERVAL"
        # Try pinging
        ping -c 1 -I "$WLAN" "$gateway" > /dev/null
        retval="$?"
        if [ "$retval" -eq 0 ]; then
            #log 1 "Successful ping of $gateway."
            fails="$MAX_FAILURES"
            echo true
        else
            # If that didn't work...
            ((fails++))
            log 2 "$fails failure(s) to reach $gateway."
            if [ "$fails" -ge "$MAX_FAILURES" ]; then
                echo false
            fi
        fi
    done
}

############
### Restart WLAN
############

func_restart() {
    ### Restart wireless interface
    log 3 "Router unreachable. Restarting $WLAN."
    ip link set dev "$WLAN" down
    ip link set dev "$WLAN" up
}

############
### Determine if we are running in CRON or Daemon mode
############

func_getinteract() {
    # See if we are interactive (no cron or daemon (-d) mode)
    pstree -s $$ | grep -q bash && cron=false || cron=true
    [[ ! "${1//-}" == "d"* ]] && daemon=false || daemon=true
    if [[ "$daemon" == false ]] && [[ "$cron" == false ]]; then
        echo true
    else
        echo false
    fi
}

############
### Print banner
############

func_banner(){
    echo -e "\n***Script $THISSCRIPT $1.***"
}

############
### Keep checking the adapter
############

check_loop() {
    local gateway
    local -i before after delay
    before=0
    after=0
    delay=0
    while :
    do
        if [ -z "$WLAN" ]; then
            log 3 "Unable to determine wireless interface name.  Exiting."
            exit 1
        fi
        gateway=$(func_getgateway)
        if [ -z "$gateway" ]; then
            log 3 "Unable to determine gateway.  Exiting."
            exit 1
        fi
        before=$(date +%s)
        if [ "$(func_ping "$gateway")" == true ]; then
            fails=0
        else
            func_restart
            fails=0
        fi
        after=$(date +%s)
        (("delay=$LOOP-($after-$before)"))
        [ "$delay" -lt "1" ] && delay=10
        sleep "$delay"
    done
}

############
### Check the adapter for one go-around
############

check_once() {
    if [ -z "$WLAN" ]; then
        log 3 "Unable to determine wireless interface name.  Exiting."
        exit 1
    fi
    gateway=$(func_getgateway)
    if [ -z "$gateway" ]; then
        log 3 "Unable to determine gateway.  Exiting."
        exit 1
    fi
    if [ "$(func_ping "$gateway")" == true ]; then
        fails=0
    else
        func_restart
        fails=0
    fi
}

############
### Main loop
############

main() {
    init "$@"
    check_root "$@"
    help_ver "$@"
    INTERACT=$(func_getinteract "$@")
    iwconfig wlan0 power off # Turn off power management for WiFi
    # If we're interactive, just run it once
    if [ "$INTERACT" == true ]; then
        func_banner "starting"
        check_once # Check adapter for only one set of events
        func_banner "complete"
    else
        check_loop # Check adapter forever
    fi
}

main "$@" && exit 0
