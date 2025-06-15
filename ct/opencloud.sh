#!/usr/bin/env bash
source <(curl -s https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: vhsdream
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://opencloud.eu

APP="OpenCloud"
var_tags="${var_tags:-files;cloud}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-6}"
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

  if [[ ! -d /etc/opencloud ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  RELEASE=$(curl -s https://api.github.com/repos/opencloud-eu/opencloud/releases/latest | grep "tag_name" | awk '{print substr($2, 3, length($2)-4) }')
  if [[ "${RELEASE}" != "$(cat /etc/opencloud/version)" ]] || [[ ! -f /etc/opencloud/version ]]; then
    msg_info "Stopping $APP"
    systemctl stop opencloud opencloud-wopi
    msg_ok "Stopped $APP"

    msg_info "Updating $APP to v${RELEASE}"
    curl -fsSL "https://github.com/opencloud-eu/opencloud/releases/download/v${RELEASE}/opencloud-${RELEASE}-linux-amd64" -o /usr/bin/opencloud
    chmod +x /usr/bin/opencloud
    msg_ok "Updated $APP to v${RELEASE}"

    msg_info "Starting $APP"
    systemctl start opencloud opencloud-wopi
    msg_ok "Started $APP"

    echo "${RELEASE}" >/etc/opencloud/version
    msg_ok "Update Successful"
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
echo -e "${TAB}${GATEWAY}${BGN}https://<your-OpenCloud-domain>${CL}"
