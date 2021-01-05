#!/bin/bash

# Copyright (c) 2021 Lee C. Bussy

# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:

# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

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
# Reboot on failure
REBOOT=false
# ** No changes past this point **
# Global constants declaration
declare STDOUT STDERR SCRIPTPATH THISSCRIPT SCRIPTNAME WLAN INTERACT
# Global variables declaration
declare -i fails=0

############
### Init
############

init() {
    # Change to current dir (assumed to be in a repo) so we can get the script info
    pushd . &> /dev/null || exit 1
    SCRIPTPATH="$( cd "$(dirname "$0")" || exit ; pwd -P )"
    THISSCRIPT="$(basename "$0")"
    SCRIPTNAME="${THISSCRIPT%%.*}"
    STDOUT="$SCRIPTNAME.log"
    STDERR="$SCRIPTNAME.err"
    # Get wireless lan device name and gateway
    WLAN="$(iw dev | awk '$1=="Interface"{print $2}')"
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

die() {
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

# usage outputs to stdout the --help usage message.

usage() {
    echo -e "\n$SCRIPTNAME usage: sudo $SCRIPTPATH/$THISSCRIPT"
}

# version outputs to stdout the --version message.
version() {
cat << EOF

"$SCRIPTNAME" Copyright (C) 2019 Lee C. Bussy (@LBussy)
This program comes with ABSOLUTELY NO WARRANTY.

This is free software, and you are welcome to redistribute it
under certain conditions.

There is NO WARRANTY, to the extent permitted by law.
EOF
}

help_ver() {
    local arg
    arg="$1"
    if [ -n "$arg" ]; then
        arg="${arg//-}" # Strip out all dashes
        if [[ "$arg" == "h"* ]]; then usage; exit 0; fi
        if [[ "$arg" == "v"* ]]; then version; exit 0; fi
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
    # If we are interacive, send to tty (straight echo will break func here)
    [ "$INTERACT" == true ] && echo -e "$level: $msg" > /dev/tty && return
    logmsg="$now $name $level: $msg"
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

getgateway() {
    local gateway
    # Get gateway address
    gateway=$(/sbin/ip route | grep -m 1 'default' | awk '{ print $3 }')
    ### Sometimes network is so hosed, gateway IP is missing from route
    if [ -z "$gateway" ]; then
        # Try to restart interface and get gateway again
        restart
        gateway=$(/sbin/ip route | grep -m 1 'default' | awk '{ print $3 }')
    fi
    echo "$gateway"
}

############
### Perform ping test
############

do_ping() {
    local retval gateway
    gateway="$1"
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

restart() {
    ### Restart wireless interface
    ip link set dev "$WLAN" down
    ip link set dev "$WLAN" up
}

############
### Determine if we are running in CRON or Daemon mode
############

getinteract() {
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

banner(){
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
            if [ "$REBOOT" == true ]; then
                log 3 "Unable to determine wireless interface name.  Rebooting."
                reboot
            else
                log 3 "Unable to determine wireless interface name.  Exiting."
                exit 1
            fi
        fi
        gateway=$(getgateway)
        if [ -z "$gateway" ]; then
            exit 1
            if [ "$REBOOT" == true ]; then
                log 3 "Unable to determine gateway.  Rebooting."
                reboot
            else
                log 3 "Unable to determine gateway.  Exiting."
                exit 1
            fi
        fi
        before=$(date +%s)
        if [ "$(do_ping "$gateway")" == false ]; then
            log 3 "Gateway unreachable. Restarting $WLAN."
            restart
        fi
        fails=0
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
    local gateway
    if [ -z "$WLAN" ]; then
        log 3 "Unable to determine wireless interface name.  Exiting."
        exit 1
    fi
    gateway=$(getgateway)
    if [ -z "$gateway" ]; then
        log 3 "Unable to determine gateway.  Exiting."
        exit 1
    fi
    if [ "$(do_ping "$gateway")" == true ]; then
        log 1 "Ping of gateway $gateway successful."
        fails=0
    else
        log 3 "Gateway unreachable. Restarting $WLAN."
        restart
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
    INTERACT=$(getinteract "$@")
    iw dev wlan0 set power_save off # Turn off power management for WiFi
    # If we're interactive, just run it once
    if [ "$INTERACT" == true ]; then
        banner "starting"
        check_once # Check adapter for only one set of events
        banner "complete"
    else
        check_loop # Check adapter forever
    fi
}

main "$@" && exit 0
