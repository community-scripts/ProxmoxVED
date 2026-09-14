#!/usr/bin/env bash
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: pshankinclarke (lazarillo)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://valkey.io/

APP="Valkey"
var_tags="${var_tags:-database}"
var_cpu="${var_cpu:-1}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"
if [[ -z "${var_os:-}" ]] && command -v pveversion >/dev/null 2>&1; then
  var_os=$(msg_menu "Choose the container OS" \
    "debian" "Debian 13 (TLS supported)" \
    "alpine" "Alpine 3.24 (smaller, no TLS)")
fi

if [[ "${var_os:-}" == "alpine" ]]; then
  var_ram="${var_ram:-256}"
  var_disk="${var_disk:-1}"
  var_version="${var_version:-3.24}"
else
  var_ram="${var_ram:-1024}"
  var_disk="${var_disk:-4}"
  var_version="${var_version:-13}"
fi

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  run_os_update
}

update_deb_based() {
  if [[ ! -f /lib/systemd/system/valkey-server.service ]]; then
    msg_error "No Valkey installation found!"
    exit 1
  fi

  LXCIP=$(ip a s dev eth0 | awk '/inet / {print $2}' | cut -d/ -f1)
  CHOICE=$(msg_menu "Valkey Management" \
    "1" "Update Valkey" \
    "2" "Allow 0.0.0.0 for listening" \
    "3" "Allow only ${LXCIP} for listening")

  case "$CHOICE" in
  1)
    msg_info "Updating Valkey"
    $STD apt update
    $STD apt -y upgrade
    systemctl restart valkey-server
    msg_ok "Updated Valkey"
    ;;
  2)
    msg_info "Setting Valkey to listen on all interfaces"
    sed -i 's/^bind .*/bind 0.0.0.0/' /etc/valkey/valkey.conf
    systemctl restart valkey-server
    msg_ok "Valkey now listens on all interfaces"
    ;;
  3)
    msg_info "Setting Valkey to listen only on ${LXCIP}"
    sed -i "s/^bind .*/bind ${LXCIP}/" /etc/valkey/valkey.conf
    systemctl restart valkey-server
    msg_ok "Valkey now listens only on ${LXCIP}"
    ;;
  esac
}

update_alpine() {
  if [[ ! -f /etc/init.d/valkey ]]; then
    msg_error "No Valkey installation found!"
    exit 1
  fi

  LXCIP=$(ip a s dev eth0 | awk '/inet / {print $2}' | cut -d/ -f1)
  CHOICE=$(msg_menu "Valkey Management" \
    "1" "Update Valkey" \
    "2" "Allow 0.0.0.0 for listening" \
    "3" "Allow only ${LXCIP} for listening")

  case "$CHOICE" in
  1)
    msg_info "Updating Valkey"
    $STD apk update
    $STD apk upgrade valkey
    rc-service valkey restart
    msg_ok "Updated Valkey"
    ;;
  2)
    msg_info "Setting Valkey to listen on all interfaces"
    sed -i 's/^bind .*/bind 0.0.0.0/' /etc/valkey/valkey.conf
    rc-service valkey restart
    msg_ok "Valkey now listens on all interfaces"
    ;;
  3)
    msg_info "Setting Valkey to listen only on ${LXCIP}"
    sed -i "s/^bind .*/bind ${LXCIP}/" /etc/valkey/valkey.conf
    rc-service valkey restart
    msg_ok "Valkey now listens only on ${LXCIP}"
    ;;
  esac
}

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Connect to Valkey CLI using the following command:${CL}"
echo -e "${GATEWAY}${BGN}valkey-cli -h ${IP} -p 6379${CL}"
