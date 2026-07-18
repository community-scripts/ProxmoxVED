#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../misc/build.func" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_URL:-https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main}/misc/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/stoatchat/stoatchat

APP="Stoatchat"
var_tags="${var_tags:-chat;messaging;community}"
var_cpu="${var_cpu:-4}"
var_ram="${var_ram:-10240}"
var_disk="${var_disk:-30}"
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

  if [[ ! -d /opt/stoatchat ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "stoatchat" "stoatchat/stoatchat"; then
    msg_info "Stopping Services"
    systemctl stop stoatchat-api stoatchat-events stoatchat-autumn stoatchat-january stoatchat-crond
    msg_ok "Stopped Services"

    create_backup /Revolt.toml

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "stoatchat" "stoatchat/stoatchat" "tarball"

    msg_info "Rebuilding Backend (Patience)"
    cd /opt/stoatchat
    CARGO_PROFILE_RELEASE_LTO=thin \
      $STD cargo build --release --bins -j 2
    msg_ok "Rebuilt Backend"

    msg_info "Updating Web Frontend"
    FORWEB_VERSION=$(get_latest_github_release "stoatchat/for-web")
    $STD git -C /opt/stoatchat-web fetch --tags
    $STD git -C /opt/stoatchat-web checkout "$FORWEB_VERSION"
    $STD git -C /opt/stoatchat-web submodule update --init --recursive
    cd /opt/stoatchat-web
    $STD pnpm install --frozen-lockfile
    $STD pnpm --filter stoat.js build
    $STD pnpm --filter solid-livekit-components build
    $STD pnpm --filter "@lingui-solid/babel-plugin-lingui-macro" build
    $STD pnpm --filter "@lingui-solid/babel-plugin-extract-messages" build
    $STD pnpm --filter client exec lingui compile --typescript
    $STD pnpm --filter client exec node scripts/copyAssets.mjs
    $STD pnpm --filter client exec panda codegen
    $STD pnpm --filter client exec vite build
    msg_ok "Updated Web Frontend"

    restore_backup

    msg_info "Starting Services"
    systemctl start stoatchat-api stoatchat-events stoatchat-autumn stoatchat-january stoatchat-crond
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
echo -e "${GATEWAY}${BGN}http://${IP}${CL}"
