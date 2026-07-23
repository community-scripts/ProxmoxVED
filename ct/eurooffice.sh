#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../misc/build.func" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_URL:-https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main}/misc/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Thieneret
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/Euro-Office

APP="eurooffice"
var_tags="${var_tags:-office}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-10}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-no}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  if check_for_gh_release "EuroOffice" "Euro-Office/DocumentServer" "latest"; then
    msg_info "Stoping services"
    systemctl stop ds-docservice ds-converter ds-metrics nginx
	msg_ok "Services stoped"
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "EuroOffice" "Euro-Office/DocumentServer" "binary" "latest" "/opt/eurooffice" "euro-office-documentserver_*.deb"
	msg_info "Starting services"
	systemctl restart ds-docservice ds-converter ds-metrics
    for i in {1..10}; do
      if [[ $(systemctl is-active ds-docservice) == active && $(systemctl is-active ds-converter) == active && $(systemctl is-active ds-metrics) == active ]]; then
    	break
      fi
      sleep 1
    done
    systemctl restart nginx
    msg_ok "Services started"
	msg_ok "Updated successfully!"
  fi
  exit
}

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}${CL}"
echo -e "${INFO}${YW} Secret Key is located in ${HOME}/.euro-office.creds${CL}"
