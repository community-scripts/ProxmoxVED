#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Decrux (devdecrux)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/devdecrux/pocketr-app

APP="Pocketr"
var_tags="${var_tags:-finance;budgeting}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

if command -v pveversion >/dev/null 2>&1; then
  if [[ -n "${POCKETR_DB_MODE+x}" ]]; then
    POCKETR_DB_MODE_WAS_SET="yes"
  else
    POCKETR_DB_MODE_WAS_SET="no"
  fi
  POCKETR_DB_MODE="${POCKETR_DB_MODE:-internal}"
  if [[ "${POCKETR_DB_MODE}" != "internal" && "${POCKETR_DB_MODE}" != "external" ]]; then
    msg_error "POCKETR_DB_MODE must be 'internal' or 'external'"
    exit 1
  fi

  if [[ "${POCKETR_DB_MODE_WAS_SET}" == "no" && -t 0 && -z "${POCKETR_DB_URL:-${DB_URL:-}}" && -z "${POCKETR_DB_USERNAME:-${DB_USERNAME:-}}" && -z "${POCKETR_DB_PASSWORD:-${DB_PASSWORD:-}}" ]]; then
    if whiptail --backtitle "Proxmox VE Helper Scripts" --title "Pocketr Database" --yesno "Use an external PostgreSQL database?\n\nDefault: No, install PostgreSQL inside this LXC." 10 68; then
      POCKETR_DB_MODE="external"
    fi
  fi

  if [[ "${POCKETR_DB_MODE}" == "external" ]]; then
    POCKETR_DB_URL="${POCKETR_DB_URL:-${DB_URL:-}}"
    POCKETR_DB_USERNAME="${POCKETR_DB_USERNAME:-${DB_USERNAME:-}}"
    POCKETR_DB_PASSWORD="${POCKETR_DB_PASSWORD:-${DB_PASSWORD:-}}"

    if [[ -z "${POCKETR_DB_URL}" ]]; then
      POCKETR_DB_URL=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "Pocketr Database URL" --inputbox "External PostgreSQL JDBC URL:" 10 78 "jdbc:postgresql://postgres.example.lan:5432/pocketr_db" 3>&1 1>&2 2>&3) || exit 1
    fi
    if [[ -z "${POCKETR_DB_USERNAME}" ]]; then
      POCKETR_DB_USERNAME=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "Pocketr Database User" --inputbox "External PostgreSQL username:" 10 68 "pocketr_user" 3>&1 1>&2 2>&3) || exit 1
    fi
    if [[ -z "${POCKETR_DB_PASSWORD}" ]]; then
      POCKETR_DB_PASSWORD=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "Pocketr Database Password" --passwordbox "External PostgreSQL password:" 10 68 3>&1 1>&2 2>&3) || exit 1
    fi

    if [[ -z "${POCKETR_DB_URL}" || -z "${POCKETR_DB_USERNAME}" || -z "${POCKETR_DB_PASSWORD}" ]]; then
      msg_error "External PostgreSQL requires POCKETR_DB_URL, POCKETR_DB_USERNAME, and POCKETR_DB_PASSWORD"
      exit 1
    fi
  fi

  export POCKETR_DB_MODE
  export POCKETR_DB_URL
  export POCKETR_DB_USERNAME
  export POCKETR_DB_PASSWORD
  unset POCKETR_DB_MODE_WAS_SET
fi

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/pocketr ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "pocketr" "devdecrux/pocketr-app"; then
    msg_info "Stopping Service"
    systemctl stop pocketr
    msg_ok "Stopped Service"

    msg_info "Backing up Data"
    cp /opt/pocketr/.env /opt/pocketr.env.bak
    cp -r /opt/pocketr/data /opt/pocketr_data_backup
    msg_ok "Backed up Data"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "pocketr" "devdecrux/pocketr-app" "singlefile" "latest" "/opt/pocketr" "pocketr-*.jar"

    msg_info "Restoring Data"
    cp /opt/pocketr.env.bak /opt/pocketr/.env
    cp -r /opt/pocketr_data_backup/. /opt/pocketr/data
    rm -f /opt/pocketr.env.bak
    rm -rf /opt/pocketr_data_backup
    msg_ok "Restored Data"

    msg_info "Starting Service"
    systemctl start pocketr
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
if pct exec "$CTID" -- test -f /opt/pocketr/.service-not-started 2>/dev/null; then
  echo -e "${INFO}${YW} Pocketr service is enabled but was not started because the external PostgreSQL connection failed.${CL}"
  echo -e "${TAB}${YW} Edit /opt/pocketr/.env inside the LXC, then run:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}systemctl start pocketr${CL}"
  echo -e "${TAB}${YW} Enabled services also start automatically after an LXC reboot.${CL}"
else
  echo -e "${INFO}${YW} Access it using the following URL:${CL}"
  echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8081/frontend${CL}"
fi
