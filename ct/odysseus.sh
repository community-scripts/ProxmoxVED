#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: pwdiepie-archdaemon
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/pewdiepie-archdaemon/odysseus

APP="Odysseus"
var_tags="${var_tags:-ai;llm;self-hosted}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
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

  if [[ ! -f /etc/systemd/system/odysseus.service ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Stopping Services"
  systemctl stop odysseus
  systemctl stop chromadb
  msg_ok "Stopped Services"

  msg_info "Updating ${APP}"
  cd /opt/odysseus
  $STD git pull
  PYTHON_VERSION="3.12" setup_uv
  $STD uv pip install -r /opt/odysseus/requirements.txt --python /opt/odysseus/.venv/bin/python3
  msg_ok "Updated ${APP}"

  msg_info "Starting Services"
  systemctl start chromadb
  systemctl start odysseus
  msg_ok "Started Services"

  msg_ok "Updated successfully!"
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:7000${CL}"
echo -e "${INFO}${YW} Admin credentials saved to:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}~/odysseus.creds${CL}"
