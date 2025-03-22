#!/usr/bin/env bash
source <(curl -s https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: tteck (tteckster) | Co-Author: Slaviša Arežina (tremor021)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://www.qbittorrent.org/

APP="qBittorrent"
var_tags="torrent"
var_cpu="2"
var_ram="2048"
var_disk="8"
var_os="debian"
var_version="12"
var_unprivileged="1"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -f /etc/systemd/system/qbittorrent-nox.service ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  if [[ ! -f /opt/${APP}_version.txt ]]; then
    touch /opt/${APP}_version.txt
    mkdir -p $HOME/.config/qBittorrent/
    mv /.config/qBittorrent $HOME/.config/
    $STD apt-get remove --purge -y qbittorrent-nox
    rm -f /etc/systemd/system/qbittorrent-nox.service
    sed -i 's@ExecStart=/usr/bin/qbittorrent-nox@ExecStart=/opt/qbittorrent/qbittorrent-nox@g' /etc/systemd/system/qbittorrent-nox.service
  fi
  FULLRELEASE=$(curl -s https://api.github.com/repos/userdocs/qbittorrent-nox-static/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3) }')
  RELEASE=$(echo $RELEASE | cut -c 9-13)
  if [[ ! -f /opt/${APP}_version.txt ]] || [[ "${RELEASE}" != "$(cat /opt/${APP}_version.txt)" ]]; then
    msg_info "Stopping Service"
    systemctl stop qbittorrent-nox
    msg_ok "Stopped Service"

    msg_info "Updating ${APP} to v${RELEASE}"
    rm -f /opt/qbittorrent/qbittorrent-nox
    wget -q "https://github.com/userdocs/qbittorrent-nox-static/releases/download/${FULLRELEASE}/x86_64-qbittorrent-nox -O /opt/qbittorrent/qbittorrent-nox"
    chmod +x /opt/qbittorrent/qbittorrent-nox
    echo "${RELEASE}" >/opt/${APP}_version.txt
    msg_ok "Updated $APP to v${RELEASE}"

    msg_info "Starting Service"
    systemctl start qbittorrent-nox
    msg_ok "Started Service"
    msg_ok "Updated Successfully"
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
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8090${CL}"
