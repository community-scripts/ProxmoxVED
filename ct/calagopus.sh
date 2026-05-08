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
  docker compose -f /opt/calagopus/compose.yml pull
  msg_ok "Pulled Latest Images"

  msg_info "Restarting Services"
  docker compose -f /opt/calagopus/compose.yml up -d --remove-orphans
  msg_ok "Restarted Services"

  msg_ok "Updated Successfully!"
  exit
}

CHOICES=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "CALAGOPUS VARIANT" \
  --checklist "Select image options (Spacebar = toggle, Enter = confirm):" 14 60 3 \
  "aio" "All-in-One (Panel + Wings bundled)" ON \
  "heavy" "Heavy (includes extension build tools)" OFF \
  "nightly" "Nightly build (not for production)" OFF \
  3>&1 1>&2 2>&3)

[[ $CHOICES == *'"aio"'* ]] && export CALAGOPUS_AIO="yes" || export CALAGOPUS_AIO="no"
[[ $CHOICES == *'"heavy"'* ]] && export CALAGOPUS_HEAVY="yes" || export CALAGOPUS_HEAVY="no"
[[ $CHOICES == *'"nightly"'* ]] && export CALAGOPUS_NIGHTLY="yes" || export CALAGOPUS_NIGHTLY="no"

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8000${CL}"
