#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../misc/build.func" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_URL:-https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main}/misc/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: angusmaul
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://orb.net/

APP="Orb"
var_tags="${var_tags:-network;monitoring}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-4}"
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

  if ! command -v orb >/dev/null 2>&1; then
    msg_error "No ${APP} Installation Found!"
    exit 233
  fi

  if [[ ! -f /etc/apt/sources.list.d/orb.sources ]]; then
    setup_deb822_repo \
      "orb" \
      "https://pkgs.orb.net/stable/debian/orbforge.noarmor.gpg" \
      "https://pkgs.orb.net/stable/debian" \
      "orb" \
      "main"
  fi

  # The sensor identity (private.key + certificate.crt) lives in /home/orb/.config/orb.
  # Upgrading the package replaces only /usr/bin/orb, so that directory is never touched
  # and the sensor keeps its Orb ID and its history. Do not clear it to "start clean".
  msg_info "Updating $APP LXC"
  $STD apt update
  $STD apt install -y --only-upgrade orb
  msg_ok "Updated successfully!"
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}The sensor is running but is not linked to an Orb account yet.${CL}"
echo -e "${TAB}${GATEWAY}${BGN}pct exec ${CTID} -- runuser -u orb -- orb link${CL}"
echo -e "${INFO}${YW}Then scan the QR code, or open the printed URL and sign in.${CL}"
echo -e "${INFO}${YW}Measurements are viewed in the Orb app or at:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}https://app.orb.net${CL}"
