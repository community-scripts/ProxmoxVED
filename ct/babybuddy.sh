#!/usr/bin/env bash
source <(curl -s https://raw.githubusercontent.com/MickLesk/Proxmox_DEV/main/misc/build.func)
# Copyright (c) 2021-2024 tteck
# Author: tteck
# Co-Author: MickLesk (Canbiz)
# License: MIT
# https://github.com/tteck/Proxmox/raw/main/LICENSE

function header_info {
clear
cat <<"EOF"
    ____        __             ____            __    __     
   / __ )____ _/ /_  __  __   / __ )__  ______/ /___/ /_  __
  / __  / __ `/ __ \/ / / /  / __  / / / / __  / __  / / / /
 / /_/ / /_/ / /_/ / /_/ /  / /_/ / /_/ / /_/ / /_/ / /_/ / 
/_____/\__,_/_.___/\__, /  /_____/\__,_/\__,_/\__,_/\__, /  
                  /____/                           /____/   
EOF
}
header_info
echo -e "Loading..."
APP="BabyBuddy"
var_disk="5"
var_cpu="2"
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
  if [[ ! -d /opt/scrutiny ]]; then msg_error "No ${APP} Installation Found!"; exit; fi
  RELEASE=$(curl -s https://api.github.com/repos/AnalogJ/scrutiny/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3) }')

  UPD=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "Scrutiny Management" --radiolist --cancel-button Exit-Script "Spacebar = Select" 15 70 4 \
    "1" "Update Scrutiny to $RELEASE" ON \
	"2" "Change Scrutiny Settings"  OFF \
    3>&1 1>&2 2>&3)
  header_info
if [ "$UPD" == "2" ]; then
	nano /opt/scrutiny/config/scrutiny.yaml
	exit
fi
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${APP} Setup should be reachable by going to the following URL.
		 but first, you need to edit the influxDB connection!
         ${BL}http://${IP}:8080${CL} \n"