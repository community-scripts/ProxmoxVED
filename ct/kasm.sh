#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: Omar Minaya
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://www.kasmweb.com/docs/latest/index.html

APP="Kasm"
var_tags="${var_tags:-os}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4192}"
var_disk="${var_disk:-30}"
var_os="${var_os:-debian}"
var_version="${var_version:-12}"
var_unprivileged="${var_unprivileged:-0}"
var_fuse="${var_fuse:-yes}"
var_tun="${var_tun:-yes}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/kasm ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  RELEASE=$(curl -fsSL 'https://www.kasmweb.com/downloads' | grep -o 'https://kasm-static-content.s3.amazonaws.com/kasm_release_[^"]*\.tar\.gz' | head -n 1 | sed -E 's/.*release_(.*)\.tar\.gz/\1/')
  if [[ "${RELEASE}" != "$(cat /opt/${APP}_version.txt)" ]] || [[ ! -f /opt/${APP}_version.txt ]]; then
    msg_info "Updating ${APP} to v${RELEASE}"
    temp_file=$(mktemp)
    curl -fsSL "https://kasm-static-content.s3.amazonaws.com/kasm_release_${RELEASE}.tar.gz" -o "$temp_file"
    tar zxf "$temp_file"
    chmod 777 /opt/kasm/backups/
    mv /opt/kasm/1.*/certs/kasm_nginx.crt /opt/kasm/kasm_nginx.crt_bak
    printf 'y\n' | $STD sudo bash /tmp/kasm_release/upgrade.sh
    $STD sudo bash /tmp/kasm_release/upgrade.sh
    echo "${RELEASE}" >/opt/${APP}_version.txt
    msg_ok "Updated ${APP} to v${RELEASE}"

    msg_info "Cleaning up"
    rm -f "$temp_file"
    rm -rf /tmp/kasm_release
    $STD apt-get -y autoremove
    $STD apt-get -y autoclean
    msg_ok "Cleaned"
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
echo -e "${TAB}${GATEWAY}${BGN}https://${IP}${CL}"
