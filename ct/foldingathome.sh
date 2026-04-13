#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: 007hacky007
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://foldingathome.org/

APP="Folding@Home"
NSAPP="folding-at-home"
SCRIPT_SLUG="foldingathome"
var_hostname="${var_hostname:-folding-at-home}"
var_tags="${var_tags:-distributed-computing;science}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"
var_gpu="${var_gpu:-yes}"

header_info "$APP"
variables
NSAPP="folding-at-home"
var_install="foldingathome-install"
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if ! dpkg -s fah-client >/dev/null 2>&1; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  local arch current_version deb_url deb_file latest_version
  arch=$(dpkg --print-architecture)
  current_version=$(dpkg-query -W -f='${Version}' fah-client)

  case "${arch}" in
  amd64)
    deb_url="https://download.foldingathome.org/releases/public/fah-client/debian-10-64bit/release/latest.deb"
    ;;
  arm64)
    deb_url="https://download.foldingathome.org/releases/public/fah-client/debian-stable-arm64/release/latest.deb"
    ;;
  *)
    msg_error "Unsupported architecture: ${arch}"
    exit
    ;;
  esac

  deb_file="/tmp/fah-client_latest_${arch}.deb"

  msg_info "Downloading Latest ${APP} Package"
  curl -fsSL "${deb_url}" -o "${deb_file}"
  msg_ok "Downloaded Latest ${APP} Package"

  latest_version=$(dpkg-deb -f "${deb_file}" Version)
  if [[ "${current_version}" == "${latest_version}" ]]; then
    rm -f "${deb_file}"
    msg_ok "No update required. ${APP} is already at v${current_version}"
    exit
  fi

  msg_info "Stopping Service"
  systemctl stop fah-client
  msg_ok "Stopped Service"

  msg_info "Updating ${APP} (${current_version} -> ${latest_version})"
  $STD apt update
  $STD apt install -y "${deb_file}"
  rm -f "${deb_file}"
  msg_ok "Updated ${APP}"

  msg_info "Starting Service"
  systemctl start fah-client
  msg_ok "Started Service"
  msg_ok "Updated successfully!"
  exit
}

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Application was assigned the following IP:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}Address: ${IP}${CL}"
echo -e "${INFO}${YW} Folding@Home config file:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}/etc/fah-client/config.xml${CL}"
echo -e "${INFO}${YW} Use Folding@Home Web Control to manage or link this machine:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}https://v8-5.foldingathome.org/${CL}"
echo -e "${INFO}${YW} Folding@Home v8.5 documentation:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}https://foldingathome.org/guides/v8-5-client-guide/${CL}"
