#!/usr/bin/env bash
# Engine comes from community-scripts/core; this repo only ships the scripts.
# A local core checkout wins (COMMUNITY_SCRIPTS_CORE_DIR, else a sibling ../core),
# so a fork or branch of core can be tested without editing this file.
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: lukdz
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/pingdotgg/t3code

APP="T3Code"
var_tags="${var_tags:-ai;dev-tools}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-10}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
#var_arm64="${var_arm64:-no}" # unset = ask the user; set yes/no only when verified
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if ! command -v t3 >/dev/null 2>&1; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Stopping Service"
  systemctl stop t3code
  msg_ok "Stopped Service"

  # T3 Code is distributed via npm; npm resolves the latest version itself,
  # so there is no GitHub-release tarball to check against.
  msg_info "Updating T3 Code"
  $STD npm install -g t3@latest
  msg_ok "Updated T3 Code"

  msg_info "Starting Service"
  systemctl start t3code
  msg_ok "Started Service"
  msg_ok "Updated successfully!"
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Access it using the following URL:${CL}"
echo -e "${GATEWAY}${BGN}http://${IP}:3773${CL}"
echo -e ""
echo -e "${INFO}${YW}A one-time pairing URL (1h lifetime) is printed at the end of the install log.${CL}"
echo -e "${INFO}${YW}Generate a fresh one anytime from the Proxmox host:${CL}"
echo -e "${TAB}${BGN}pct exec ${CTID} -- t3 pair --base-dir /opt/t3code_data --ttl 1h${CL}"
echo -e ""
echo -e "${INFO}${YW}Provider CLIs (codex, claude, opencode) and gh are installed but not authenticated. Log in from the host, e.g.:${CL}"
echo -e "${TAB}${BGN}pct exec ${CTID} -- codex login${CL}"
