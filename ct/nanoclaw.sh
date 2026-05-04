#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: dooha333
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/qwibitai/nanoclaw

APP="NanoClaw"
var_tags="ai;automation"
var_cpu="2"
var_ram="4096"
var_disk="25"
var_os="debian"
var_version="13"
var_unprivileged="1"
var_gpu="yes"
var_tun="yes"
var_fuse="yes"
var_ssh="yes"
var_nesting="1"
var_keyctl="1"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /home/nanoclaw/nanoclaw-v2 ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  # The clone exists right after install, but the interactive wizard
  # (bash nanoclaw.sh) is what installs Node/pnpm/Docker. Without it,
  # the update commands below would fail with confusing errors. Use
  # pnpm presence as the proxy for "wizard ran successfully".
  if ! sudo -u nanoclaw -H bash -lc 'command -v pnpm' &>/dev/null; then
    msg_error "${APP} setup not finished — run 'su - nanoclaw && cd ~/nanoclaw-v2 && bash nanoclaw.sh' first"
    exit
  fi

  msg_info "Updating ${APP}"
  $STD sudo -u nanoclaw -H bash -lc '
    set -e
    cd ~/nanoclaw-v2
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
echo -e "${TAB}${GN}cd ~/nanoclaw-v2 && bash nanoclaw.sh${CL}"
