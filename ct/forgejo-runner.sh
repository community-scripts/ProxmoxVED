#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Simon Friedrich
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://forgejo.org/

APP="Forgejo Runner"
var_tags="${var_tags:-ci}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-12}"

var_unprivileged="${var_unprivileged:-1}"
var_nesting="${var_nesting:-1}"
var_keyctl="${var_keyctl:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f /usr/local/bin/forgejo-runner ]]; then
    msg_error "No ${APP} installation found!"
    exit 1
  fi

  msg_info "Stopping Forgejo Runner"
  systemctl stop forgejo-runner
  msg_ok "Stopped Forgejo Runner"

  msg_info "Fetching latest Forgejo Runner version"
  OS=$(uname -s | tr '[:upper:]' '[:lower:]')
  ARCH=$(uname -m)

  case "$ARCH" in
    x86_64) ARCH="amd64" ;;
    aarch64|arm64) ARCH="arm64" ;;
    armv7l) ARCH="armv7" ;;
    *) echo "Unsupported architecture: $ARCH" >&2; exit 1 ;;
  esac

  RELEASE=$(curl -fsSL https://data.forgejo.org/api/v1/repos/forgejo/runner/releases/latest \
    | grep -oP '"tag_name":\s*"\K[^"]+' | sed 's/^v//')

  msg_info "Updating Forgejo Runner to v${RELEASE}"

  curl -fsSL \
    "https://data.forgejo.org/forgejo/runner/releases/download/v${RELEASE}/forgejo-runner-${OS}-${ARCH}" \
    -o forgejo-runner


  chmod +x /usr/local/bin/forgejo-runner
  msg_ok "Updated Forgejo Runner"

  msg_info "Starting Forgejo Runner"
  systemctl enable -q --now forgejo-runner
  msg_ok "Started Forgejo Runner"

  msg_ok "Update completed successfully!"
  exit
}

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}${CL}"