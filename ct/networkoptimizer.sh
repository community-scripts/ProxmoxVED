#!/usr/bin/env bash
# Engine comes from community-scripts/core; this repo only ships the scripts.
# A local core checkout wins (COMMUNITY_SCRIPTS_CORE_DIR, else a sibling ../core),
# so a fork or branch of core can be tested without editing this file.
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/shared/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/shared/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: MickLesk (CanbiZ)
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/Ozark-Connect/NetworkOptimizer

APP="NetworkOptimizer"
var_tags="${var_tags:-network;monitoring;unifi}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-12}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/networkoptimizer ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "networkoptimizer" "Ozark-Connect/NetworkOptimizer"; then
    msg_info "Stopping Service"
    systemctl stop networkoptimizer
    msg_ok "Stopped Service"

    msg_info "Backing up Configuration"
    cp /opt/networkoptimizer/networkoptimizer.env /opt/networkoptimizer.env.bak
    msg_ok "Backed up Configuration"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "networkoptimizer" "Ozark-Connect/NetworkOptimizer" "tarball"

    msg_info "Rebuilding NetworkOptimizer"
    RID="linux-x64"
    [[ "$(dpkg --print-architecture)" == "arm64" ]] && RID="linux-arm64"
    cd /opt/networkoptimizer
    $STD dotnet publish src/NetworkOptimizer.Web -c Release -r "$RID" --self-contained -o /opt/networkoptimizer/publish
    chmod +x /opt/networkoptimizer/publish/NetworkOptimizer.Web
    mkdir -p /opt/networkoptimizer/publish/tools
    cd /opt/networkoptimizer/src/uwnspeedtest
    CGO_ENABLED=0 GOOS=linux GOARCH=arm64 $STD go build -trimpath -ldflags "-s -w" -o /opt/networkoptimizer/publish/tools/uwnspeedtest-linux-arm64 .
    msg_ok "Rebuilt NetworkOptimizer"

    msg_info "Restoring Configuration"
    cp /opt/networkoptimizer.env.bak /opt/networkoptimizer/networkoptimizer.env
    rm -f /opt/networkoptimizer.env.bak
    msg_ok "Restored Configuration"

    msg_info "Starting Service"
    systemctl start networkoptimizer
    msg_ok "Started Service"
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
echo -e "${GATEWAY}${BGN}http://${IP}:8042${CL}"
