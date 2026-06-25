#!/usr/bin/env bash
source <(curl -fsSL "${COMMUNITY_SCRIPTS_URL:-https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main}/misc/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/lemonade-sdk/lemonade

APP="Lemonade-Server"
var_tags="${var_tags:-ai}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-8192}"
var_disk="${var_disk:-80}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-no}"
var_unprivileged="${var_unprivileged:-1}"
var_gpu="${var_gpu:-yes}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if ! command -v lemonade &>/dev/null; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "lemonade-server" "lemonade-sdk/lemonade"; then
    msg_info "Stopping Service"
    systemctl stop lemond
    msg_ok "Stopped Service"

    if ! fetch_and_deploy_gh_release "lemonade-server" "lemonade-sdk/lemonade" "binary" "latest" "/tmp" "lemonade-server_*-debian13_amd64.deb"; then
      msg_error "Download or deployment failed – check network connectivity and GitHub API availability"
      systemctl start lemond
      exit 250
    fi
    msg_ok "Updated Lemonade Server"

    msg_info "Starting Service"
    systemctl start lemond
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Access it using the following URL:${CL}"
echo -e "${GATEWAY}${BGN}http://${IP}:13305${CL}"
echo -e "${INFO}${YW}Security: host is set to 0.0.0.0 — set LEMONADE_API_KEY via a systemd override:${CL}"
echo -e "${TAB3}mkdir -p /etc/systemd/system/lemond.service.d${CL}"
echo -e "${TAB3}printf '%s\n' '[Service]' 'Environment=LEMONADE_API_KEY=your-secret-key' > /etc/systemd/system/lemond.service.d/override.conf${CL}"
echo -e "${TAB3}systemctl daemon-reload && systemctl restart lemond${CL}"
echo -e "${INFO}${YW}Docs: https://lemonade-server.ai/guide/configuration/${CL}"
echo -e "${INFO}${YW}Note: models download on demand — increase disk size for large models.${CL}"
