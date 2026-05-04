#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: glifocat
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/qwibitai/nanoclaw

APP="NanoClaw"
var_tags="${var_tags:-bot;chat;docker}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-8192}"
var_disk="${var_disk:-60}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"
var_keyctl="${var_keyctl:-1}"

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
  msg_info "Updating $APP"
  $STD su - nanoclaw -c "cd nanoclaw && git fetch --all --prune && git pull --ff-only"
  $STD su - nanoclaw -c "cd nanoclaw && pnpm install --prefer-frozen-lockfile && pnpm run build"
  msg_ok "Updated $APP"
  exit
}

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been initialized!${CL}"
echo -e "${INFO}${YW} NanoClaw needs an interactive setup wizard. Run it now:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}pct enter ${CT_ID}${CL}"
echo -e "${TAB}${GATEWAY}${BGN}su - nanoclaw -c 'cd nanoclaw && bash nanoclaw.sh'${CL}"
