#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://mealie.io

APP="Mealie"
var_tags="${var_tags:-recipes}"
var_cpu="${var_cpu:-5}"
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

  if [[ ! -d /opt/mealie ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  if check_for_gh_release "mealie" "mealie-recipes/mealie"; then
    PYTHON_VERSION="3.12" setup_uv
    NODE_MODULE="yarn" NODE_VERSION="24" setup_nodejs

    msg_info "Stopping Service"
    systemctl stop mealie
    msg_ok "Stopped Service"

    msg_info "Backing up configuration"
    mkdir -p /opt/mealie_bak
    cp -f /opt/mealie/mealie.env /opt/mealie_bak/mealie.env.bak
    cp -f /opt/mealie/start.sh /opt/mealie_bak/start.sh.bak
    msg_ok "Backup completed"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "mealie" "mealie-recipes/mealie" "tarball" "latest" "/opt/mealie"

    msg_info "Rebuilding Frontend"
    export NUXT_TELEMETRY_DISABLED=1
    cd /opt/mealie/frontend
    $STD yarn install --prefer-offline --frozen-lockfile --non-interactive --production=false --network-timeout 1000000
    $STD yarn generate
    cp -r /opt/mealie/frontend/dist/* /opt/mealie/mealie/frontend/
    msg_ok "Frontend rebuilt"

    msg_info "Updating Python Dependencies"
    cd /opt/mealie
    $STD uv sync --frozen --extra pgsql
    msg_ok "Dependencies updated"

    msg_info "Restoring configuration"
    grep -q "^SECRET=" /opt/mealie_bak/mealie.env.bak || echo "SECRET=$(openssl rand -hex 32)" >>/opt/mealie_bak/mealie.env.bak
    grep -q "^MEALIE_HOME=" /opt/mealie_bak/mealie.env.bak || echo "MEALIE_HOME=/opt/mealie" >>/opt/mealie_bak/mealie.env.bak
    grep -q "^NLTK_DATA=" /opt/mealie_bak/mealie.env.bak || echo "NLTK_DATA=/nltk_data" >>/opt/mealie_bak/mealie.env.bak

    mv -f /opt/mealie_bak/mealie.env.bak /opt/mealie/mealie.env
    mv -f /opt/mealie_bak/start.sh.bak /opt/mealie/start.sh
    chmod +x /opt/mealie/start.sh
    sed -i 's|exec .*|source /opt/mealie/.venv/bin/activate\nexec uv run mealie|' /opt/mealie/start.sh
    msg_ok "Configuration restored"

    msg_info "Starting Service"
    systemctl start mealie
    msg_ok "Started Service"
    msg_ok "Updated successfully"
  fi

  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:9000${CL}"
