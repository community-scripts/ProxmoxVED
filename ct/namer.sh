#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Nanja-at-web
# Co-Author: OpenAI Codex
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/Nanja-at-web/namer

APP="Namer"
var_tags="${var_tags:-media;metadata;python}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
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

  if [[ ! -d /opt/namer ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Stopping Service"
  systemctl stop namer-watchdog
  msg_ok "Stopped Service"

  msg_info "Backing up Configuration"
  cp /etc/namer/namer.cfg /opt/namer.cfg.bak 2>/dev/null || true
  msg_ok "Backed up Configuration"

  msg_info "Reinstalling Test Branch"
  if ! env app="namer" \
    FUNCTIONS_FILE_PATH="$(curl -fsSL "$COMMUNITY_SCRIPTS_URL/misc/install.func")" \
    NAMER_PIP_SPEC="git+https://github.com/Nanja-at-web/namer.git@codex/proxmox-setup-wizard" \
    bash -c "$(curl -fsSL "$COMMUNITY_SCRIPTS_URL/install/namer-install.sh")"; then
    msg_info "Restoring Configuration"
    cp /opt/namer.cfg.bak /etc/namer/namer.cfg 2>/dev/null || true
    rm -f /opt/namer.cfg.bak
    msg_ok "Restored Configuration"

    msg_info "Starting Service"
    systemctl start namer-watchdog
    msg_ok "Started Service"

    msg_error "Failed to reinstall ${APP} from the test branch"
    exit 1
  fi
  msg_ok "Reinstalled Test Branch"

  msg_info "Restoring Configuration"
  cp /opt/namer.cfg.bak /etc/namer/namer.cfg 2>/dev/null || true
  rm -f /opt/namer.cfg.bak
  msg_ok "Restored Configuration"

  msg_info "Starting Service"
  systemctl start namer-watchdog
  msg_ok "Started Service"
  msg_ok "Updated successfully!"
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:6980${CL}"
