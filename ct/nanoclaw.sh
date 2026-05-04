#!/usr/bin/env bash
# DEV-ONLY: point build.func's internal fetches (install script, etc.) at our
# fork's branch. Revert this block + the source line below to the canonical
# community-scripts URLs before opening the PR.
export COMMUNITY_SCRIPTS_URL="${COMMUNITY_SCRIPTS_URL:-https://raw.githubusercontent.com/dooha333/ProxmoxVED/feature/nanoclaw-community-defaults}"
source <(curl -fsSL "$COMMUNITY_SCRIPTS_URL/misc/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: dooha333
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/qwibitai/nanoclaw

APP="NanoClaw"
var_tags="${var_tags:-ai;automation}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-20}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"
var_gpu="${var_gpu:-yes}"
var_tun="${var_tun:-yes}"
var_fuse="${var_fuse:-yes}"
var_ssh="${var_ssh:-yes}"
var_nesting="${var_nesting:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /home/nanoclaw/nanoclaw ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Updating ${APP}"
  $STD sudo -u nanoclaw -H bash -lc '
    set -e
    cd ~/nanoclaw
    git pull --ff-only
    pnpm install --frozen-lockfile
    pnpm run build
    systemctl --user restart "nanoclaw-*" 2>/dev/null || true
  '
  msg_ok "Updated ${APP}"
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} is staged in CT ${BL}${CT_ID}${CL}"
echo -e "${INFO}${YW} Finish setup interactively with:${CL}"
echo -e "${TAB}${GN}pct enter ${CT_ID}${CL}"
echo -e "${TAB}${GN}su - nanoclaw${CL}"
echo -e "${TAB}${GN}cd ~/nanoclaw && bash nanoclaw.sh${CL}"
