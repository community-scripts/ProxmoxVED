#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://gitea.io

APP="Alpine-Gitea"
var_tags="alpine;git"
var_cpu="1"
var_ram="256"
var_disk="1"
var_os="alpine"
var_version="3.21"
var_unprivileged="1"

header_info "$APP"
variables
color
catch_errors

function update_script() {
    if ! apk -e info newt >/dev/null 2>&1; then
        apk add -q newt
    fi
    while true; do
        CHOICE=$(
            whiptail --backtitle "Proxmox VE Helper Scripts" --title "SUPPORT" --menu "Select option" 11 58 2 \
                "1" "Update Alpine" \
                "2" "Update Gitea" 3>&2 2>&1 1>&3
        )
        exit_status=$?
        if [ $exit_status == 1 ]; then
            clear
            exit-script
        fi
        header_info
        case $CHOICE in
        1)
            apk update && apk upgrade
            exit
            ;;
        2)
            apk update && apk upgrade
            apk upgrade gitea
            rc-service gitea restart
            exit
            ;;
        esac
    done
}

start
build_container
description

msg_ok "Completed Successfully!\n"
