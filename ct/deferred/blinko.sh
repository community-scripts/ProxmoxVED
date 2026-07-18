#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../misc/build.func" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_URL:-https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main}/misc/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://blinko.space/

APP="Blinko"
var_tags="${var_tags:-notes;ai;knowledge}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-8}"
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

  if [[ ! -d /opt/blinko ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "blinko" "blinkospace/blinko"; then
    msg_info "Stopping Service"
    systemctl stop blinko
    msg_ok "Stopped Service"

    msg_info "Backing up Data"
    cp /opt/blinko/.env /opt/blinko.env.bak
    msg_ok "Backed up Data"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "blinko" "blinkospace/blinko" "tarball"

    msg_info "Restoring Data"
    cp /opt/blinko.env.bak /opt/blinko/.env
    rm -f /opt/blinko.env.bak
    msg_ok "Restored Data"

    msg_info "Updating Application"
    cd /opt/blinko
    $STD bun install
    $STD bun run build:web
    mkdir -p /opt/blinko/dist/public/dist
    cp -r /opt/blinko/node_modules/vditor/dist/{js,css,images} /opt/blinko/dist/public/dist/
    $STD bun run build:seed
    $STD bun run prisma:generate
    $STD bun run prisma:migrate:deploy
    $STD bun run seed
    $STD npm install --force @node-rs/crc32 lightningcss "sharp@0.34.1" "prisma@5.21.1"
    $STD npm install -g "prisma@5.21.1"
    $STD npm install --force "sqlite3@5.1.7"
    $STD npm install --force llamaindex "@langchain/community@0.3.40"
    $STD npm install --force @libsql/client @libsql/core
    $STD npx prisma generate
    msg_ok "Updated Application"

    msg_info "Updating Service"
    cat <<EOF >/etc/systemd/system/blinko.service
[Unit]
Description=Blinko Note-Taking App
After=network.target postgresql.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/blinko
ExecStartPre=/bin/bash -c "mkdir -p /opt/blinko/server/public && cp -r /opt/blinko/dist/public/. /opt/blinko/server/public/"
ExecStart=/usr/bin/node --env-file=/opt/blinko/.env /opt/blinko/dist/index.js
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    msg_ok "Updated Service"

    msg_info "Starting Service"
    systemctl start blinko
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
echo -e "${INFO}${YW}Access it using the following URL:${CL}"
echo -e "${GATEWAY}${BGN}http://${IP}:1111/signup${CL}"
