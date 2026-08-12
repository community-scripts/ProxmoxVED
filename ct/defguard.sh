#!/usr/bin/env bash
# Engine comes from community-scripts/core; this repo only ships the scripts.
# A local core checkout wins (COMMUNITY_SCRIPTS_CORE_DIR, else a sibling ../core),
# so a fork or branch of core can be tested without editing this file.
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/DefGuard/defguard

APP="Defguard"
var_tags="${var_tags:-vpn;wireguard;sso}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
#var_arm64="${var_arm64:-no}" # unset = ask the user; set yes/no only when verified
var_unprivileged="${var_unprivileged:-1}"
var_testurl="${var_testurl:-https://github.com/community-scripts/ProxmoxVED/issues/2111}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f /etc/defguard/core.conf ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Updating ${APP}"
  $STD apt update
  $STD apt install -y defguard defguard-proxy
  msg_ok "Updated ${APP}"

  msg_info "Restarting Services"
  systemctl restart defguard defguard-proxy
  msg_ok "Restarted Services"
  msg_ok "Updated successfully!"
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Access it using the following URL:${CL}"
echo -e "${GATEWAY}${BGN}http://${IP}:8000${CL}"
echo -e "${INFO}${YW}In the setup wizard, enter this as the Edge address:${CL}"
echo -e "${TAB}${DEFAULT}${BGN}127.0.0.1:50051${CL}"
echo -e "${INFO}${YW}The generated admin password is in /etc/defguard/core.conf${CL}"
