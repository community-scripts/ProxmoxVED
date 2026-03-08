#!/usr/bin/env bash
COMMUNITY_SCRIPTS_URL="${COMMUNITY_SCRIPTS_URL:-https://git.community-scripts.org/community-scripts/ProxmoxVED/raw/branch/main}"
source <(curl -fsSL "$COMMUNITY_SCRIPTS_URL/misc/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Stephen Chin
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/ProtonMail/proton-bridge
# Description: Debian LXC that runs Proton Mail Bridge headless and exposes IMAP/SMTP to the LAN via systemd-socket-proxyd.

APP="ProtonMail-Bridge"
var_tags="${var_tags:-mail;proton}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-768}"
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

  if [[ ! -x /usr/bin/protonmail-bridge ]]; then
    msg_error "No Proton Mail Bridge Installation Found!"
    exit
  fi

  if check_for_gh_release "protonmail-bridge" "ProtonMail/proton-bridge"; then
    msg_info "Stopping Services"
    systemctl stop protonmail-bridge-imap.socket protonmail-bridge-smtp.socket
    systemctl stop protonmail-bridge-imap-proxy.service protonmail-bridge-smtp-proxy.service protonmail-bridge.service
    msg_ok "Stopped Services"

    msg_info "Updating Proton Mail Bridge"
    fetch_and_deploy_gh_release "protonmail-bridge" "ProtonMail/proton-bridge" "binary"
    msg_ok "Updated Proton Mail Bridge"

    if [[ -f /home/protonbridge/.protonmailbridge-initialized ]]; then
      msg_info "Starting Services"
      systemctl start protonmail-bridge.service
      systemctl start protonmail-bridge-imap.socket protonmail-bridge-smtp.socket
      systemctl start protonmail-bridge-imap-proxy.service protonmail-bridge-smtp-proxy.service
      msg_ok "Started Services"
    else
      msg_ok "Initialization not completed. Services remain disabled."
    fi

    msg_ok "Updated successfully!"
  fi
  exit
}

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}Proton Mail Bridge setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}One-time initialization is required before Bridge services are enabled.${CL}"
echo -e "${INFO}${YW}Initialize the account inside the container:${CL}"
echo -e "${TAB}${YW}protonmailbridge-init${CL}"
echo -e "${INFO}${YW}After initial configuration, use this to access the Bridge CLI:${CL}"
echo -e "${TAB}${YW}protonmailbridge-configure${CL}"
echo -e "${INFO}${YW}LAN-accessible forwarded ports (container IP ${IP}):${CL}"
echo -e "${TAB}${GATEWAY}${BGN}IMAP  ${IP}:143${CL}"
echo -e "${TAB}${GATEWAY}${BGN}SMTP  ${IP}:587${CL}"
echo -e "${INFO}${YW}Forwarding targets inside the container (Bridge defaults):${CL}"
echo -e "${TAB}${YW}IMAP 127.0.0.1:1143${CL}"
echo -e "${TAB}${YW}SMTP 127.0.0.1:1025${CL}"
