#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Nik Pottbecker (nikpottbecker)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/nikpottbecker/openvoice-ai

APP="OpenVoice AI"
var_tags="${var_tags:-ai;communication;phone}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-6144}"
var_disk="${var_disk:-20}"
var_os="${var_os:-debian}"
var_version="${var_version:-12}"
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

  if [[ ! -d /opt/phone-agent ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "openvoice-ai" "nikpottbecker/openvoice-ai"; then
    msg_info "Stopping Services"
    systemctl stop phone-agent-dashboard asterisk
    msg_ok "Stopped Services"

    msg_info "Backing up Data"
    mkdir -p /opt/openvoice-ai_backup
    cp -a /opt/phone-agent/.env /opt/openvoice-ai_backup/.env 2>/dev/null || true
    cp -a /opt/phone-agent/recordings /opt/openvoice-ai_backup/recordings 2>/dev/null || true
    cp -a /opt/phone-agent/transcripts /opt/openvoice-ai_backup/transcripts 2>/dev/null || true
    cp -a /opt/phone-agent/logs /opt/openvoice-ai_backup/logs 2>/dev/null || true
    msg_ok "Backed up Data"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "openvoice-ai" "nikpottbecker/openvoice-ai" "tarball" "latest" "/opt/phone-agent"

    msg_info "Updating Python Environment"
    cd /opt/phone-agent
    $STD python3 -m venv .venv
    $STD .venv/bin/pip install --upgrade pip wheel
    $STD .venv/bin/pip install -r requirements.txt
    msg_ok "Updated Python Environment"

    msg_info "Restoring Data"
    cp -a /opt/openvoice-ai_backup/.env /opt/phone-agent/.env 2>/dev/null || true
    cp -a /opt/openvoice-ai_backup/recordings /opt/phone-agent/recordings 2>/dev/null || true
    cp -a /opt/openvoice-ai_backup/transcripts /opt/phone-agent/transcripts 2>/dev/null || true
    cp -a /opt/openvoice-ai_backup/logs /opt/phone-agent/logs 2>/dev/null || true
    rm -rf /opt/openvoice-ai_backup
    msg_ok "Restored Data"

    msg_info "Starting Services"
    systemctl start asterisk phone-agent-dashboard
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
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8088${CL}"
