#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/DragoQC/ProxmoxVE/main/misc/build.func)

#source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: DragoQC
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://discopanel.app/

APP="DiscoPanel"
var_tags="${var_tags:-gaming}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-15}"
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

  if [[ ! -d "/opt/discopanel" ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "discopanel" "nickheyer/discopanel"; then
    msg_info "Stopping Service"
    systemctl stop discopanel
    msg_ok "Stopped Service"

    msg_info "Creating Backup"
    mkdir -p /opt/discopanel_backup_last
    backup_items=(
      "/opt/discopanel/data/discopanel.db"
      "/opt/discopanel/data/.recovery_key"
      "/opt/discopanel/data/servers"
    )
    for item in "${backup_items[@]}"; do
      if [[ -e "$item" ]]; then
          cp -r "$item" /opt/discopanel_backup_last/
      fi
    done
    msg_ok "Created Backup"

    rm -rf /opt/discopanel

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "discopanel" "nickheyer/discopanel" "tarball" "latest" "/opt/discopanel"
    msg_info "Setting up DiscoPanel"
    cd /opt/discopanel/web/discopanel
    $STD npm install
    $STD npm run build
    cd /opt/discopanel
    $STD go build -o discopanel cmd/discopanel/main.go
    msg_ok "Setup DiscoPanel"

    msg_info "Restoring Data"
    cp -r /opt/discopanel_backup_last/* /opt/discopanel/data/
    msg_ok "Restored Data"

    msg_info "Starting Service"
    systemctl start discopanel
    msg_ok "Started Service"
    msg_ok "Updated Successfully!"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8080${CL}"
