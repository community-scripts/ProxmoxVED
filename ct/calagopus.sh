#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Jelcoo
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://calagopus.com/

APP="Calagopus"
var_tags="${var_tags:-panel;game-server;docker}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-15}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f /opt/calagopus/compose.yml ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Pulling Latest Images"
  cd /opt/calagopus
  docker compose pull
  msg_ok "Pulled Latest Images"

  msg_info "Restarting Services"
  docker compose up -d --remove-orphans
  msg_ok "Restarted Services"

  msg_ok "Updated Successfully!"
  exit
}

export CALAGOPUS_AIO="yes"
export CALAGOPUS_HEAVY="no"
export CALAGOPUS_NIGHTLY="no"

if ! (whiptail --backtitle "Proxmox VE Helper Scripts" --title "DEPLOYMENT TYPE" --yesno \
  "Install as All-in-One (AIO)?\n\nYES  — Panel + Wings in a single container (recommended for single-node)\nNO   — Standalone Panel only (for multi-node / split-host setups)" \
  12 65); then
  export CALAGOPUS_AIO="no"
fi

if (whiptail --backtitle "Proxmox VE Helper Scripts" --title "HEAVY VARIANT" --yesno \
  "Enable the Heavy variant?\n\nIncludes extension build tools inside the container.\nUse this if you plan to install Calagopus extensions." \
  10 65); then
  export CALAGOPUS_HEAVY="yes"
fi

if (whiptail --backtitle "Proxmox VE Helper Scripts" --title "NIGHTLY BUILD" --defaultno --yesno \
  "Use the Nightly (development) build?\n\nNightly builds contain the latest unreleased changes.\nNot recommended for production environments." \
  10 65); then
  export CALAGOPUS_NIGHTLY="yes"
fi

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8000${CL}"
