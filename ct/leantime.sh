#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)

# Copyright (c) 2021-2025 community-scripts ORG
# Author: Stroopwafe1
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://leantime.io

# App Default Values
# Name of the app (e.g. Google, Adventurelog, Apache-Guacamole"
APP="Leantime"
# Tags for Proxmox VE, maximum 2 pcs., no spaces allowed, separated by a semicolon ; (e.g. database | adblock;dhcp)
var_tags="${var_tags:-productivity}"
# Number of cores (1-X) (e.g. 4) - default are 2
var_cpu="${var_cpu:-2}"
# Amount of used RAM in MB (e.g. 2048 or 4096)
var_ram="${var_ram:-2048}"
# Amount of used disk space in GB (e.g. 4 or 10)
var_disk="${var_disk:-20}"
# Default OS (e.g. debian, ubuntu, alpine)
var_os="${var_os:-debian}"
# Default OS version (e.g. 12 for debian, 24.04 for ubuntu, 3.20 for alpine)
var_version="${var_version:-12}"
# 1 = unprivileged container, 0 = privileged container
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  # Check if installation is present | -f for file, -d for folder
  if [[ ! -d /opt/${APP} ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  # Crawling the new version and checking whether an update is required
  RELEASE=$(curl -fsSL https://api.github.com/repos/Leantime/leantime/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3) }')
  if [[ "${RELEASE}" != "$(cat /opt/${APP}_version.txt)" ]] || [[ ! -f /opt/${APP}_version.txt ]]; then
    # Creating Backup
    msg_info "Creating Backup"
    mariadb-dump leantime >"/opt/${APP}_db_backup_$(date +%F).sql"
    tar -czf "/opt/${APP}_backup_$(date +%F).tar.gz" /opt/leantime
    msg_ok "Backup Created"

    # Execute Update
    msg_info "Updating $APP to v${RELEASE}"
    curl -fsSL -o "${RELEASE}.tar.gz" "https://github.com/Leantime/leantime/archive/refs/tags/${RELEASE}.tar.gz"
    tar xf "${RELEASE}.tar.gz" --strip-components=1 -C "/opt/${APP}"
    msg_ok "Updated $APP to v${RELEASE}"

    # Cleaning up
    msg_info "Cleaning Up"
    rm -rf "${RELEASE}.tar.gz"
    msg_ok "Cleanup Completed"

    # Last Action
    echo "${RELEASE}" >/opt/${APP}_version.txt
    msg_ok "Update Successful"
  else
    msg_ok "No update required. ${APP} is already at v${RELEASE}"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}/install${CL}"
