#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: SunFlowerOwl
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/haugene/docker-transmission-openvpn

APP="transmission-openvpn"
var_tags="${var_tags:-torrent;vpn}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-12}"
var_unprivileged="${var_unprivileged:-1}"
var_tun="${var_tun:-yes}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -d /opt/transmission-openvpn/ ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  
  msg_info "Updating Transmission Web UIs"
  rm -rf /opt/transmission-ui/*
  if check_for_gh_release "flood-for-transmission" "johman10/flood-for-transmission"; then
    fetch_and_deploy_gh_release "flood-for-transmission" "johman10/flood-for-transmission" "tarball" "latest" "/opt/flood-for-transmission"
    mv /opt/flood-for-transmission /opt/transmission-ui/flood
  fi
  if check_for_gh_release "combustion" "Secretmapper/combustion"; then
    fetch_and_deploy_gh_release "combustion" "Secretmapper/combustion" "tarball" "latest" "/opt/combustion"
    mv /opt/combustion /opt/transmission-ui/combustion
  fi
  if check_for_gh_release "transmissionic" "6c65726f79/Transmissionic"; then
    fetch_and_deploy_gh_release "transmissionic" "6c65726f79/Transmissionic" "tarball" "latest" "/opt/transmissionic"
    mv /opt/transmissionic /opt/transmission-ui/transmissionic
  fi
  curl -fsSL -o "Shift-master.tar.gz" "https://github.com/killemov/Shift/archive/master.tar.gz"
  tar xzf Shift-master.tar.gz
  mv Shift-master /opt/transmission-ui/shift
  curl -fsSL -o "kettu-master.tar.gz" "https://github.com/endor/kettu/archive/master.tar.gz"
  tar xzf kettu-master.tar.gz
  mv kettu-master /opt/transmission-ui/kettu
  msg_ok "Updated Transmission Web UIs"
  
  msg_info "Updating Dependencies"
  $STD apt-get update
  $STD apt-get -y upgrade
  msg_ok "Updated Dependencies"

  if check_for_gh_release "docker-transmission-openvpn" "haugene/docker-transmission-openvpn"; then
    msg_info "Stopping $APP"
    systemctl stop openvpn-custom
    msg_ok "Stopped $APP"

    msg_info "Updating ${APP} LXC"
    fetch_and_deploy_gh_release "docker-transmission-openvpn" "haugene/docker-transmission-openvpn" "tarball" "latest" "/opt/docker-transmission-openvpn"
    rm -rf /etc/openvpn/* /etc/transmission/* /etc/scripts/* /opt/privoxy/*
    cp -r /opt/docker-transmission-openvpn/openvpn/* /etc/openvpn/
    cp -r /opt/docker-transmission-openvpn/transmission/* /etc/transmission/
    cp -r /opt/docker-transmission-openvpn/scripts/* /etc/scripts/
    cp -r /opt/docker-transmission-openvpn/privoxy/scripts/* /opt/privoxy/
    chmod +x /etc/openvpn/*.sh || true
    chmod +x /etc/scripts/*.sh || true
    chmod +x /opt/privoxy/*.sh || true
    msg_ok "Updated ${APP} LXC"

    msg_info "Starting $APP"
    systemctl start openvpn-custom
    msg_ok "Started $APP"
  fi

  msg_info "Cleaning up"
  $STD apt-get -y autoremove
  $STD apt-get -y autoclean
  rm -rf /opt/docker-transmission-openvpn
  rm -f Shift-master.tar.gz
  rm -f kettu-master.tar.gz
  msg_ok "Cleaned"

  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:9091${CL}"
