#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: CrazyWolf13
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/arunavo4/gitea-mirror

APP="gitea-mirror"
var_tags="${var_tags:-arr;dashboard}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-1024}"
var_disk="${var_disk:-5}"
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
  if [[ ! -d /opt/gite-mirror ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  RELEASE=$(curl -fsSL https://api.github.com/repos/arunavo4/gitea-mirror/releases/latest | grep "tag_name" | awk '{print substr($2, 3, length($2)-4) }')
  if [[ ! -f /opt/${APP}_version.txt ]] || [[ "${RELEASE}" != "$(cat /opt/${APP}_version.txt)" ]]; then

    msg_info "Stopping Services (Patience)"
    systemctl stop gitea-mirror
    msg_ok "Services Stopped"

    msg_info "Backup Data"
    mkdir -p /opt/homarr-data-backup
    cp /opt/homarr/.env /opt/homarr-data-backup/.env
    msg_ok "Backup Data"

    msg_info "Installing Bun"
    export BUN_INSTALL=/opt/bun
    curl -fsSL https://bun.sh/install | bash
    ln -sf /opt/bun/bin/bun /usr/local/bin/bun
    ln -sf /opt/bun/bin/bun /usr/local/bin/bunx
    msg_ok "Installed Bun"
    
    msg_info "Updating and rebuilding ${APP} to v${RELEASE} (Patience)"  
    apt install -y git
    rm -rf /opt/homarr
    fetch_and_deploy_gh_release "arunavo4/gitea-mirror"
    cd /opt/gitea-mirror
    bun install
    bun run build
    bun run manage-db init
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
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:4321${CL}"
