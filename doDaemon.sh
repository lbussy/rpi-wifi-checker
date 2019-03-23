#!/bin/bash

# This file is part of LBussy's Raspberry Pi WiFi Checker (rpi-wifi-checker).
# Copyright (C) 2019 Lee C. Bussy (@LBussy)

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

# Global constant declarations
declare THISSCRIPT SCRIPTLOC RUNSCRIPT DAEMONNAME RUNAS URL SCRIPTURL

############
### Init
############

init() {
    # Change to current dir (assumed to be in a repo) so we can get the script info
    THISSCRIPT="doDaemon.sh"
    SCRIPTLOC="/usr/local/bin"
    RUNSCRIPT="checkWiFi.sh"
    DAEMONNAME="wificheck"
    SCRIPTURL="https://raw.githubusercontent.com/lbussy/rpi-wifi-checker/master/checkWiFi.sh"
    RUNAS="root"
    URL="wifi.brewpiremix.com"
    CMDLINE="curl -L $URL | sudo bash"
    SCRIPTNAME="${THISSCRIPT%%.*}"
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
### Make sure command is running with sudo
############

checkroot() {
    local retval
    if [[ "$EUID" -ne 0 ]]; then
        sudo -n true 2> /dev/null
        retval="$?"
        if [ "$retval" -eq 0 ]; then
            echo -e "\nNot running as root, relaunching correctly.\n"
            sleep 2
            eval "$CMDLINE"
            exit "$?"
        else
            # sudo not available, give instructions
            echo -e "\nThis script must be run with root privileges."
            echo -e "Enter the following command as one line:"
            echo -e "$CMDLINE" 1>&2
            exit 1
        fi
    fi
}

############
### --help and --version functionality
############

# usage outputs to stdout the --help usage message.

usage() {
    echo -e "\n$SCRIPTNAME usage: $CMDLINE"
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
### Install script
############

install_script() {
    local overwrite
    if [ -f "$SCRIPTLOC/$RUNSCRIPT" ]; then
        echo -e "\nTarget script $RUNSCRIPT already exists in $SCRIPTLOC." > /dev/tty
        while true; do
            read -rp "Do you want to overwrite? [Y/n]: " yn < /dev/tty
            case "$yn" in
                '' ) overwrite=1; break ;;
                [Yy]* ) overwrite=1; break ;;
                [Nn]* ) break ;;
                * ) echo "Enter [Y]es or [n]o." ; sleep 1 ; echo ;;
            esac
        done
        if [ "$overwrite" -ne 1 ]; then
            return
        fi
    fi
    echo -e "\nInstalling $RUNSCRIPT script to $SCRIPTLOC."
    curl -o "$SCRIPTLOC/$RUNSCRIPT" "$SCRIPTURL"
    chmod 744 "$SCRIPTLOC/$RUNSCRIPT"
}

############
### Create systemd unit file
### Required:
###   scriptName - Name of script to run under Bash
###   daemonName - Name to be used for Unit
###   userName - Context under which daemon shall be run
############

createdaemon () {
    local scriptName daemonName userName unitFile overwrite
    scriptName="$SCRIPTLOC/$1 -d"
    daemonName="${2,,}"
    userName="$3"
    unitFile="/etc/systemd/system/$daemonName.service"
    if [ -f "$unitFile" ]; then
        echo -e "\nUnit file $daemonName.service already exists in /etc/systemd/system." > /dev/tty
        while true; do
            read -rp "Do you want to overwrite? [Y/n]: " yn < /dev/tty
            case "$yn" in
                '' ) overwrite=1; break ;;
                [Yy]* ) overwrite=1; break ;;
                [Nn]* ) break ;;
                * ) echo "Enter [Y]es or [n]o." ; sleep 1 ; echo ;;
            esac
        done
        if [ "$overwrite" -ne 1 ]; then
            return
        else
            echo -e "\nStopping $daemonName daemon.";
            systemctl stop "$daemonName";
            echo -e "Disabling $daemonName daemon.";
            systemctl disable "$daemonName";
            echo -e "Removing unit file $unitFile";
            rm "$unitFile"
        fi
    fi
    echo -e "\nCreating unit file for $daemonName."
    {
        echo -e "[Unit]"
        echo -e "Description=Service for: $daemonName"
        echo -e "Documentation=https://github.com/lbussy/rpi-wifi-checker"
        echo -e "After=multi-user.target network.target"
        echo -e "\n[Service]"
        echo -e "Type=simple"
        echo -e "Restart=on-failure"
        echo -e "RestartSec=1"
        echo -e "User=$userName"
        echo -e "Group=$userName"
        echo -e "ExecStart=/bin/bash $scriptName"
        echo -e "SyslogIdentifier=$daemonName"
        echo -e "\n[Install]"
        echo -e "WantedBy=multi-user.target network.target"
    }  > "$unitFile"
    chown root:root "$unitFile"
    chmod 0644 "$unitFile"
    echo -e "Reloading systemd config."
    systemctl daemon-reload
    echo -e "Enabling $daemonName daemon."
    eval "systemctl enable $daemonName"
    echo -e "Starting $daemonName daemon."
    eval "systemctl restart $daemonName"
}

############
### Print banner
############

banner(){
    echo -e "\n***Script $THISSCRIPT $1.***"
}

############
### Main function
############

main() {
    init "$@"
    checkroot "$@"
    help_ver "$@"
    banner "starting"
    install_script
    createdaemon "$RUNSCRIPT" "$DAEMONNAME" "$RUNAS"
    banner "complete"
}

main "$@" && exit 0
