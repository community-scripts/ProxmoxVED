#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/hudikhq/hoodik

APP="Hoodik"
var_tags="${var_tags:-cloud;storage}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
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

  if [[ ! -f /usr/local/bin/hoodik ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "hoodik" "hudikhq/hoodik"; then
    msg_info "Stopping Services"
    systemctl stop hoodik
    msg_ok "Stopped Services"

    msg_info "Backing up Configuration"
    cp /opt/hoodik/.env /tmp/hoodik.env.bak
    msg_ok "Backed up Configuration"

    msg_info "Updating ${APP} (Patience - this takes 10-15 minutes)"
    source ~/.cargo/env
    rm -rf /opt/hoodik
    fetch_and_deploy_gh_release "hoodik" "hudikhq/hoodik" "tarball" "latest" "/opt/hoodik"
    cd /opt/hoodik
    $STD cargo build --release
    cp /opt/hoodik/target/release/hoodik /usr/local/bin/hoodik
    chmod +x /usr/local/bin/hoodik
    msg_ok "Updated ${APP}"

    msg_info "Restoring Configuration"
    cp /tmp/hoodik.env.bak /opt/hoodik/.env
    rm -f /tmp/hoodik.env.bak
    msg_ok "Restored Configuration"

    msg_info "Cleaning Up"
    rm -rf /opt/hoodik/target
    msg_ok "Cleaned"

    msg_info "Starting Services"
    systemctl start hoodik
    msg_ok "Started Services"

    msg_ok "Updated Successfully"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}https://${IP}:5443${CL}"
