#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/dkuku/ProxmoxVED/refs/heads/livebook/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: dkuku
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/livebook-dev/livebook

echo -e "Loading..."
APP="Livebook"
var_tags="${var_tags:-development}"
var_disk="${var_disk:-4}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-1024}"
var_os="${var_os:-ubuntu}"
var_version="${var_version:-24}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  # Check if Livebook is installed
  if [[ ! -f /opt/${APP}_version.txt ]]; then
    msg_error "No ${APP} Installation Found!"
    exit 1
  fi

  # Get the latest version from GitHub
  msg_info "Checking for updates..."
  RELEASE=$(curl -fsSL https://api.github.com/repos/livebook-dev/livebook/releases/latest | grep "tag_name" | awk -F'"' '{print $4}')

  if [[ -z "$RELEASE" ]]; then
    msg_error "Failed to fetch latest version information"
    exit 1
  fi

  # Check if version file exists and compare versions
  if [[ "${RELEASE}" != "$(cat /opt/${APP}_version.txt 2>/dev/null)" ]]; then
    msg_info "Updating ${APP} LXC"
    $STD apt-get update
    $STD apt-get -y upgrade
    msg_ok "Updated ${APP} LXC"

    msg_info "Updating ${APP} to ${RELEASE}"
    source /opt/.env
    cd /opt || exit 1
    rm /opt/.mix/escripts/livebook
    mix escript.install hex livebook --force >/dev/null 2>&1

    # Save the new version
    echo "$RELEASE" | $STD tee /opt/${APP}_version.txt >/dev/null

    msg_ok "Successfully updated to ${RELEASE}"
  else
    msg_ok "No update required. ${APP} is already at ${RELEASE}."
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
