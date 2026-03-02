#!/usr/bin/env bash
SCRIPT_REPO="${SCRIPT_REPO:-BillyOutlast/ProxmoxVE}"
export SCRIPT_REPO
source <(curl -fsSL "https://raw.githubusercontent.com/${SCRIPT_REPO}/main/misc/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: ChatGPT
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/samanhappy/mcphub | Docs: https://docs.mcphubx.com/

APP="MCPHub"
var_tags="${var_tags:-ai;automation;tooling}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"
var_ssh="${var_ssh:-yes}"

if [[ -z "${var_ssh_authorized_key:-}" ]] && [[ -r /root/.ssh/authorized_keys ]]; then
  var_ssh_authorized_key="$(grep -m1 -E '^(ssh-(rsa|ed25519)|ecdsa-sha2-nistp256|sk-(ssh-ed25519|ecdsa-sha2-nistp256))[[:space:]]+' /root/.ssh/authorized_keys || true)"
fi

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f /etc/systemd/system/mcphub.service ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  NODE_VERSION="22" setup_nodejs

  msg_info "Updating MCPHub"
  systemctl stop mcphub
  $STD npm update -g @samanhappy/mcphub
  systemctl start mcphub
  msg_ok "Updated MCPHub"
  msg_ok "Updated successfully!"
  exit
}

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:3000${CL}"
