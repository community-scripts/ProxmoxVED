#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../misc/build.func" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_URL:-https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main}/misc/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/rustfs/rustfs

APP="RustFS"
var_tags="${var_tags:-storage;s3}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-20}"
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

  if [[ ! -f /etc/default/rustfs ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Stopping Service"
  systemctl stop rustfs
  msg_ok "Stopped Service"

  msg_info "Updating ${APP}"
  curl -fsSL "https://dl.rustfs.com/artifacts/rustfs/release/rustfs-linux-$(arch_resolve x86_64 aarch64)-gnu-latest.zip" -o /tmp/rustfs.zip
  $STD unzip -o /tmp/rustfs.zip -d /opt/rustfs
  rm -f /tmp/rustfs.zip
  chmod +x /opt/rustfs/rustfs
  msg_ok "Updated ${APP}"

  msg_info "Starting Service"
  systemctl start rustfs
  msg_ok "Started Service"
  msg_ok "Updated successfully!"
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Console:${CL}"
echo -e "${GATEWAY}${BGN}http://${IP}:9001${CL}"
echo -e "${INFO}${YW}S3 API on port 9000 - keys are in /etc/default/rustfs${CL}"
