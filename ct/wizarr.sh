#!/usr/bin/env bash
source <(curl -s https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: vhsdream
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/wizarrrr/wizarr

APP="Wizarr"
var_tags="${var_tags:-media;arr}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-12}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/wizarr ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  RELEASE=$(curl -s https://api.github.com/repos/wizarrrr/wizarr/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3) }')
  if [[ "${RELEASE}" != "$(cat /opt/wizarr_version.txt)" ]] || [[ ! -f /opt/wizarr_version.txt ]]; then
    msg_info "Stopping $APP"
    systemctl stop wizarr
    msg_ok "Stopped $APP"

    msg_info "Creating Backup"
    BACKUP_FILE="/opt/wizarr_backup_$(date +%F).tar.gz"
    $STD tar -czf "$BACKUP_FILE" /opt/wizarr/{.env,start.sh} /opt/wizarr/database/ &>/dev/null
    msg_ok "Backup Created"

    msg_info "Updating $APP to v${RELEASE}"
    rm -rf /opt/wizarr
    curl -fsSL "https://github.com/wizarrrr/wizarr/archive/refs/tags/${RELEASE}.zip" -o /tmp/"$RELEASE".zip
    unzip -q /tmp/"$RELEASE".zip
    mv wizarr-${RELEASE}/ /opt/wizarr
    cd /opt/wizarr
    setup_uv
    uv -q sync --locked
    $STD uv -q run pybabel compile -d app/translations
    $STD npm --prefix app/static install
    mkdir -p ./.cache
    $STD tar -xf "$BACKUP_PATH" --directory=/
    $STD uv -q run flask db upgrade
    msg_ok "Updated $APP to v${RELEASE}"

    msg_info "Starting $APP"
    systemctl start wizarr
    msg_ok "Started $APP"

    msg_info "Cleaning Up"
    rm -rf "$BACKUP_PATH"
    rm /tmp/"$RELEASE".zip
    msg_ok "Cleanup Completed"

    echo "${RELEASE}" >/opt/wizarr_version.txt
    msg_ok "Update Successful"
  else
    msg_ok "No update required. ${APP} is already at v${RELEASE}"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:5690${CL}"
