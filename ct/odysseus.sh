#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/alexindigo/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Alex Indigo (alexindigo)
# License: MIT | https://github.com/alexindigo/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/pewdiepie-archdaemon/odysseus | https://pewdiepie-archdaemon.github.io/odysseus/

APP="Odysseus"
var_tags="${var_tags:-ai;workspace;llm}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-no}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/odysseus ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Checking for updates"
  cd /opt/odysseus
  $STD git fetch origin main
  LOCAL=$(git rev-parse HEAD)
  REMOTE=$(git rev-parse origin/main 2>/dev/null || echo "")
  if [[ "$LOCAL" != "$REMOTE" && -n "$REMOTE" ]]; then
    PYTHON_VERSION="3.12" setup_uv
    msg_info "Stopping Service"
    systemctl stop odysseus
    msg_ok "Stopped Service"

    msg_info "Backing up Configuration"
    cp /opt/odysseus/.env /opt/odysseus.env.bak
    msg_ok "Backed up Configuration"

    $STD git pull origin main

    $STD uv pip install -r /opt/odysseus/requirements.txt --python=/opt/odysseus/venv/bin/python --upgrade

    msg_info "Restoring Configuration"
    cp /opt/odysseus.env.bak /opt/odysseus/.env
    rm -f /opt/odysseus.env.bak
    msg_ok "Restored Configuration"

    $STD /opt/odysseus/venv/bin/python /opt/odysseus/setup.py

    msg_info "Starting Service"
    systemctl start odysseus
    msg_ok "Started Service"
    msg_ok "Updated Successfully!"
  else
    msg_ok "${APP} is up to date"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}${CL}"
