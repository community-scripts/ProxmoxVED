#!/usr/bin/env bash
COMMUNITY_SCRIPTS_URL="${COMMUNITY_SCRIPTS_URL:-https://git.community-scripts.org/community-scripts/ProxmoxVED/raw/branch/main}"
source <(curl -fsSL "$COMMUNITY_SCRIPTS_URL/misc/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: PouletteMC
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://surrealdb.com

APP="SurrealDB"
var_tags="${var_tags:-database;nosql}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-1024}"
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

  if [[ ! -f /usr/local/bin/surreal ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  UPD=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "${APP} Management" \
    --menu "Select an option:" 12 58 3 \
    "1" "Update SurrealDB" \
    "2" "Switch to Memory Storage" \
    "3" "Switch to Disk Storage (RocksDB)" \
    3>&1 1>&2 2>&3) || exit

  case "$UPD" in
  1)
    RELEASE=$(curl -fsSL https://api.github.com/repos/surrealdb/surrealdb/releases/latest | grep "tag_name" | awk '{print substr($2, 3, length($2)-4) }')
    if [[ "${RELEASE}" != "$(cat /opt/${APP}_version.txt 2>/dev/null)" ]] || [[ ! -f /opt/${APP}_version.txt ]]; then
      msg_info "Stopping ${APP}"
      systemctl stop surrealdb
      msg_ok "Stopped ${APP}"

      msg_info "Updating ${APP} to v${RELEASE}"
      $STD bash <(curl -sSf https://install.surrealdb.com)
      echo "${RELEASE}" >/opt/${APP}_version.txt
      msg_ok "Updated ${APP} to v${RELEASE}"

      msg_info "Starting ${APP}"
      systemctl start surrealdb
      msg_ok "Started ${APP}"

      msg_ok "Update Successful"
    else
      msg_ok "No update required. ${APP} is already at v${RELEASE}"
    fi
    ;;
  2)
    msg_info "Switching to Memory Storage"
    sed -i 's|^ExecStart=.*|ExecStart=/usr/local/bin/surreal start --bind 0.0.0.0:8000 --user root --pass ${SURREALDB_PASS} memory|' /etc/systemd/system/surrealdb.service
    systemctl daemon-reload
    systemctl restart surrealdb
    msg_ok "Switched to Memory Storage"
    msg_ok "Warning: Data will not persist across restarts"
    ;;
  3)
    msg_info "Switching to Disk Storage (RocksDB)"
    mkdir -p /opt/surrealdb/data
    sed -i 's|^ExecStart=.*|ExecStart=/usr/local/bin/surreal start --bind 0.0.0.0:8000 rocksdb:///opt/surrealdb/data/srdb.db|' /etc/systemd/system/surrealdb.service
    systemctl daemon-reload
    systemctl restart surrealdb
    msg_ok "Switched to Disk Storage (RocksDB)"
    ;;
  esac
  exit
}

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8000${CL}"
