#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../misc/build.func" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_URL:-https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main}/misc/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Marc Went (Dunky13)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://openbao.org/

APP="Alpine-OpenBao"
var_tags="${var_tags:-alpine;security;secrets}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-3}"
var_os="${var_os:-alpine}"
var_version="${var_version:-3.24}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f /opt/openbao/bao ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Updating Alpine Packages"
  $STD apk -U upgrade
  msg_ok "Updated Alpine Packages"

  if check_for_gh_release "openbao" "openbao/openbao"; then
    msg_info "Stopping Service"
    $STD rc-service openbao stop
    msg_ok "Stopped Service"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "openbao" "openbao/openbao" "prebuild" "latest" "/opt/openbao" "openbao_*_linux_$(arch_resolve).tar.gz"

    msg_info "Starting Service"
    $STD rc-service openbao start
    msg_ok "Started Service"
    for _ in $(seq 1 15); do
      BAO_ADDR=https://127.0.0.1:8200 BAO_SKIP_VERIFY=true bao status -format=json 2>/dev/null | jq -e '.sealed == false' >/dev/null && break
      sleep 2
    done
    if ! BAO_ADDR=https://127.0.0.1:8200 BAO_SKIP_VERIFY=true bao status -format=json 2>/dev/null | jq -e '.sealed == false' >/dev/null; then
      msg_error "OpenBao did not unseal within 30 seconds"
      exit 1
    fi
    msg_ok "Updated successfully!"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}https://${IP}:8200${CL}"
echo -e "${INFO}${YW} Credentials:${CL}"
echo -e "${TAB}${DGN}Root Token: ${BGN}$(pct exec "$CTID" -- sed -n 's/^BAO_ROOT_TOKEN=//p' /etc/conf.d/openbao)${CL}"
echo -e "${TAB}${DGN}Unseal Key: ${BGN}$(pct exec "$CTID" -- sed -n 's/^BAO_UNSEAL_KEY=//p' /etc/conf.d/openbao)${CL}"
