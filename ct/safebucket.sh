#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: renizmy
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/safebucket/safebucket

APP="Safebucket"
var_tags="${var_tags:-files;sharing}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-10}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f /opt/safebucket/safebucket ]]; then
    msg_error "No ${APP} Installation Found!"
    exit 1
  fi

  if check_for_gh_release "safebucket" "safebucket/safebucket"; then
    msg_info "Stopping Service"
    systemctl stop safebucket
    msg_ok "Stopped Service"

    msg_info "Backing up Data"
    cp -r /opt/safebucket/data /opt/safebucket_data_backup 2>/dev/null || true
    cp /opt/safebucket/config.yaml /opt/safebucket_config_backup.yaml 2>/dev/null || true
    msg_ok "Backed up Data"

    local ARCH=$(dpkg --print-architecture 2>/dev/null || uname -m)
    [[ "$ARCH" == "x86_64" ]] && ARCH="amd64"
    [[ "$ARCH" == "aarch64" ]] && ARCH="arm64"
    
    fetch_and_deploy_gh_release "safebucket" "safebucket/safebucket" "singlefile" "latest" "/opt/safebucket" "safebucket-linux-${ARCH}"
    chmod +x /opt/safebucket/safebucket

    msg_info "Restoring Data"
    cp -r /opt/safebucket_data_backup/. /opt/safebucket/data/ 2>/dev/null || true
    cp /opt/safebucket_config_backup.yaml /opt/safebucket/config.yaml 2>/dev/null || true
    rm -rf /opt/safebucket_data_backup /opt/safebucket_config_backup.yaml
    chown -R safebucket:safebucket /opt/safebucket
    msg_ok "Restored Data"

    msg_info "Starting Service"
    systemctl start safebucket
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8080${CL}"
