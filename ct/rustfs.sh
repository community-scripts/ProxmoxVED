#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: GitHub Copilot
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/rustfs/rustfs

APP="RustFS"
var_tags="${var_tags:-object-storage}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f /opt/rustfs/rustfs ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Stopping Service"
  systemctl stop rustfs
  msg_ok "Stopped Service"

  msg_info "Updating ${APP}"
  ARCH=$(dpkg --print-architecture)
  if [[ "$ARCH" == "amd64" ]]; then
    RUSTFS_ARCH="x86_64"
  elif [[ "$ARCH" == "arm64" ]]; then
    RUSTFS_ARCH="aarch64"
  else
    msg_error "Unsupported architecture: $ARCH"
    exit 1
  fi

  cd /opt/rustfs || exit
  RELEASE=$(curl -sL https://api.github.com/repos/rustfs/rustfs/releases | grep -o '"tag_name": *"[^"]*"' | head -1 | cut -d'"' -f4)
  if [[ -z "$RELEASE" ]]; then
    msg_error "Failed to fetch latest release version"
    exit 1
  fi
  wget -q "https://github.com/rustfs/rustfs/releases/download/${RELEASE}/rustfs-linux-${RUSTFS_ARCH}-gnu-latest.zip"
  unzip -qo rustfs-linux-${RUSTFS_ARCH}-gnu-latest.zip
  rm rustfs-linux-${RUSTFS_ARCH}-gnu-latest.zip
  chmod +x rustfs
  msg_ok "Updated to ${RELEASE}"

  msg_info "Starting Service"
  systemctl start rustfs
  msg_ok "Started Service"
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URLs:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}Console: http://${IP}:9001${CL}"
echo -e "${TAB}${GATEWAY}${BGN}API: http://${IP}:9000${CL}"
echo -e "${INFO}${YW} Default credentials: ${BGN}rustfsadmin${CL} / ${BGN}rustfsadmin${CL}"
