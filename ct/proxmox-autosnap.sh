#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Kr1sCode
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/Kr1sCode/proxmox-autosnap

APP="proxmox-autosnap"
var_tags="${var_tags:-proxmox;snapshot;backup}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-3}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/autosnap ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Updating ${APP}"
  tmp_dir=$(mktemp -d)
  curl -fsSL "https://github.com/Kr1sCode/proxmox-autosnap/archive/refs/heads/main.tar.gz" | tar -xz -C "$tmp_dir"
  src=$(find "$tmp_dir" -mindepth 1 -maxdepth 1 -type d | head -1)
  cp -r "$src"/app/. /opt/autosnap/
  cp "$src"/systemd/*.service "$src"/systemd/*.timer /etc/systemd/system/
  rm -rf "$tmp_dir"
  systemctl daemon-reload
  systemctl restart autosnap-web.service
  msg_ok "Updated ${APP}"
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}${CL}"
echo -e "${INFO}${YW}On first access, complete the setup wizard (Proxmox host + API token).${CL}"
