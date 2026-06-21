#!/usr/bin/env bash
# shellcheck disable=SC1090
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: ryanbuu
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://manual.nssurge.com/others/snell.html

APP="Snell"
var_tags="${var_tags:-proxy;network}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-2}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

export SNELL_PORT="${SNELL_PORT:-}"
export SNELL_PSK="${SNELL_PSK:-}"

SNELL_VERSION="v5.0.1"

header_info "$APP"
variables
color
catch_errors

snell_release_arch() {
  local arch
  arch="$(dpkg --print-architecture 2>/dev/null || uname -m)"
  case "$arch" in
  amd64 | x86_64)
    echo "amd64"
    ;;
  arm64 | aarch64)
    echo "aarch64"
    ;;
  *)
    msg_error "Unsupported architecture: ${arch}"
    exit 65
    ;;
  esac
}

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -x /usr/local/bin/snell-server ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if [[ "$(cat /opt/snell/version 2>/dev/null)" == "${SNELL_VERSION}" ]]; then
    msg_ok "No update required. Snell is already ${SNELL_VERSION}."
    exit
  fi

  msg_info "Stopping Service"
  systemctl stop snell
  msg_ok "Stopped Service"

  CLEAN_INSTALL=1 fetch_and_deploy_from_url "https://dl.nssurge.com/snell/snell-server-${SNELL_VERSION}-linux-$(snell_release_arch).zip" "/opt/snell"

  msg_info "Installing Snell"
  chmod +x /opt/snell/snell-server
  ln -sf /opt/snell/snell-server /usr/local/bin/snell-server
  echo "${SNELL_VERSION}" >/opt/snell/version
  msg_ok "Installed Snell"

  msg_info "Starting Service"
  systemctl start snell
  msg_ok "Started Service"
  msg_ok "Updated successfully!"
  exit
}

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Snell server configuration:${CL}"
echo -e "${TAB}${BGN}/etc/snell/snell-server.conf${CL}"
echo -e "${INFO}${YW} Client format:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}snell, ${IP}, <port>, psk = <psk>, version = 5, reuse = true${CL}"
