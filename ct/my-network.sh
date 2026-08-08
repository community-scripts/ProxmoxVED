#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/../misc/build.func" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_URL:-https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main}/misc/build.func")

# Copyright (c) 2021-2026 community-scripts ORG
# Author: VRB95
# Source: https://github.com/VRB95/WatchYourLAN-MobileUI

APP="myNetwork"
var_tags="${var_tags:-}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-10}"
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

  if [[ ! -d /opt/mynetwork/.git ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  msg_info "Stopping ${APP}"
  systemctl stop mynetwork
  msg_ok "Stopped ${APP}"

  msg_info "Updating Repository"
  cd /opt/mynetwork
  git fetch origin main
  git reset --hard origin/main
  git clean -fd
  msg_ok "Updated Repository"

  msg_info "Building Frontend"
  cd /opt/mynetwork/frontend

  if [[ -f package-lock.json ]]; then
    $STD npm ci
  else
    $STD npm install
  fi

  $STD npm run build

  mkdir -p /opt/mynetwork/backend/internal/web/public/assets
  rsync -a --delete \
    /opt/mynetwork/frontend/dist/assets/ \
    /opt/mynetwork/backend/internal/web/public/assets/

  msg_ok "Built Frontend"

  msg_info "Building Backend"
  cd /opt/mynetwork/backend

  $STD go mod download

  CGO_ENABLED=0 go build \
    -trimpath \
    -ldflags="-s -w" \
    -o /usr/local/bin/mynetwork.new \
    ./cmd/myNetwork

  mv /usr/local/bin/mynetwork.new /usr/local/bin/mynetwork
  chmod 0755 /usr/local/bin/mynetwork
  msg_ok "Built Backend"

  msg_info "Starting ${APP}"
  systemctl start mynetwork
  msg_ok "Started ${APP}"

  msg_ok "Updated successfully!"
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Access it using the following URL:${CL}"
echo -e "${GATEWAY}${BGN}http://${IP}:8840${CL}"
