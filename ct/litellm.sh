#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: stout01
# Co-Authors: MickLesk, tremor021 (prior pip/Prisma versions)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/BerriAI/litellm

APP="LiteLLM"
var_tags="${var_tags:-ai;proxy;llm}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-2048}"
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
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f /opt/litellm/litellm.yaml ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "litellm" "BerriAI/litellm"; then
    msg_info "Stopping LiteLLM"
    systemctl stop litellm
    msg_ok "Stopped LiteLLM"

    create_backup /opt/litellm/litellm.yaml

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "litellm" "BerriAI/litellm" "tarball" "latest" "/opt/litellm"

    restore_backup

    msg_info "Updating LiteLLM Python environment (Patience)"
    cd /opt/litellm
    $STD uv pip install --python .venv/bin/python -e ".[proxy]"
    DATABASE_URL=$(grep 'database_url:' /opt/litellm/litellm.yaml | awk '{print $2}')
    export DATABASE_URL
    export PATH="/opt/litellm/.venv/bin:${PATH}"
    $STD .venv/bin/prisma generate --schema=/opt/litellm/schema.prisma
    msg_ok "Updated LiteLLM"

    msg_info "Starting LiteLLM"
    systemctl start litellm
    msg_ok "Started LiteLLM"
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
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:4000${CL}"
echo -e "${INFO}${YW} Master key saved to:${CL} ${TAB}${BGN}~/litellm.creds${CL}"
