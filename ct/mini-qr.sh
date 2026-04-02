#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: doge0420
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/lyqht/mini-qr

APP="Mini-QR"
var_tags="${var_tags:-QRcode;}"                 # Max 2 tags, semicolon-separated
var_cpu="${var_cpu:-2}"                         # CPU cores: 1-4 typical
var_ram="${var_ram:-2048}"                      # RAM in MB: 512, 1024, 2048, etc.
var_disk="${var_disk:-6}"                       # Disk in GB: 6, 8, 10, 20 typical
var_os="${var_os:-debian}"                      # OS: debian, ubuntu, alpine
var_version="${var_version:-13}"                # OS Version: 13 (Debian), 24.04 (Ubuntu), 3.21 (Alpine)
var_unprivileged="${var_unprivileged:-1}"       # 1=unprivileged (secure), 0=privileged (for Docker/Podman)

header_info "$APP" # Display app name and setup header
variables          # Initialize build.func variables
color              # Load color variables for output
catch_errors       # Enable error handling with automatic exit on failure

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/mini-qr ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "mini-qr" "lyqht/mini-qr"; then

    msg_info "Stopping Service"
    systemctl stop caddy
    msg_ok "Stopped Service"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "mini-qr" "lyqht/mini-qr" "tarball" "latest" "/opt/mini-qr"

    msg_info "Installing Dependencies"
    cd /opt/mini-qr || exit
    $STD npm install
    msg_ok "Installed Dependencies"

    msg_info "Building MiniQR"
    $STD npm run build
    msg_ok "Built MiniQR"

    msg_info "Starting Service"
    systemctl start caddy
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
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:80${CL}"
