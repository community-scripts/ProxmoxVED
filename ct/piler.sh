#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/GoldenSpringness/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/GoldenSpringness/ProxmoxVED/raw/main/LICENSE
# Source: https://www.mailpiler.org/

APP="Piler"
var_tags="${var_tags:-email;archive;smtp}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-20}"
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

  if [[ ! -f /etc/piler/piler.conf ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  RELEASE_NEW=$(curl -fsSL https://www.mailpiler.org/download.php | grep -oP 'piler-\K[0-9]+\.[0-9]+\.[0-9]+' | head -1)
  RELEASE_OLD=$(pilerd -v 2>/dev/null | grep -oP 'version \K[0-9]+\.[0-9]+\.[0-9]+' || echo "unknown")

  if [[ "${RELEASE_NEW}" != "${RELEASE_OLD}" ]]; then
    msg_info "Stopping Piler Services"
    $STD systemctl stop piler
    $STD systemctl stop manticore
    msg_ok "Stopped Piler Services"

    msg_info "Backing up Configuration"
    cp /etc/piler/piler.conf /tmp/piler.conf.bak
    msg_ok "Backed up Configuration"

    msg_info "Updating to v${RELEASE_NEW}"
    cd /tmp
    curl -fsSL "https://bitbucket.org/jsuto/piler/downloads/piler-${RELEASE_NEW}.tar.gz" -o piler.tar.gz
    tar -xzf piler.tar.gz
    cd "piler-${RELEASE_NEW}"

    $STD ./configure \
      --localstatedir=/var \
      --with-database=mysql \
      --sysconfdir=/etc/piler \
      --enable-memcached

    $STD make
    $STD make install
    $STD ldconfig

    cd /tmp && rm -rf "piler-${RELEASE_NEW}" piler.tar.gz
    msg_ok "Updated to v${RELEASE_NEW}"

    msg_info "Restoring Configuration"
    cp /tmp/piler.conf.bak /etc/piler/piler.conf
    rm -f /tmp/piler.conf.bak
    chown piler:piler /etc/piler/piler.conf
    msg_ok "Restored Configuration"

    msg_info "Starting Piler Services"
    $STD systemctl start manticore
    $STD systemctl start piler
    msg_ok "Started Piler Services"
    msg_ok "Updated Successfully to v${RELEASE_NEW}"
  else
    msg_ok "No update available (current: v${RELEASE_OLD})"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}${CL}"
