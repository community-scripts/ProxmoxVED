#!/usr/bin/env bash
# Engine comes from community-scripts/core; this repo only ships the scripts.
# A local core checkout wins (COMMUNITY_SCRIPTS_CORE_DIR, else a sibling ../core),
# so a fork or branch of core can be tested without editing this file.
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Justin Tröbinger (bonderaustria)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/bonderaustria/proxfy

APP="Proxfy"
var_tags="${var_tags:-backup;verification;proxmox}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"
#var_arm64="${var_arm64:-no}" # unset = ask the user; set yes/no only when verified

# Proxfy drives the hypervisor over SSH, so it needs to know where it is and
# needs its public key in the host's authorized_keys. The address is required.
# The password is optional and only used once, to place that key; it is never
# written to disk.
export var_pve_host="${var_pve_host:-}"
export var_pve_password="${var_pve_password:-}"

header_info "$APP"
variables
color
catch_errors

if [[ -n "${mode:-}" && -z "${var_pve_host}" ]]; then
  msg_error "var_pve_host is required for unattended installs."
  exit 1
fi

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f /opt/proxfy/config.yaml ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "proxfy" "bonderaustria/proxfy"; then
    msg_info "Stopping Services"
    systemctl stop proxfy proxfy-auth
    msg_ok "Stopped Services"

    create_backup /opt/proxfy/config.yaml /opt/proxfy/auth.env \
      /opt/proxfy/proxfy.db /opt/proxfy/auth.db

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "proxfy" "bonderaustria/proxfy" "tarball"

    restore_backup

    msg_info "Rebuilding Login Service"
    cd /opt/proxfy/auth
    $STD npm install --omit=dev --no-audit --no-fund
    msg_ok "Rebuilt Login Service"

    msg_info "Starting Services"
    systemctl start proxfy-auth
    systemctl start proxfy
    msg_ok "Started Services"
    msg_ok "Updated successfully!"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Access it using the following URL:${CL}"
echo -e "${GATEWAY}${BGN}http://${IP}:8099${CL}"
echo -e "${INFO}${YW}Open it now and create the first account - until one exists,${CL}"
echo -e "${INFO}${YW}anyone who can reach the address could create it.${CL}"
