#!/usr/bin/env bash
COMMUNITY_SCRIPTS_URL="${COMMUNITY_SCRIPTS_URL:-https://raw.githubusercontent.com/community-unscripted/ProxmoxVED/refs/heads/Hermes-Agent}"
source <(curl -fsSL ${COMMUNITY_SCRIPTS_URL}/misc/build.func)

# Copyright (c) 2021-2026 community-scripts ORG
# Author: community-scripts
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/NousResearch/hermes-agent

APP="Hermes Agent"
var_tags="${var_tags:-ai;agent;llm;automation}"
var_cpu="${var_cpu:-8}"
var_ram="${var_ram:-16384}"
var_disk="${var_disk:-50}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
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

  if [[ ! -d /opt/hermes-agent ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "hermes-agent" "NousResearch/hermes-agent"; then
    msg_info "Stopping Service"
    systemctl stop hermes-agent
    msg_ok "Stopped Service"

    msg_info "Backing up Configuration"
    cp -r /root/.hermes /opt/hermes_backup 2>/dev/null || true
    cp /opt/hermes-agent/.env /opt/hermes_env.bak 2>/dev/null || true
    msg_ok "Backed up Configuration"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "hermes-agent" "NousResearch/hermes-agent" "tarball"

    msg_info "Installing Python Dependencies"
    cd /opt/hermes-agent
    $STD uv venv .venv --python 3.12
    $STD uv pip install -e ".[all]"
    msg_ok "Installed Python Dependencies"

    msg_info "Restoring Configuration"
    cp -r /opt/hermes_backup/. /root/.hermes 2>/dev/null || true
    cp /opt/hermes_env.bak /opt/hermes-agent/.env 2>/dev/null || true
    rm -rf /opt/hermes_backup /opt/hermes_env.bak
    msg_ok "Restored Configuration"

    msg_info "Starting Service"
    systemctl start hermes-agent
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8000${CL}"
echo -e "${INFO}${YW} Or use the CLI: hermes${CL}"