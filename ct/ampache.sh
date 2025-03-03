#!/usr/bin/env bash
source <(curl -s https://raw.githubusercontent.com/MickLesk/Proxmox_DEV/main/misc/build.func)
# Copyright (c) 2021-2024 tteck
# Author: MickLesk (Canbiz)
# License: MIT
# https://github.com/tteck/Proxmox/raw/main/LICENSE

function header_info {
clear
cat <<"EOF"
______                          _ _ 
|  _  \                        | | |
| | | |___   ___ ___ _ __   ___| | |
| | | / _ \ / __/ __| '_ \ / _ \ | |
| |/ / (_) | (__\__ \ |_) |  __/ | |
|___/ \___/ \___|___/ .__/ \___|_|_|
                    | |             
                    |_|            
                                               
EOF
}
header_info
echo -e "Loading..."
APP="Ampache"
var_disk="5"
var_cpu="4"
var_ram="2048"
var_os="debian"
var_version="12"
variables
color
catch_errors

function default_settings() {
  CT_TYPE="1"
  PW=""
  CT_ID=$NEXTID
  HN=$NSAPP
  DISK_SIZE="$var_disk"
  CORE_COUNT="$var_cpu"
  RAM_SIZE="$var_ram"
  BRG="vmbr0"
  NET="dhcp"
  GATE=""
  APT_CACHER=""
  APT_CACHER_IP=""
  DISABLEIP6="no"
  MTU=""
  SD=""
  NS=""
  MAC=""
  VLAN=""
  SSH="no"
  VERB="no"
  echo_default
}

function update_script() {
header_info
if [[ ! -d /opt/ampache ]]; then 
	msg_error "No ${APP} Installation Found!"; 
	exit; 
fi
msg_info "Updating ${APP} LXC"
cd /opt/bookstack
git config --global --add safe.directory /opt/bookstack >/dev/null 2>&1
git pull origin release >/dev/null 2>&1
composer install --no-interaction --no-dev >/dev/null 2>&1
php artisan migrate --force >/dev/null 2>&1
php artisan cache:clear
php artisan config:clear
php artisan view:clear
msg_ok "Updated Successfully"
exit
msg_error "There is currently no update path available."
}

start
build_container
description

msg_info "Setting Container to Normal Resources"
pct set $CTID -cores 2
msg_ok "Set Container to Normal Resources"

msg_ok "Completed Successfully!\n"
echo -e "${APP} Setup should be reachable by going to the following URL.
         ${BL}http://${IP}/install.php${CL} \n"
