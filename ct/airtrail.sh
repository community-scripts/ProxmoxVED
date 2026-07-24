#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Majiiin
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/johanohly/AirTrail

APP="AirTrail"
var_tags="${var_tags:-travel;flight-tracker}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-10}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-no}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/airtrail ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "airtrail" "johanohly/AirTrail"; then
    msg_info "Stopping Service"
    systemctl stop airtrail
    msg_ok "Stopped Service"

    create_backup /opt/airtrail/.env /opt/airtrail/uploads

    NODE_VERSION="22" setup_nodejs
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "airtrail" "johanohly/AirTrail" "tarball"

    restore_backup

    msg_info "Updating AirTrail"
    cd /opt/airtrail
    $STD bun install --frozen-lockfile
    $STD bun run build
    $STD bun run db:migrate-deploy
    msg_ok "Updated AirTrail"

    msg_info "Updating Service"
    cat <<EOF >/etc/systemd/system/airtrail.service
[Unit]
Description=AirTrail Flight Tracker
After=network.target postgresql.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/airtrail
EnvironmentFile=/opt/airtrail/.env
ExecStart=/usr/bin/node /opt/airtrail/build
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    msg_ok "Updated Service"

    msg_info "Starting Service"
    systemctl start airtrail
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Access it using the following URL:${CL}"
echo -e "${GATEWAY}${BGN}http://${IP}:3000${CL}"
