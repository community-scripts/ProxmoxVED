#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: piotrlaczykowski
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/vllm-project/vllm

APP="vLLM"
var_tags="${var_tags:-ai;llm}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-8192}"
var_disk="${var_disk:-40}"
var_os="${var_os:-ubuntu}"
var_version="${var_version:-24.04}"
var_unprivileged="${var_unprivileged:-0}"
var_gpu="${var_gpu:-yes}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/vllm ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "vLLM" "vllm-project/vllm"; then
    RELEASE="${CHECK_UPDATE_RELEASE}"
    RELEASE_VERSION="${RELEASE#v}"

    msg_info "Stopping Service"
    systemctl stop vllm
    msg_ok "Stopped Service"

    msg_info "Updating ${APP} to ${RELEASE}"
    $STD uv pip install --python /opt/vllm/.venv/bin/python --upgrade "vllm==${RELEASE_VERSION}"
    msg_ok "Updated ${APP} to ${RELEASE}"

    msg_info "Starting Service"
    systemctl start vllm
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
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8000${CL}"
echo -e "${INFO}${YW} OpenAI-compatible API endpoint:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8000/v1${CL}"
echo -e "${INFO}${YW} Swagger docs:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8000/docs${CL}"
