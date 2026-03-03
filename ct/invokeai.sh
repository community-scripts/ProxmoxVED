#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)

# Copyright (c) 2021-2026 community-scripts ORG
# Author: BillyOutlast
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/invoke-ai/InvokeAI

APP="InvokeAI"
var_tags="${var_tags:-ai;image-generation}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-8192}"
var_disk="${var_disk:-30}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f /etc/systemd/system/invokeai.service ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "invokeai" "invoke-ai/InvokeAI"; then
    msg_info "Stopping Service"
    systemctl stop invokeai
    msg_ok "Stopped Service"

    msg_info "Updating InvokeAI"
    if ! $STD uv pip install --python /opt/invokeai/.venv/bin/python --torch-backend=cpu --upgrade invokeai; then
      systemctl start invokeai || true
      msg_error "Failed to update InvokeAI"
      exit 1
    fi
    msg_ok "Updated InvokeAI"

    msg_info "Starting Service"
    if ! systemctl start invokeai; then
      msg_error "Failed to start InvokeAI"
      exit 1
    fi
    msg_ok "Started Service"

    if ! systemctl is-active -q invokeai; then
      msg_error "InvokeAI service is not running"
      exit 1
    fi

    INVOKEAI_VERSION="$(/opt/invokeai/.venv/bin/python -c "import importlib.metadata as m; print(m.version('invokeai'))")"
    echo "${INVOKEAI_VERSION}" >"$HOME/.invokeai"
    msg_ok "Updated successfully to v${INVOKEAI_VERSION}"
  fi
  exit
}

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:9090${CL}"
