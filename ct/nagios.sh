#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: GitHub Copilot (GPT-5.3-Codex)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/NagiosEnterprises/nagioscore

APP="Nagios"
var_tags="${var_tags:-monitoring;alerts;infrastructure}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-20}"
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

  if [[ ! -f /etc/nagios4/nagios.cfg ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Updating Nagios Packages"
  $STD apt update
  $STD apt install -y --only-upgrade nagios4 nagios-plugins-contrib apache2
  msg_ok "Updated Nagios Packages"

  msg_info "Restarting Services"
  systemctl restart nagios4
  systemctl restart apache2
  msg_ok "Restarted Services"

  msg_ok "Updated successfully!"
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}/nagios4${CL}"
