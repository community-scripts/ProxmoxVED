#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../misc/build.func" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_URL:-https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main}/misc/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/NeptuneHub/AudioMuse-AI

APP="AudioMuse-AI"
var_tags="${var_tags:-music;ai}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-8192}"
var_disk="${var_disk:-20}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"
var_arm64="${var_arm64:-no}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/audiomuse-ai ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "audiomuse-ai" "NeptuneHub/AudioMuse-AI"; then
    msg_info "Stopping Services"
    systemctl stop audiomuse-ai audiomuse-ai-worker audiomuse-ai-worker-high audiomuse-ai-janitor
    msg_ok "Stopped Services"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "audiomuse-ai" "NeptuneHub/AudioMuse-AI" "tarball"

    msg_info "Updating Python Environment"
    cd /opt/audiomuse-ai
    $STD uv venv --seed --python 3.11 /opt/audiomuse-ai/.venv
    $STD uv pip install --python /opt/audiomuse-ai/.venv \
      -r /opt/audiomuse-ai/requirements/common.txt \
      -r /opt/audiomuse-ai/requirements/cpu.txt
    msg_ok "Updated Python Environment"

    msg_info "Starting Services"
    systemctl start audiomuse-ai audiomuse-ai-worker audiomuse-ai-worker-high audiomuse-ai-janitor
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
echo -e "${GATEWAY}${BGN}http://${IP}:8000${CL}"
