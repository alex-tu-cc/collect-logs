#!/bin/bash

LOGS=/var/log/local/check-hw-change.log
set -x

log(){
    [ ! -e $LOGS ] && mkdir -p /var/log/local
    echo "$1" >> $LOGS
}

# noticifican should be issued after some delay, otherwise it will not shows on screen.
notify_user(){
    [ $# == 0 ] && return
    local xuser_display_pairs=($(who | sed 's/[(|)]/ /g' | awk '{print $1 " " $5}' | grep ":"))
    local i=0
    for(( i=0; i < ${#xuser_display_pairs[@]}; i+=2));
    do
        XAUTHORITY=/home/${xuser_display_pairs[$i]}/.Xauthority DISPLAY=${xuser_display_pairs[$((i+1))]} notify-send -u critical "$1"
    done
    wall "$1"
}

USER_HOME=/home/$(cat /usr/share/collect-logs/config)
LOGS_FOLDER=$USER_HOME/collect-logs
if [ ! "$( lspci -vvvnn | md5sum - | cut -d ' ' -f 1 )" == "$(md5sum $LOGS_FOLDER/lspci-vvvnn.log | cut -d ' ' -f 1 )" ]; then
    notify_user "pci hw changed!! please collect-logs again.";
    exit 0
fi
if [ ! "$( lsusb -v | md5sum - | cut -d ' ' -f 1 )" == "$(md5sum $LOGS_FOLDER/lsusb-v.log | cut -d ' ' -f 1 )" ]; then
    notify_user "usb hw changed!! please collect-logs again.";
    exit 0
fi
log "check done.."

