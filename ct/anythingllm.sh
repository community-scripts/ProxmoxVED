#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../misc/build.func" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_URL:-https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main}/misc/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/Mintplex-Labs/anything-llm

APP="AnythingLLM"
var_tags="${var_tags:-ai;rag}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-20}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_gpu="${var_gpu:-yes}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/anythingllm ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "anythingllm" "Mintplex-Labs/anything-llm"; then
    msg_info "Stopping Services"
    systemctl stop anythingllm anythingllm-collector
    msg_ok "Stopped Services"

    msg_info "Backing up Configuration"
    cp /opt/anythingllm/server/.env /opt/anythingllm-server.env.bak
    cp /opt/anythingllm/collector/.env /opt/anythingllm-collector.env.bak
    cp /opt/anythingllm/frontend/.env /opt/anythingllm-frontend.env.bak
    msg_ok "Backed up Configuration"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "anythingllm" "Mintplex-Labs/anything-llm" "tarball"

    msg_info "Restoring Configuration"
    mv /opt/anythingllm-server.env.bak /opt/anythingllm/server/.env
    mv /opt/anythingllm-collector.env.bak /opt/anythingllm/collector/.env
    mv /opt/anythingllm-frontend.env.bak /opt/anythingllm/frontend/.env
    msg_ok "Restored Configuration"

    msg_info "Building AnythingLLM (Patience)"
    cd /opt/anythingllm
    $STD yarn setup
    cd /opt/anythingllm/frontend
    $STD yarn build
    rm -rf /opt/anythingllm/server/public
    cp -R /opt/anythingllm/frontend/dist /opt/anythingllm/server/public
    cd /opt/anythingllm/server
    $STD npx prisma generate --schema=./prisma/schema.prisma
    $STD npx prisma migrate deploy --schema=./prisma/schema.prisma
    msg_ok "Built AnythingLLM"

    msg_info "Starting Services"
    systemctl start anythingllm anythingllm-collector
    msg_ok "Started Services"
    msg_ok "Updated successfully!"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Access it using the following URL:${CL}"
echo -e "${GATEWAY}${BGN}http://${IP}:3001${CL}"
