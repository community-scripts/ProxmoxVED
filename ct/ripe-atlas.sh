#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2026 Juan Lago
# Author: Juan Lago (juanparati)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/RIPE-NCC/ripe-atlas-software-probe

APP="RIPE-Atlas"
var_tags="${var_tags:-network;monitoring}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-256}"
var_disk="${var_disk:-3}"
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

  if [[ ! -f /etc/ripe-atlas/probe_key.pub ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Updating ${APP}"
  $STD apt-get update
  $STD apt-get -y install --only-upgrade ripe-atlas-probe
  msg_ok "Updated ${APP}"
  exit
}

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Register your probe at:${CL}"
echo -e "${GATEWAY}${BGN}https://atlas.ripe.net/apply/swprobe/${CL}"
PROBE_KEY=$(pct exec "$CTID" -- cat /etc/ripe-atlas/probe_key.pub 2>/dev/null || true)
if [[ -n "$PROBE_KEY" ]]; then
  echo -e "${INFO}${YW}Public key (also in /etc/ripe-atlas/probe_key.pub inside the container):${CL}"
  echo -e "${BGN}${PROBE_KEY}${CL}"
else
  echo -e "${INFO}${YW}Retrieve the public key with:${CL}"
  echo -e "${BGN}pct exec ${CTID} -- cat /etc/ripe-atlas/probe_key.pub${CL}"
fi
