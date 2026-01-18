#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: rdeangel
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/rdeangel/InstradaOGM


APP="InstradaOGM"
var_tags="${var_tags:-firewall;management}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-7}"
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
  if [[ ! -d /opt/instradaogm ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "instradaogm" "rdeangel/InstradaOGM"; then
    msg_info "Stopping Service"
    systemctl stop instradaogm
    msg_ok "Stopped Service"

    msg_info "Updating InstradaOGM"
    rm -rf /tmp/*
    cp -p /opt/instradaogm/.env /opt
    mkdir /opt/data.backup
    cp -Rp /opt/instradaogm/data/backups /opt/data.backup/
    cp -Rp /opt/instradaogm/data/db /opt/data.backup/
    rm -rf /opt/instradaogm/*
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "instradaogm" "rdeangel/InstradaOGM" "prebuild" "latest" "/opt/instradaogm" "instradaogm-sqlite-v*-amd64.tar.gz"
    cp -p /opt/.env /opt/instradaogm/.env
    cp -Rp /opt/data.backup/backups /opt/instradaogm/data/
    cp -Rp /opt/data.backup/db /opt/instradaogm/data/
    rm -Rf /opt/data.backup
    rm /opt/.env

    cat <<EOF >/etc/systemd/system/instradaogm.service
[Unit]
Description=InstradaOGM Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/instradaogm
ExecStart=/usr/bin/node server.js
Restart=always
RestartSec=10
Environment=NODE_ENV=production
Environment=PORT=3000

[Install]
WantedBy=multi-user.target
EOF
    $STD systemctl daemon-reload

    cd /opt/instradaogm || exit

    export NODE_OPTIONS='--max-old-space-size=512'
    $STD npm run setup-dirs
    $STD npm run db:migrate
    $STD npm run db:seed
    unset NODE_OPTIONS

    msg_ok "Updated InstradaOGM"

    msg_info "Starting Service"
    $STD systemctl start instradaogm
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
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:3000${CL}"
