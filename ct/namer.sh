#!/usr/bin/env bash
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Nanja-at-web
# Co-Author: OpenAI Codex
# License: MIT
# Source: https://github.com/Nanja-at-web/namer
# Description: ProxmoxVED container wrapper for Namer with wizard-first NAS onboarding

source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)

APP="Namer"
var_tags="media;metadata;python"
var_cpu="2"
var_ram="2048"
var_disk="8"
var_os="debian"
var_version="12"
var_unprivileged="1"

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

  if [[ ! -f /opt/namer_version.txt ]]; then
    msg_error "No ${APP} version file found at /opt/namer_version.txt"
    exit 1
  fi

  msg_info "Checking latest ${APP} release"
  RELEASE=$(curl -fsSL https://pypi.org/pypi/namer/json | grep '"version"' | head -n1 | awk -F'"' '{print $4}')
  if [[ -z "${RELEASE}" ]]; then
    msg_error "Unable to determine latest ${APP} release from PyPI"
    exit 1
  fi

  CURRENT=$(cat /opt/namer_version.txt)
  if [[ "${RELEASE}" == "${CURRENT}" ]]; then
    msg_ok "No update required. ${APP} is already at v${RELEASE}."
    exit
  fi

  msg_info "Updating ${APP} from v${CURRENT} to v${RELEASE}"
  if ! pct exec "$CTID" -- bash -lc 'export NAMER_PIP_SPEC="namer"; bash /opt/namer/namer-install.sh'; then
    msg_error "Failed to update ${APP}"
    exit 1
  fi

  msg_ok "Updated ${APP} to v${RELEASE}"
  exit
}

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Open the setup wizard using the container address on port 6980.${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:6980${CL}"
