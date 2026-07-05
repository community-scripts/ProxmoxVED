#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: stout01
# Co-Authors: MickLesk, tremor021 (prior pip/Prisma versions)
# Refactor: Docker Compose official stack (community contribution preserved)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/BerriAI/litellm

APP="LiteLLM"
var_tags="${var_tags:-ai;proxy;llm}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-20}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_nesting="${var_nesting:-1}"
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

  msg_info "Updating LiteLLM (Docker Compose)"
  cd /opt/litellm
  $STD docker compose pull
  $STD docker compose up -d
  msg_ok "Updated LiteLLM containers"

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
