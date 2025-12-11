#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/RostislavDugin/postgresus

APP="Postgresus"
var_tags="${var_tags:-backup;postgresql;database}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
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

  if [[ ! -f /opt/postgresus/postgresus ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "RostislavDugin" "postgresus"; then
    msg_info "Stopping ${APP}"
    systemctl stop postgresus
    msg_ok "Stopped ${APP}"

    RELEASE=$(curl -fsSL https://api.github.com/repos/RostislavDugin/postgresus/releases/latest | grep "tag_name" | awk '{print substr($2, 3, length($2)-4) }')

    msg_info "Backing up Configuration"
    cp /opt/postgresus/.env /tmp/postgresus.env.bak
    msg_ok "Backed up Configuration"

    msg_info "Building new version v${RELEASE}"
    cd /tmp
    curl -fsSL "https://github.com/RostislavDugin/postgresus/archive/refs/tags/v${RELEASE}.tar.gz" -o postgresus.tar.gz
    tar -xzf postgresus.tar.gz
    cd "postgresus-${RELEASE}"

    # Build frontend
    cd frontend
    $STD npm ci
    $STD npm run build
    cd ..

    # Build backend
    cd backend
    $STD go mod download
    CGO_ENABLED=0 go build -o /opt/postgresus/postgresus.new ./cmd/main.go
    cd ..

    # Update files
    mv /opt/postgresus/postgresus /opt/postgresus/postgresus.backup
    mv /opt/postgresus/postgresus.new /opt/postgresus/postgresus
    chmod +x /opt/postgresus/postgresus

    cp -r frontend/dist /opt/postgresus/ui
    cp -r backend/migrations /opt/postgresus/

    cd /tmp && rm -rf "postgresus-${RELEASE}" postgresus.tar.gz
    msg_ok "Built new version v${RELEASE}"

    msg_info "Restoring Configuration"
    cp /tmp/postgresus.env.bak /opt/postgresus/.env
    rm -f /tmp/postgresus.env.bak
    chown -R postgresus:postgresus /opt/postgresus
    msg_ok "Restored Configuration"

    msg_info "Starting ${APP}"
    systemctl start postgresus
    msg_ok "Started ${APP}"

    msg_ok "Updated Successfully to v${RELEASE}"
  else
    msg_ok "No update available"
  fi
  exit
}start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:4005${CL}"
