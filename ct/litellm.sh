#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: stout01
# Co-Authors: MickLesk, tremor021 (prior pip/Prisma versions)
# Refactor: Docker Compose official stack (community contribution preserved)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/BerriAI/litellm

APP="LiteLLM"
var_tags="${var_tags:-ai;proxy;llm}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-20}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_nesting="${var_nesting:-1}"
var_arm64="${var_arm64:-no}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f /opt/litellm/docker-compose.yml ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "litellm" "BerriAI/litellm"; then
    msg_info "Updating LiteLLM (Docker Compose)"
    cd /opt/litellm
    cp .env /tmp/litellm.env.bak
    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "litellm" "BerriAI/litellm" "tarball" "latest" "/opt/litellm"
    mv /tmp/litellm.env.bak .env
    POSTGRES_PASSWORD=$(grep '^POSTGRES_PASSWORD=' .env | cut -d= -f2- | tr -d '"')
    sed -i "s/dbpassword9090/${POSTGRES_PASSWORD}/g" docker-compose.yml
    sed -i 's/- "5432:5432"/- "127.0.0.1:5432:5432"/' docker-compose.yml
    sed -i 's/- "9090:9090"/- "127.0.0.1:9090:9090"/' docker-compose.yml
    $STD docker compose pull
    $STD docker compose up -d
    msg_ok "Updated LiteLLM containers"
  fi

  msg_ok "Updated successfully!"
  exit
}

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:4000${CL}"
echo -e "${INFO}${YW} Master key saved to:${CL} ${TAB}${BGN}~/litellm.creds${CL}"
