#!/usr/bin/env bash
source <(curl -s https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: glabutis
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/bitfocus/companion

# App Default Values
APP="Companion"
var_tags="${var_tags:-automation;media}"
# Tags for Proxmox VE (max 2, no spaces, semicolon-separated)
var_cpu="${var_cpu:-2}"
# Number of cores (default: 2)
var_ram="${var_ram:-512}"
# RAM in MB (default: 512)
var_disk="${var_disk:-8}"
# Disk space in GB (default: 8)
var_os="${var_os:-debian}"
# Default OS
var_version="${var_version:-12}"
# Default OS version
var_unprivileged="${var_unprivileged:-1}"
# 1 = unprivileged container, 0 = privileged

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f /opt/companion/companion_headless.sh ]]; then
    msg_error "No ${APP} Installation Found!"
    exit 1
  fi

  RELEASE_JSON=$(curl -fsSL "https://api.bitfocus.io/v1/product/companion/packages?limit=20")
  RELEASE=$(echo "$RELEASE_JSON" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for pkg in data.get('packages', data if isinstance(data, list) else []):
    if pkg.get('target') == 'linux-tgz':
        print(pkg.get('version', ''))
        break
")
  ASSET_URL=$(echo "$RELEASE_JSON" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for pkg in data.get('packages', data if isinstance(data, list) else []):
    if pkg.get('target') == 'linux-tgz':
        print(pkg.get('uri', ''))
        break
")

  if [[ "${RELEASE}" == "$(cat /opt/companion_version.txt 2>/dev/null)" ]]; then
    msg_ok "No update required. ${APP} is already at v${RELEASE}"
    exit
  fi

  msg_info "Stopping ${APP}"
  systemctl stop companion
  msg_ok "Stopped ${APP}"

  msg_info "Updating ${APP} to v${RELEASE}"
  rm -rf /opt/companion
  mkdir -p /opt/companion
  curl -fsSL "$ASSET_URL" -o /tmp/companion.tar.gz
  tar -xzf /tmp/companion.tar.gz -C /opt/companion --strip-components=1
  rm -f /tmp/companion.tar.gz
  chown -R companion:companion /opt/companion
  msg_ok "Updated ${APP} to v${RELEASE}"

  msg_info "Starting ${APP}"
  systemctl start companion
  msg_ok "Started ${APP}"

  msg_info "Cleaning Up"
  rm -f /tmp/companion.tar.gz
  msg_ok "Cleanup Completed"

  echo "${RELEASE}" >/opt/companion_version.txt
  msg_ok "Update Successful"
  exit
}

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8000${CL}"
