#!/usr/bin/env bash
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Alex Van de Putte (avandeputte)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/avandeputte/haproxy-manager

APP="HAProxy-Manager"
var_tags="${var_tags:-proxy;loadbalancer;haproxy;keepalived}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"
var_arm64="${var_arm64:-yes}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f /opt/haproxy-manager/app.py ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "haproxy-manager" "avandeputte/haproxy-manager"; then
    msg_info "Stopping Service"
    systemctl stop haproxy-manager
    msg_ok "Stopped Service"

    fetch_and_deploy_gh_release "haproxy-manager" "avandeputte/haproxy-manager" "binary" "latest" "/opt/haproxy-manager" "haproxy-manager_*_all.deb"

    msg_info "Starting Service"
    systemctl daemon-reload
    systemctl start haproxy-manager
    msg_ok "Started Service"
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
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8080${CL}"
echo -e "${INFO}${YW} Credentials (also in /root/haproxy-manager.creds in the container):${CL}"
echo -e "${TAB}${DGN}$(pct exec "$CTID" -- cat /root/haproxy-manager.creds)${CL}"
