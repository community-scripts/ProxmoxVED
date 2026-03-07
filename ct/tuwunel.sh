#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/derickson2402/ProxmoxVE/main/misc/build.func)
# Copyright (c) 2021-2026 tteck
# Author: Dan Erickson (derickson2402)
# License: MIT | https://github.com/derickson2402/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/matrix-construct/tuwunel

APP="Tuwunel"
var_tags="${var_tags:-communication}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-10}"
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

  if [[ ! -d /etc/tuwunel ]]; then
      msg_error "No ${APP} Installation Found!"
      exit
  fi
  msg_info "Found existing ${APP} installation, checking for updates"

  tuwunel_repo="matrix-construct/tuwunel"
  tuwunel_release=$(get_latest_github_release "${tuwunel_repo}")
  current_version_path=/opt/Tuwunel_version.txt
  current_arch_path=/opt/Tuwunel_arch.txt
  current_cpu_cap_path=/opt/tuwunel/cpu_cap.txt
  if [[ ! -f ${current_version_path} ]] || [[ "${tuwunel_release}" != "$(cat ${current_version_path})" ]]; then
    msg_info "Updating ${APP}: v$(cat ${current_version_path}) ==> v${tuwunel_release}"
    # Back up user settings before installing, then restore on success. The
    # deb package shouldn't overwrite their settings, but we do this just
    # in case
    cp -a /etc/tuwunel/tuwunel.toml /tmp/tuwunel.toml
    deb_url="https://github.com/${tuwunel_repo}/releases/download/v${tuwunel_release}/v${tuwunel_release}-release-all-$(cat ${current_arch_path})-$(cat ${current_cpu_cap_path})-linux-gnu-tuwunel.deb"
    deb_pkg_path="/tmp/tuwunel.deb"
    curl -fsSL -o "${deb_pkg_path}" "${deb_url}"
    $STD dpkg -i "${deb_pkg_path}"
    mv /tmp/tuwunel.toml /etc/tuwunel/tuwunel.toml
    rm -f "${deb_pkg_path}"
    echo "${tuwunel_release}" > "${current_version_path}"
  else
    msg_ok "${APP} is already at latest version v${tuwunel_release}."
  fi

  msg_ok "Updated ${APP} successfully!"
  exit
}

function health_check() {
  header_info

  if [[ ! -f /opt/Tuwunel_version.txt ]]; then
    msg_error "Application not found!"
    exit 1
  fi

  if ! systemctl is-active --quiet tuwunel; then
    msg_error "Application service not running"
    exit 1
  fi

  msg_ok "Health check passed"
}

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8008/${CL}"
