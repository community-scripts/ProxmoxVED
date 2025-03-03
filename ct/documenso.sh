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
    ____                                                 
   / __ \____  _______  ______ ___  ___  ____  _________ 
  / / / / __ \/ ___/ / / / __ `__ \/ _ \/ __ \/ ___/ __ \
 / /_/ / /_/ / /__/ /_/ / / / / / /  __/ / / (__  ) /_/ /
/_____/\____/\___/\__,_/_/ /_/ /_/\___/_/ /_/____/\____/ 

EOF
}
header_info
echo -e "Loading..."
APP="Documenso"
var_disk="12"
var_cpu="6"
var_ram="6144"
var_os="debian"
var_version="12"
var_unprivileged="1"

# App Output & Base Settings
header_info "$APP"

# Core
variables
color
catch_errors


function update_script() {
header_info
if [[ ! -d /opt/documenso ]]; then msg_error "No ${APP} Installation Found!"; exit; fi
if (( $(df /boot | awk 'NR==2{gsub("%","",$5); print $5}') > 80 )); then
  read -r -p "Warning: Storage is dangerously low, continue anyway? <y/N> " prompt
  [[ ${prompt,,} =~ ^(y|yes)$ ]] || exit
fi
RELEASE=$(curl -s https://api.github.com/repos/documenso/documenso/releases/latest | grep "tag_name" | awk '{print substr($2, 3, length($2)-4) }')
if [[ ! -f /opt/${APP}_version.txt ]] || [[ "${RELEASE}" != "$(cat /opt/${APP}_version.txt)" ]]; then
  whiptail --backtitle "Proxmox VE Helper Scripts" --msgbox --title "SET RESOURCES" "Please set the resources in your ${APP} LXC to ${var_cpu}vCPU and ${var_ram}RAM for the build process before continuing" 10 75
  msg_info "Stopping ${APP}"
  systemctl stop documenso
  msg_ok "${APP} Stopped"

  msg_info "Updating ${APP} to ${RELEASE}"
  cp /opt/documenso/.env /opt/
  rm -R /opt/documenso
  wget -q "https://github.com/documenso/documenso/archive/refs/tags/v${RELEASE}.zip"
  unzip -q v${RELEASE}.zip
  mv documenso-${RELEASE} /opt/documenso
  cd /opt/documenso
  mv /opt/.env /opt/documenso/.env
  npm install &>/dev/null
  npm run build:web &>/dev/null 
  npm run prisma:migrate-deploy &>/dev/null
  echo "${RELEASE}" >/opt/${APP}_version.txt
  msg_ok "Updated ${APP}"

  msg_info "Starting ${APP}"
  systemctl start documenso
  msg_ok "Started ${APP}"

  msg_info "Cleaning Up"
  rm -rf v${RELEASE}.zip
  msg_ok "Cleaned"
  msg_ok "Updated Successfully"
else
  msg_ok "No update required. ${APP} is already at ${RELEASE}"
fi
exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${APP} Setup should be reachable by going to the following URL.
         ${BL}http://${IP}:9000${CL} \n"