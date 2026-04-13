#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: 007hacky007
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://www.squid-cache.org/

APP="Squid"
var_tags="${var_tags:-proxy}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-4}"
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
  if [[ ! -f /etc/squid/squid.conf ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  msg_info "Updating ${APP}"
  $STD apt-get update
  $STD apt-get -y upgrade
  msg_info "Validating Squid Configuration"
  $STD squid -k parse
  msg_ok "Validated Squid Configuration"
  msg_info "Restarting Squid"
  systemctl restart squid
  msg_ok "Restarted Squid"
  msg_ok "Updated ${APP}"
  msg_ok "Updated successfully!"
  exit
}

start
build_container
description

SQUID_USER=""
SQUID_PASS=""
if pct exec "$CTID" -- test -f /root/squid.creds 2>/dev/null; then
  SQUID_USER=$(pct exec "$CTID" -- awk -F': ' '/^Username:/ {print $2}' /root/squid.creds 2>/dev/null | tr -d '\r')
  SQUID_PASS=$(pct exec "$CTID" -- awk -F': ' '/^Password:/ {print $2}' /root/squid.creds 2>/dev/null | tr -d '\r')
fi

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Proxy endpoint:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}${IP}:3128${CL}"
if [[ -n "$SQUID_USER" && -n "$SQUID_PASS" ]]; then
  echo -e "${INFO}${YW} Credentials:${CL}"
  echo -e "${TAB}${BGN}Username: ${SQUID_USER}${CL}"
  echo -e "${TAB}${BGN}Password: ${SQUID_PASS}${CL}"
else
  echo -e "${INFO}${YW} Credentials are stored in the container at /root/squid.creds.${CL}"
fi
echo -e "${INFO}${YW} These details are also available in the container MOTD.${CL}"
