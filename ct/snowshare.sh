#!/usr/bin/env bash
source <(curl -s https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: TuroYT
# License: MIT
# https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE

function header_info {
clear
cat <<"EOF"
   _____                       _____ __                     
  / ___/____  ____ _      __  / ___// /_  ____ ___________ 
  \__ \/ __ \/ __ \ | /| / /  \__ \/ __ \/ __ `/ ___/ _ \
 ___/ / / / / /_/ / |/ |/ /  ___/ / / / / /_/ / /  /  __/
/____/_/ /_/\____/|__/|__/  /____/_/ /_/\__,_/_/   \___/ 
                                                          
EOF
}
header_info
echo -e "Loading..."
APP="SnowShare"
var_disk="8"
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
header_info
if [[ ! -d /opt/snowshare ]]; then
  msg_error "No ${APP} Installation Found!"
  exit
fi
msg_info "Updating ${APP}"
systemctl stop snowshare
cd /opt/snowshare
git pull
npm ci
npx prisma generate
npm run build
systemctl start snowshare
msg_ok "Updated ${APP}"
exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${APP} should be reachable by going to the following URL.
         ${BL}http://${IP}:3000${CL} \n"