#!/usr/bin/env bash

# Draft for community-scripts/ProxmoxVED.
# Copy this file into ProxmoxVED/ct/openvoice-ai.sh before submission.

source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)

# Copyright (c) 2026 OpenVoice AI contributors
# License: MIT
# Source: https://github.com/nikpottbecker/openvoice-ai

APP="OpenVoice AI"
var_tags="${var_tags:-ai;communication;phone}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-6144}"
var_disk="${var_disk:-20}"
var_os="${var_os:-debian}"
var_version="${var_version:-12}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/phone-agent ]]; then
    msg_error "No ${APP} installation found."
    exit 1
  fi

  msg_info "Updating ${APP}"
  bash /opt/phone-agent/scripts/update.sh
  msg_ok "Updated ${APP}"
  exit
}

start
build_container
description
msg_ok "Completed successfully!\n"
echo -e "${INFO}${YW}Dashboard:${CL} ${BGN}http://${IP}:8088${CL}"
