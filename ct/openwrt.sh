#!/usr/bin/env bash
if [[ -n "${BUILD_FUNC_URL:-}" && -z "${COMMUNITY_SCRIPTS_URL:-}" && "$BUILD_FUNC_URL" == */misc/build.func ]]; then
  export COMMUNITY_SCRIPTS_URL="${BUILD_FUNC_URL%/misc/build.func}"
fi
source <(curl -fsSL "${BUILD_FUNC_URL:-${COMMUNITY_SCRIPTS_URL:-https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main}/misc/build.func}")

# Copyright (c) 2021-2026 community-scripts ORG
# Author: community-scripts ORG
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://openwrt.org/

APP="OpenWrt"
var_tags="${var_tags:-os;router;network}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-256}"
var_disk="${var_disk:-1}"
var_os="${var_os:-openwrt}"
var_version="${var_version:-25.12}"
var_arm64="${var_arm64:-no}"
var_unprivileged="${var_unprivileged:-1}"
var_tun="${var_tun:-yes}"
var_lan_bridge="${var_lan_bridge:-vmbr0}"
var_wan_bridge="${var_wan_bridge:-vmbr0}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  msg_error "Automated OpenWrt LXC upgrades are not supported. Use OpenWrt's sysupgrade process after reviewing container networking and package compatibility."
  exit
}

start
build_container
description

msg_ok "Completed successfully!\n"
msg_custom "🚀" "${GN}" "${APP} setup has been successfully initialized!"
echo -e "${INFO}${YW} Review WAN/LAN bridge assignments before routing production traffic.${CL}"
echo -e "${INFO}${YW} If you set VLAN tags, ensure the selected Proxmox bridge is VLAN-aware.${CL}"
