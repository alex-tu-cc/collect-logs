#!/bin/bash
LOGS_FOLDER="$HOME/collect-logs"
set -x
set -e
main() {
# record the user name for check-hw-changes.sh notification.
    echo $USER | sudo tee /usr/share/collect-logs/config
# prepare folder
    cd "$LOGS_FOLDER"
    git config --get user.name || git config --global user.name "$0"
    git config --get user.email || git config --global user.email "$0@example.com"
    if [ ! -d ".git" ]; then
        git init
    else
        rm -rf $LOGS_FOLDER/*
#        git clean -x -d -f
#        git checkout . || true
    fi
    cd "$OLDPWD"

# call log collector one by one.
# prepare env parameter, so that collecting could be triggerred by ssh.
    [[ -z $DISPLAY ]] && export DISPLAY=:0

    lspci -vvvnn > "$LOGS_FOLDER/lspci-vvvnn.log"
    lspci -t > "$LOGS_FOLDER/lspci-t.log"
    sudo lsusb -v > "$LOGS_FOLDER/lsusb-v.log"
    lsmod > "$LOGS_FOLDER/lsmod.log"
    [[ -e `which dkms` ]] &&  dkms status > "$LOGS_FOLDER/dkms-status.log"
    rfkill list > "$LOGS_FOLDER/rfkill-l.log"
    hciconfig > "$LOGS_FOLDER/hciconfig.log"
    udevadm info -e > "$LOGS_FOLDER/udevadm-info-e.log"
    uname -a > "$LOGS_FOLDER/uname-a.log"
    uname -a > "$LOGS_FOLDER/uname-a.log"
    lsblk -a > "$LOGS_FOLDER/lsblk-a.log"
    sudo ldconfig -v > "$LOGS_FOLDER/ldconfig-v.log"
    sudo lshw > "$LOGS_FOLDER/lshw.log"
    mkdir -p "$LOGS_FOLDER/proc"
    cat /proc/cmdline > "$LOGS_FOLDER/proc/cmdline"
    xrandr > "$LOGS_FOLDER/xrandr" || touch "$LOGS_FOLDER/xrandr.failed"
    xrandr --listproviders > "$LOGS_FOLDER/xrandr--listproviders" || touch "$LOGS_FOLDER/xrandr.failed"

    get_nvme_info
    get_kernel_information
    [[ "$FULL" == "1" ]] && get_kernel_debug_files
    get_audio_logs
    get_nvidia_logs
    get_wwan_card_logs
    get_network_manager_logs
    get_manifest_from_recovery || true
    get_xinput_logs
    get_system_logs
    get_etc_default_files
    get_bios_info

    dpkg -l > "$LOGS_FOLDER/dpkg-l.log"
    ps -ef > "$LOGS_FOLDER/ps-ef.log"

# commit logs.
    cd "$LOGS_FOLDER"
    git add .
    git commit -m "collected from $(cat /sys/devices/virtual/dmi/id/product_name) + BIOS $(grep -m 1 Version dmidecode.log)"



}

get_nvme_info()
{
   if  mount | grep nvme;then
        [[ ! -x $(which nvme) ]] && sudo apt-get install -y nvme-cli
        sudo nvme get-feature -f 0x0c -H /dev/nvme0n1 > "$LOGS_FOLDER/nvme_info.log"
    fi

}
get_kernel_information()
{
    # get glxinfo
    glxinfo > "$LOGS_FOLDER/glxinfo.log" || touch "$LOGS_FOLDER/glxinfo.log.failed"
    # get kernel config
    local local_kernel_build=/lib/modules/`uname -r`/build/
    mkdir -p $LOGS_FOLDER/$local_kernel_build
    cp $local_kernel_build/.config $LOGS_FOLDER/$local_kernel_build/config
    # get alll module info
    lsmod | grep -v Module | grep -v nvidia | cut -d ' ' -f1 | xargs modinfo > $LOGS_FOLDER/modinfo.log
    lsmod | grep nvidia && modinfo nvidia-375 >> $LOGS_FOLDER/modinfo.log || true
}

get_kernel_debug_files()
{
    for file in $(find /sys/kernel/debug/);do test -f $file && stat -c %A $file | grep r >> /dev/null &&  collect_kernel_debug_file $file; done
    for file in $(find /sys/devices);do test -f $file && stat -c %A $file | grep r >> /dev/null &&  collect_kernel_debug_file $file; done
}

# $1 target
collect_kernel_debug_file()
{
    # filter out the size which more than 1M

   # filter out the size which more than 1M
   #if  ! `ls -lh  $1| awk '{print $5}' | grep M`; then
   if [[ $(stat -c %s $1) < 10000 ]]; then
        echo "$1" | grep "tracing\|dynamic_debug" && return
        [[ $(basename "$1") == "i915_ggptt_info" ]] && return
        [[ $(basename "$1") == "registers" ]] && return
        [[ $(basename "$1") == "mem_value" ]] && return
        [[ $(basename "$1") == "access" ]] && return
        [[ $(basename "$1") == "amdgpu_gtt" ]] && return
        [[ $(basename "$1") == "amdgpu_vram" ]] && return
        echo "$1" | cpio -p --make-directories "$LOGS_FOLDER" && cat "$1" > "$LOGS_FOLDER/$1"&
    fi
}

get_bios_info() {
#    local bios_logs_folder=$LOGS_FOLDER/bios
#    mkdir -p "$bios_logs_folder"
#    sudo dmidecode > "$bios_logs_folder/dmidecode.log"
    sudo dmidecode > "$LOGS_FOLDER/dmidecode.log"
    [[ ! -x $(which acpidump) ]] && sudo apt-get install -y acpidump
    sudo acpidump > "$LOGS_FOLDER/acpi.log"
# refer to https://github.com/Bumblebee-Project/bbswitch
    local tmp_folder=$(mktemp -d)
    pushd $tmp_folder
        git clone git://github.com/Lekensteyn/acpi-stuff.git --depth 1
        cd acpi-stuff/acpi_dump_info
        make
        sudo make load || true
        cat /proc/acpi/dump_info | tee $LOGS_FOLDER/acpi_used_handles.log
    popd

}

get_audio_logs() {
    [[ -e $(which alsa-info.sh) ]] && alsa-info.sh --stdout > "$LOGS_FOLDER/alsa-info.log" || true
}

get_nvidia_logs() {
    [[ -x $(which nvidia-bug-report.sh) ]] && sudo nvidia-bug-report.sh --output-file "$LOGS_FOLDER/nvidia-bug-report" || true
    if [ -e /etc/X11/xorg.conf ];then
        mkdir -p /etc/X11
        cp /etc/X11/xorg.conf "$LOGS_FOLDER/"
    fi
}

get_network_manager_logs() {
    nmcli dev > "$LOGS_FOLDER/nmcli-dev.log"
    nmcli co > "$LOGS_FOLDER/nmcli-co.log"
    # [TODO]
    # http://manpages.ubuntu.com/manpages/precise/man5/NetworkManager.conf.5.html
    # or there should be a way to raise debug level by send dbus message.

}

get_wwan_card_logs() {
    # check modemmanager works first.
    if systemctl show --property=SubState ModemManager.service | grep running; then
        #get modem hardware information
        if [[ -e $(which mmcli) ]]; then
            rm -f "$LOGS_FOLDER/mmcli.log"
            local modem_index=$(mmcli -L | grep Modem | awk -F'/| ' '{ print $6}')
            printf "\n\$mmcli\n"; mmcli -L; printf "\n\$mmcli -m $modem_index "; mmcli -m $modem_index >> "$LOGS_FOLDER/mmcli.log" || true
        fi
        # check firmware version
        [[ !  -e $(which mbimcli) ]] && sudo apt-get install -y libmbim-utils
        if ls /dev/cdc-wdm* ;then
            for node in /dev/cdc-wdm*; do
                sudo mbimcli -d "$node" --query-device-caps --verbose > "$LOGS_FOLDER/mbimcli-d-$(basename $node).log" || true
            done
        fi
    else
        touch "$LOGS_FOLDER/ModemManager.service.dead"
    fi
}

get_manifest_from_recovery() {
    mount | grep "\/ type ext4" | grep sda
    if [[ $? == 0 ]]; then
        sudo mount /dev/sda2 /mnt
    else
        sudo mount /dev/nvme0n1p2 /mnt
    fi
    cp /mnt/bto.xml "$LOGS_FOLDER"
    sudo umount /mnt
    # check mount | grep "\/ type ext4" to know if currently use sda or nvme?
    # mount /dev/${recovery-partition} /mnt | cat /mnt/bto.xml
}

get_system_logs() {
    dmesg > "$LOGS_FOLDER/dmesg.log"
    cat dmesg | sed 's/[0-9]*\.[0-9]*\]//g' > "$LOGS_FOLDER/dmesg.stripped"
    find /var/log/syslog | cpio -p --make-directories "$LOGS_FOLDER"
    find /var/log/Xorg.0* | cpio -p --make-directories "$LOGS_FOLDER"
    find /var/log/gpu-manager.log* | cpio -p --make-directories "$LOGS_FOLDER"
    journalctl > "$LOGS_FOLDER/journalctl.log"
}

get_etc_default_files(){
    find /etc/default | cpio -p --make-directories "$LOGS_FOLDER" || true
}


get_xinput_logs() {
    xinput > "$LOGS_FOLDER/xinput.log" || touch "$LOGS_FOLDER/xinput.log.failed"
}


__ScriptVersion="0.1"

#===  FUNCTION  ================================================================
#         NAME:  usage
#  DESCRIPTION:  Display usage information.
#===============================================================================
usage ()
{
    echo "Usage :  $0 [options] [--]

    This command is used to collect all logs which could be used to identify what the issues is.
    The collected logs will be put in $LOGS_FOLDER, and each executing $0 will create a new
    git commit in $LOGS_FOLDER.

    Options:
    -h|help       Display this message
    -v|version    Display script version
    -f|full       get full logs which include /sys
    -p|path       the path you would like to store logs, default is $HOME/collect-logs"

}    # ----------  end of function usage  ----------

#-----------------------------------------------------------------------
#  Handle command line arguments
#-----------------------------------------------------------------------

while getopts ":hvfp" opt
do
  case $opt in

    h|help     )  usage; exit 0   ;;

    v|version  )  echo "$0 -- Version $__ScriptVersion"; exit 0   ;;
    f|full  )
        FULL=1; echo "$0 -- Version $__ScriptVersion";
        ;;
    p|path  )  shift;LOGS_FOLDER="$1" ;;

    * )  echo -e "\n  Option does not exist : $OPTARG\n"
          usage; exit 1   ;;

  esac    # --- end of case ---
done
shift $((OPTIND-1))

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    mkdir -p "$LOGS_FOLDER"
    exec > >(tee -i "$LOGS_FOLDER/collect-logs.log")
    main "$@"

fi



